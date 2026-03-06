import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/error.dart' show DiagnosticSeverity;
import 'package:analyzer/error/listener.dart' show DiagnosticReporter;
import 'package:custom_lint_builder/custom_lint_builder.dart';

import 'package:knex_dart_capabilities/knex_dart_capabilities.dart';
import '../rule_utils.dart';

/// Lint rule: `dialect_unsupported_json`
///
/// Fires when JSON-specific query methods are called on a `Knex` instance
/// whose resolved dialect does not support JSON operators.
///
/// Full JSON support: PostgreSQL only.
/// Partial support (JSON path functions only): MySQL 5.7+.
/// Not supported: SQLite.
class DialectUnsupportedJsonRule extends DartLintRule {
  DialectUnsupportedJsonRule() : super(code: _code);

  static const LintCode _code = LintCode(
    name: 'dialect_unsupported_json',
    problemMessage:
        'JSON operators/functions are not supported by the resolved {0} driver.',
    correctionMessage:
        'Use PostgreSQL for full JSON support, or MySQL 5.7+ for basic JSON functions. '
        'SQLite has no native JSON type.',
    errorSeverity: DiagnosticSeverity.WARNING,
  );

  // Only methods that actually exist on QueryBuilder / JsonQueryBuilder extension.
  static const _targetMethods = {
    'whereJsonObject',
    'orWhereJsonObject',
    'whereJsonPath',
    'orWhereJsonPath',
    'whereJsonSupersetOf',
    'orWhereJsonSupersetOf',
    'whereJsonSubsetOf',
    'orWhereJsonSubsetOf',
  };

  @override
  void run(
    CustomLintResolver resolver,
    DiagnosticReporter reporter,
    CustomLintContext context,
  ) {
    context.registry.addMethodInvocation((MethodInvocation node) {
      if (!_targetMethods.contains(node.methodName.name)) return;

      reportIfUnsupported(
        node: node,
        reporter: reporter,
        code: _code,
        capability: SqlCapability.json,
      );
    });
  }
}
