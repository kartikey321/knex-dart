import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/error.dart' show DiagnosticSeverity;
import 'package:analyzer/error/listener.dart' show DiagnosticReporter;
import 'package:custom_lint_builder/custom_lint_builder.dart';

import 'package:knex_dart_capabilities/knex_dart_capabilities.dart';
import '../rule_utils.dart';

/// Lint rule: `dialect_unsupported_window_functions`
///
/// Fires when `.over()` or `.analytic()` is called on a `Knex` instance
/// whose resolved dialect does not support window functions.
///
/// Window functions are supported in PostgreSQL, MySQL 8+, and SQLite 3.25+.
class DialectUnsupportedWindowFunctionsRule extends DartLintRule {
  DialectUnsupportedWindowFunctionsRule() : super(code: _code);

  static const LintCode _code = LintCode(
    name: 'dialect_unsupported_window_functions',
    problemMessage:
        'Window functions (OVER / PARTITION BY) are not supported by the resolved {0} driver.',
    correctionMessage:
        'Use PostgreSQL, MySQL 8+, or SQLite 3.25+ for window function support.',
    errorSeverity: DiagnosticSeverity.WARNING,
  );

  // NOTE: All three currently-supported dialects include `windowFunctions` in
  // the capability matrix, so this rule is inert for now.
  // It will fire if older dialect variants (e.g. MySQL 5.7) are added later.
  static const _targetMethods = {
    'rowNumber',
    'rank',
    'denseRank',
    'lead',
    'lag',
    'firstValue',
    'lastValue',
    'nthValue',
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
        capability: SqlCapability.windowFunctions,
      );
    });
  }
}
