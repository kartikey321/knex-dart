import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/error.dart' show DiagnosticSeverity;
import 'package:analyzer/error/listener.dart' show DiagnosticReporter;
import 'package:custom_lint_builder/custom_lint_builder.dart';

import 'package:knex_dart_capabilities/knex_dart_capabilities.dart';
import '../rule_utils.dart';

/// Lint rule: `dialect_unsupported_intersect_except`
///
/// Fires when `.intersect()` or `.except()` is called on a `Knex` instance
/// whose resolved dialect does not support INTERSECT / EXCEPT set operations.
///
/// Supported: PostgreSQL, SQLite.
/// Not reliably supported: MySQL (requires 8.0.31+, not yet in the matrix).
class DialectUnsupportedIntersectExceptRule extends DartLintRule {
  DialectUnsupportedIntersectExceptRule() : super(code: _code);

  static const LintCode _code = LintCode(
    name: 'dialect_unsupported_intersect_except',
    problemMessage:
        'INTERSECT / EXCEPT are not supported by the resolved {0} driver.',
    correctionMessage:
        'Use PostgreSQL or SQLite for INTERSECT/EXCEPT. '
        'MySQL requires 8.0.31+ and is not currently in the support matrix.',
    errorSeverity: DiagnosticSeverity.WARNING,
  );

  static const _targetMethods = {
    'intersect',
    'intersectAll',
    'except',
    'exceptAll',
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
        capability: SqlCapability.intersectExcept,
      );
    });
  }
}
