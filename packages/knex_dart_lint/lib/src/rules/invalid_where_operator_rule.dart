import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

const _validOps = {
  '=',
  '!=',
  '<>',
  '<',
  '>',
  '<=',
  '>=',
  'like',
  'not like',
  'ilike',
  'not ilike',
  'similar to',
  'not similar to',
  '@>',
  '<@',
  '&&',
  '?',
  '?|',
  '?&',
  '#>>',
  '~~',
  '!~~',
  '~~*',
  '!~~*',
};

const _whereHavingMethods = {'where', 'orWhere', 'andWhere', 'having', 'orHaving'};

class InvalidWhereOperatorRule extends AnalysisRule {
  static const LintCode code = LintCode(
    'invalid_where_operator',
    '"{0}" is not a recognised SQL comparison operator.',
    correctionMessage:
        'Use a valid SQL operator such as =, <>, !=, <, >, <=, >=, like, '
        'not like, ilike, in, not in, between, is, is not — '
        'or an Op constant (Op.eq, Op.gt, Op.like, ...).',
    severity: DiagnosticSeverity.WARNING,
    uniqueName: 'knex_dart_lint.invalid_where_operator',
  );

  InvalidWhereOperatorRule()
    : super(
        name: 'invalid_where_operator',
        description: 'Flags unrecognised SQL comparison operators.',
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
    if (!_whereHavingMethods.contains(node.methodName.name)) return;

    final args = node.argumentList.arguments;
    if (args.length < 3) return;

    final opArg = args[1];
    if (opArg is! StringLiteral) return;

    final op = opArg.stringValue?.toLowerCase();
    if (op == null) return;

    if (!_validOps.contains(op)) {
      rule.reportAtNode(opArg, arguments: [opArg.stringValue ?? op]);
    }
  }
}
