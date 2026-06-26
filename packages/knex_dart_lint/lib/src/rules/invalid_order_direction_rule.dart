import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

const _validDirections = {'asc', 'desc'};

class InvalidOrderDirectionRule extends AnalysisRule {
  static const LintCode code = LintCode(
    'invalid_order_direction',
    '"{0}" is not a valid sort direction. Use "asc" or "desc" (lowercase).',
    correctionMessage:
        'Replace with "asc" or "desc". knex_dart is case-sensitive '
        'for order directions.',
    severity: DiagnosticSeverity.WARNING,
    uniqueName: 'knex_dart_lint.invalid_order_direction',
  );

  InvalidOrderDirectionRule()
    : super(
        name: 'invalid_order_direction',
        description: 'Flags invalid orderBy direction strings.',
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
    if (node.methodName.name != 'orderBy') return;

    final args = node.argumentList.arguments;
    if (args.length < 2) return;

    final dirArg = args[1];
    if (dirArg is! StringLiteral) return;

    final dir = dirArg.stringValue;
    if (dir == null) return;

    if (!_validDirections.contains(dir)) {
      rule.reportAtNode(dirArg, arguments: [dir]);
    }
  }
}
