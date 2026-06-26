import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:knex_dart_capabilities/knex_dart_capabilities.dart';

import '../rule_utils.dart';

class DialectUnsupportedReturningRule extends AnalysisRule {
  static const LintCode code = LintCode(
    'dialect_unsupported_returning',
    'The .returning() method is not supported by the resolved {0} driver.',
    correctionMessage:
        'Use PostgreSQL for RETURNING support or refactor to a follow-up SELECT.',
    severity: DiagnosticSeverity.WARNING,
    uniqueName: 'knex_dart_lint.dialect_unsupported_returning',
  );

  DialectUnsupportedReturningRule()
    : super(
        name: 'dialect_unsupported_returning',
        description: 'RETURNING is not supported by all drivers.',
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

const _methodsWithReturningArg = {'insert', 'update', 'delete'};

class _Visitor extends SimpleAstVisitor<void> {
  final AnalysisRule rule;
  _Visitor(this.rule);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'returning') {
      reportIfUnsupported(
        node: node,
        rule: rule,
        capability: SqlCapability.returning,
      );
      return;
    }

    if (!_methodsWithReturningArg.contains(node.methodName.name)) return;
    final args = node.argumentList.arguments;
    if (args.isEmpty) return;
    final lastArg = args.last;
    if (lastArg is NullLiteral) return;
    final isNamedReturning =
        lastArg is NamedExpression &&
        lastArg.name.label.name == 'returning';
    final isPositionalReturning =
        lastArg is! NamedExpression &&
        ((node.methodName.name == 'delete' && args.length == 1) ||
            (node.methodName.name != 'delete' && args.length >= 2));
    if (!isNamedReturning && !isPositionalReturning) return;

    reportIfUnsupported(
      node: node,
      rule: rule,
      capability: SqlCapability.returning,
    );
  }
}
