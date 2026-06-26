import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:knex_dart_capabilities/knex_dart_capabilities.dart';

import '../dialect_resolution.dart';
import '../rule_utils.dart';

class DialectUnsupportedOnConflictMergeRule extends AnalysisRule {
  static const LintCode code = LintCode(
    'dialect_unsupported_on_conflict_merge',
    'onConflict().merge() is not supported by the resolved {0} driver.',
    correctionMessage:
        'Use dialect-specific upsert support available for your driver or refactor query strategy.',
    severity: DiagnosticSeverity.WARNING,
    uniqueName: 'knex_dart_lint.dialect_unsupported_on_conflict_merge',
  );

  DialectUnsupportedOnConflictMergeRule()
    : super(
        name: 'dialect_unsupported_on_conflict_merge',
        description: 'onConflict().merge() is not supported by all drivers.',
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

class _Visitor extends SimpleAstVisitor<void> {
  final AnalysisRule rule;
  _Visitor(this.rule);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name != 'merge') return;
    if (!hasOnConflictInChain(node)) return;
    reportIfUnsupported(
      node: node,
      rule: rule,
      capability: SqlCapability.onConflictMerge,
    );
  }
}
