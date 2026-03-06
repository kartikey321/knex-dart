import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/error.dart' show DiagnosticSeverity;
import 'package:analyzer/error/listener.dart' show DiagnosticReporter;
import 'package:custom_lint_builder/custom_lint_builder.dart';

import 'package:knex_dart_capabilities/knex_dart_capabilities.dart';
import '../rule_utils.dart';

/// Lint rule: `dialect_unsupported_cte`
///
/// Fires when `.with_()` or `.withRecursive()` is called on a `Knex` instance
/// whose dialect does not support CTEs.
///
/// CTEs are supported by PostgreSQL, MySQL 8+, and SQLite 3.35+.
/// This rule only fires for dialects we can statically resolve.
class DialectUnsupportedCteRule extends DartLintRule {
  DialectUnsupportedCteRule() : super(code: _code);

  static const LintCode _code = LintCode(
    name: 'dialect_unsupported_cte',
    problemMessage:
        'CTEs (WITH / WITH RECURSIVE) are not supported by the resolved {0} driver.',
    correctionMessage:
        'Use PostgreSQL, MySQL 8+, or SQLite 3.35+ for CTE support.',
    errorSeverity: DiagnosticSeverity.WARNING,
  );

  // NOTE: All three currently-supported dialects (postgres, mysql, sqlite)
  // include `cte` in the capability matrix, so this rule is inert for now.
  // It will fire if older dialect variants (e.g. MySQL 5.6) are added later.
  static const _targetMethods = {'withQuery', 'withRecursive'};

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
        capability: SqlCapability.cte,
      );
    });
  }
}
