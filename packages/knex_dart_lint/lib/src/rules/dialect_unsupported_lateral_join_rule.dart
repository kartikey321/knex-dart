import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:knex_dart_capabilities/knex_dart_capabilities.dart';

import '../rule_utils.dart';

class DialectUnsupportedLateralJoinRule extends AnalysisRule {
  static const LintCode code = LintCode(
    'dialect_unsupported_lateral_join',
    'LATERAL JOIN is not supported by the resolved {0} driver.',
    severity: DiagnosticSeverity.WARNING,
    uniqueName: 'knex_dart_lint.dialect_unsupported_lateral_join',
  );

  DialectUnsupportedLateralJoinRule()
    : super(
        name: 'dialect_unsupported_lateral_join',
        description: 'LATERAL JOIN is not supported by all drivers.',
      );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addMethodInvocation(this, _Visitor(this));
  }
}

const _lateralJoinMethods = {'joinLateral', 'leftJoinLateral', 'crossJoinLateral'};

class _Visitor extends SimpleAstVisitor<void> {
  final AnalysisRule rule;
  _Visitor(this.rule);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (!_lateralJoinMethods.contains(node.methodName.name)) return;
    reportIfUnsupported(
      node: node,
      rule: rule,
      capability: SqlCapability.lateralJoin,
    );
  }
}
