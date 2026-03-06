import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/error.dart' show DiagnosticSeverity;
import 'package:analyzer/error/listener.dart' show DiagnosticReporter;
import 'package:custom_lint_builder/custom_lint_builder.dart';

/// Lint rule: `where_null_value`
///
/// Fires when `.where(col, null)` or `.where(col, '=', null)` is used.
///
/// This produces `WHERE col = NULL` which always returns 0 rows in SQL
/// (the correct form is `WHERE col IS NULL`). Use `.whereNull(col)` instead.
///
/// ```dart
/// // ❌ Flagged — produces WHERE col = NULL (always false)
/// db('users').where('deleted_at', null);
/// db('users').where('deleted_at', '=', null);
///
/// // ✅ Correct
/// db('users').whereNull('deleted_at');
/// ```
class WhereNullValueRule extends DartLintRule {
  WhereNullValueRule() : super(code: _code);

  static const LintCode _code = LintCode(
    name: 'where_null_value',
    problemMessage:
        'Passing null to .where() produces `col = NULL` which is always false in SQL.',
    correctionMessage:
        'Use .whereNull(col) or .whereNotNull(col) to check for NULL values.',
    errorSeverity: DiagnosticSeverity.WARNING,
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
