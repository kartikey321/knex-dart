import 'package:analyzer/error/listener.dart' show DiagnosticReporter;
import 'package:custom_lint_builder/custom_lint_builder.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/error.dart' show DiagnosticSeverity;

import 'package:knex_dart_capabilities/knex_dart_capabilities.dart';
import '../rule_utils.dart';

class DialectUnsupportedFullOuterJoinRule extends DartLintRule {
  DialectUnsupportedFullOuterJoinRule() : super(code: _code);

  static const LintCode _code = LintCode(
    name: 'dialect_unsupported_full_outer_join',
    problemMessage:
        'FULL OUTER JOIN is not supported by the resolved {0} driver.',
    correctionMessage: 'Consider LEFT JOIN + UNION strategy where appropriate.',
    errorSeverity: DiagnosticSeverity.WARNING,
  );

  @override
  void run(
    CustomLintResolver resolver,
    DiagnosticReporter reporter,
    CustomLintContext context,
  ) {
    context.registry.addMethodInvocation((MethodInvocation node) {
      if (node.methodName.name != 'fullOuterJoin') return;

      reportIfUnsupported(
        node: node,
        reporter: reporter,
        code: _code,
        capability: SqlCapability.fullOuterJoin,
      );
    });
  }
}
