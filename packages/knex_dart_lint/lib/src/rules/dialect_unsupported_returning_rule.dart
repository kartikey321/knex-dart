import 'package:custom_lint_builder/custom_lint_builder.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/error.dart' show DiagnosticSeverity;
import 'package:analyzer/error/listener.dart' show DiagnosticReporter;

import 'package:knex_dart_capabilities/knex_dart_capabilities.dart';
import '../rule_utils.dart';

class DialectUnsupportedReturningRule extends DartLintRule {
  DialectUnsupportedReturningRule() : super(code: _code);

  static const LintCode _code = LintCode(
    name: 'dialect_unsupported_returning',
    problemMessage:
        'The .returning() method is not supported by the resolved {0} driver.',
    correctionMessage:
        'Use PostgreSQL for RETURNING support or refactor to a follow-up SELECT.',
    errorSeverity: DiagnosticSeverity.WARNING,
  );

  @override
  void run(
    CustomLintResolver resolver,
    DiagnosticReporter reporter,
    CustomLintContext context,
  ) {
    context.registry.addMethodInvocation((MethodInvocation node) {
      if (node.methodName.name != 'returning') return;

      reportIfUnsupported(
        node: node,
        reporter: reporter,
        code: _code,
        capability: SqlCapability.returning,
      );
    });
  }
}
