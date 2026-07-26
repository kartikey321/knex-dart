import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';

// ─────────────────────────────────────────────────────────────────────────────

class LimitNonIntArgumentRule extends AnalysisRule {
  static const LintCode code = LintCode(
    'limit_non_int_argument',
    '.{0}() expects an int argument, but a {1} was passed.',
    correctionMessage:
        'Pass an integer literal or convert with int.parse() / .toInt().',
    severity: DiagnosticSeverity.WARNING,
    uniqueName: 'knex_dart_lint.limit_non_int_argument',
  );

  LimitNonIntArgumentRule()
    : super(
        name: 'limit_non_int_argument',
        description: 'Flags non-int arguments passed to .limit() or .offset().',
      );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addMethodInvocation(this, _LimitNonIntVisitor(this));
  }
}

class _LimitNonIntVisitor extends SimpleAstVisitor<void> {
  final AnalysisRule rule;
  _LimitNonIntVisitor(this.rule);

  static const _targetMethods = {'limit', 'offset'};

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final method = node.methodName.name;
    if (!_targetMethods.contains(method)) return;

    final args = node.argumentList.arguments;
    if (args.isEmpty) return;

    final arg = args.first;
    final type = arg.staticType;
    if (type == null || type is DynamicType) return;

    if (!type.isDartCoreInt) {
      rule.reportAtNode(arg, arguments: [method, type.getDisplayString()]);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class InsertWrongValueTypeRule extends AnalysisRule {
  static const LintCode code = LintCode(
    'insert_wrong_value_type',
    '.insert() expects a Map<String, dynamic> or List<Map>, but a {0} was passed.',
    correctionMessage:
        'Pass a map of column→value pairs, or a list of such maps for batch inserts.',
    severity: DiagnosticSeverity.WARNING,
    uniqueName: 'knex_dart_lint.insert_wrong_value_type',
  );

  InsertWrongValueTypeRule()
    : super(
        name: 'insert_wrong_value_type',
        description: 'Flags wrong value types passed to .insert().',
      );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addMethodInvocation(this, _InsertVisitor(this));
  }
}

class _InsertVisitor extends SimpleAstVisitor<void> {
  final AnalysisRule rule;
  _InsertVisitor(this.rule);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name != 'insert') return;

    final args = node.argumentList.arguments;
    if (args.isEmpty) return;

    final arg = args.first;
    final type = arg.staticType;
    if (type == null || type is DynamicType) return;

    if (!type.isDartCoreMap && !type.isDartCoreList) {
      rule.reportAtNode(arg, arguments: [type.getDisplayString()]);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class WhereNullTypedValueRule extends AnalysisRule {
  static const LintCode code = LintCode(
    'where_null_typed_value',
    'A Null-typed value was passed to .where(), producing `col = NULL` '
        'which is always false in SQL.',
    correctionMessage: 'Use .whereNull(col) or .whereNotNull(col) instead.',
    severity: DiagnosticSeverity.WARNING,
    uniqueName: 'knex_dart_lint.where_null_typed_value',
  );

  WhereNullTypedValueRule()
    : super(
        name: 'where_null_typed_value',
        description: 'Flags Null-typed values passed to .where().',
      );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addMethodInvocation(this, _WhereNullTypedVisitor(this));
  }
}

const _whereTypedMethods = {'where', 'orWhere', 'andWhere'};

class _WhereNullTypedVisitor extends SimpleAstVisitor<void> {
  final AnalysisRule rule;
  _WhereNullTypedVisitor(this.rule);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (!_whereTypedMethods.contains(node.methodName.name)) return;

    final args = node.argumentList.arguments;
    if (args.isEmpty) return;

    final valueIndex = args.length == 2 ? 1 : (args.length == 3 ? 2 : -1);
    if (valueIndex < 0) return;

    final valueArg = args[valueIndex];
    if (valueArg is NullLiteral) return;

    final type = valueArg.staticType;
    if (type == null) return;

    if (type.isDartCoreNull) {
      rule.reportAtNode(valueArg);
    }
  }
}
