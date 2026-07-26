import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

const _whereNullMethods = {'where', 'orWhere', 'andWhere'};

class WhereNullValueRule extends AnalysisRule {
  // INFO severity (default) — registered as a lint rule requiring opt-in.
  static const LintCode code = LintCode(
    'where_null_value',
    'Prefer .whereNull(col) over .where(col, null) for explicit NULL checks.',
    correctionMessage:
        'Use .whereNull(col) or .whereNotNull(col) — intent is clearer and matches SQL idiom.',
    uniqueName: 'knex_dart_lint.where_null_value',
  );

  WhereNullValueRule()
    : super(
        name: 'where_null_value',
        description: 'Nudges toward .whereNull() over .where(col, null).',
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
    if (!_whereNullMethods.contains(node.methodName.name)) return;

    final args = node.argumentList.arguments;
    if (args.isEmpty) return;

    if (args.length == 2 && args[1] is NullLiteral) {
      rule.reportAtNode(args[1]);
      return;
    }

    if (args.length == 3 && args[2] is NullLiteral) {
      rule.reportAtNode(args[2]);
    }
  }
}
