import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/error.dart' show DiagnosticSeverity;
import 'package:analyzer/error/listener.dart' show DiagnosticReporter;
import 'package:custom_lint_builder/custom_lint_builder.dart';

/// Valid order direction strings — exact case required.
const _validDirections = {'asc', 'desc'};

/// Lint rule: `invalid_order_direction`
///
/// Fires when `.orderBy(col, dir)` or `.orderByRaw(sql, dir)` is called with
/// a string-literal direction that is not `'asc'` or `'desc'`.
///
/// Catches common mistakes like `'ASC'` (uppercase) or `'ascending'`.
///
/// ```dart
/// // ❌ Flagged — wrong casing / spelling
/// db('users').orderBy('name', 'ASC');
/// db('users').orderBy('name', 'ascending');
///
/// // ✅ Correct — lowercase
/// db('users').orderBy('name', 'asc');
/// db('users').orderBy('name', 'desc');
/// ```
class InvalidOrderDirectionRule extends DartLintRule {
  InvalidOrderDirectionRule() : super(code: _code);

  static const LintCode _code = LintCode(
    name: 'invalid_order_direction',
    problemMessage:
        '"{0}" is not a valid sort direction. Use "asc" or "desc" (lowercase).',
    correctionMessage:
        'Replace with "asc" or "desc". knex_dart is case-sensitive '
        'for order directions.',
    errorSeverity: DiagnosticSeverity.WARNING,
  );

  static const _targetMethods = {'orderBy'};

  @override
  void run(
    CustomLintResolver resolver,
    DiagnosticReporter reporter,
    CustomLintContext context,
  ) {
    context.registry.addMethodInvocation((MethodInvocation node) {
      if (!_targetMethods.contains(node.methodName.name)) return;

      final args = node.argumentList.arguments;
      // orderBy(col, direction) — direction is the second positional arg
      if (args.length < 2) return;

      final dirArg = args[1];
      if (dirArg is! StringLiteral) return;

      final dir = dirArg.stringValue;
      if (dir == null) return;

      if (!_validDirections.contains(dir)) {
        reporter.atNode(dirArg, _code, arguments: [dir]);
      }
    });
  }
}
