import 'package:custom_lint_builder/custom_lint_builder.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/error.dart' show DiagnosticSeverity;
import 'package:analyzer/error/listener.dart' show DiagnosticReporter;

import 'package:knex_dart_capabilities/knex_dart_capabilities.dart';
import '../rule_utils.dart';

class DialectUnsupportedLateralJoinRule extends DartLintRule {
  DialectUnsupportedLateralJoinRule() : super(code: _code);

  static const LintCode _code = LintCode(
    name: 'dialect_unsupported_lateral_join',
    problemMessage: 'LATERAL JOIN is not supported by the resolved {0} driver.',
    errorSeverity: DiagnosticSeverity.WARNING,
  );

  static const Set<String> _methods = {
    'joinLateral',
    'leftJoinLateral',
    'crossJoinLateral',
  };

  @override
  void run(
    CustomLintResolver resolver,
    DiagnosticReporter reporter,
    CustomLintContext context,
  ) {
    context.registry.addMethodInvocation((MethodInvocation node) {
      if (!_methods.contains(node.methodName.name)) return;

      reportIfUnsupported(
        node: node,
        reporter: reporter,
        code: _code,
        capability: SqlCapability.lateralJoin,
      );
    });
  }
}
