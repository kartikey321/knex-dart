import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

const _rawMethods = {'raw', 'rawSql', 'whereRaw', 'havingRaw', 'orderByRaw', 'groupByRaw'};

class RawNullIdentifierBindingRule extends AnalysisRule {
  static const LintCode code = LintCode(
    'raw_null_identifier_binding',
    'Null value for identifier binding :{0}: — the placeholder will '
        'stay unresolved and produce invalid SQL.',
    correctionMessage:
        'Provide a non-null string for identifier bindings, or remove the key.',
    severity: DiagnosticSeverity.WARNING,
    uniqueName: 'knex_dart_lint.raw_null_identifier_binding',
  );

  RawNullIdentifierBindingRule()
    : super(
        name: 'raw_null_identifier_binding',
        description: 'Flags null values for :key: identifier bindings in raw SQL.',
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
    if (!_rawMethods.contains(node.methodName.name)) return;

    final args = node.argumentList.arguments;
    if (args.length < 2) return;

    final mapArg = args[1];
    if (mapArg is! SetOrMapLiteral) return;

    for (final element in mapArg.elements) {
      if (element is! MapLiteralEntry) continue;
      final key = element.key;
      final value = element.value;

      if (key is! SimpleStringLiteral) continue;
      final keyStr = key.value.trim();
      if (!keyStr.endsWith(':')) continue;

      if (value is NullLiteral) {
        rule.reportAtNode(value, arguments: [keyStr]);
      }
    }
  }
}
