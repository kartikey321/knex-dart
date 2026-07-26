import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:knex_dart_capabilities/knex_dart_capabilities.dart';

import '../rule_utils.dart';

class DialectUnsupportedCteRule extends AnalysisRule {
  static const LintCode code = LintCode(
    'dialect_unsupported_cte',
    'CTEs (WITH / WITH RECURSIVE) are not supported by the resolved {0} driver.',
    correctionMessage:
        'Use PostgreSQL, MySQL 8+, or SQLite 3.35+ for CTE support.',
    severity: DiagnosticSeverity.WARNING,
    uniqueName: 'knex_dart_lint.dialect_unsupported_cte',
  );

  DialectUnsupportedCteRule()
    : super(
        name: 'dialect_unsupported_cte',
        description: 'CTEs are not supported by all drivers.',
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

const _cteTargetMethods = {'withQuery', 'withRecursive'};

class _Visitor extends SimpleAstVisitor<void> {
  final AnalysisRule rule;
  _Visitor(this.rule);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (!_cteTargetMethods.contains(node.methodName.name)) return;
    reportIfUnsupported(node: node, rule: rule, capability: SqlCapability.cte);
  }
}
