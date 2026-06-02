import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/error.dart' show DiagnosticSeverity;
import 'package:analyzer/error/listener.dart' show DiagnosticReporter;
import 'package:custom_lint_builder/custom_lint_builder.dart';

/// Lint rule: `where_null_value`
///
/// NOTE: knex_dart's `.where(col, null)` compiler delegates to `whereNull()`
/// and correctly produces `WHERE col IS NULL`. This rule is therefore
/// informational only — it nudges users toward the explicit `.whereNull(col)`
/// form for clarity, not because the implicit form is incorrect.
///
/// ```dart
/// // ⚠️ Works correctly but prefer the explicit form
/// db('users').where('deleted_at', null);
///
/// // ✅ Preferred — intent is clearer
/// db('users').whereNull('deleted_at');
/// ```
class WhereNullValueRule extends DartLintRule {
  WhereNullValueRule() : super(code: _code);

  static const LintCode _code = LintCode(
    name: 'where_null_value',
    problemMessage:
        'Prefer .whereNull(col) over .where(col, null) for explicit NULL checks.',
    correctionMessage:
        'Use .whereNull(col) or .whereNotNull(col) — intent is clearer and matches SQL idiom.',
    errorSeverity: DiagnosticSeverity.INFO,
  );

  static const _targetMethods = {'where', 'orWhere', 'andWhere'};

  @override
  void run(
    CustomLintResolver resolver,
    DiagnosticReporter reporter,
    CustomLintContext context,
  ) {
    context.registry.addMethodInvocation((MethodInvocation node) {
      if (!_targetMethods.contains(node.methodName.name)) return;

      final args = node.argumentList.arguments;
      if (args.isEmpty) return;

      // 2-arg form: where(col, null)
      if (args.length == 2 && _isNullLiteral(args[1])) {
        reporter.atNode(args[1], _code);
        return;
      }

      // 3-arg form: where(col, '=', null)
      if (args.length == 3 && _isNullLiteral(args[2])) {
        reporter.atNode(args[2], _code);
      }
    });
  }

  bool _isNullLiteral(Expression expr) => expr is NullLiteral;
}
