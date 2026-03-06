import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/error.dart' show DiagnosticSeverity;
import 'package:analyzer/error/listener.dart' show DiagnosticReporter;
import 'package:custom_lint_builder/custom_lint_builder.dart';

/// Set of valid SQL comparison operators (lowercased).
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

/// Lint rule: `invalid_where_operator`
///
/// Fires when `.where(col, op, val)` or `.having(col, op, val)` is called with
/// a string-literal operator that is not a recognised SQL operator.
///
/// Catches the most common JS-to-Dart mistake: using `'=='` instead of `'='`.
///
/// ```dart
/// // ❌ Flagged — '==' is not a valid SQL operator
/// db('users').where('age', '==', 18);
///
/// // ✅ Correct
/// db('users').where('age', '=', 18);
/// db('users').where('age', Op.eq, 18);
/// ```
class InvalidWhereOperatorRule extends DartLintRule {
  InvalidWhereOperatorRule() : super(code: _code);

  static const LintCode _code = LintCode(
    name: 'invalid_where_operator',
    problemMessage: '"{0}" is not a recognised SQL comparison operator.',
    correctionMessage:
        'Use a valid SQL operator such as =, <>, !=, <, >, <=, >=, like, '
        'not like, ilike, in, not in, between, is, is not — '
        'or an Op constant (Op.eq, Op.gt, Op.like, ...).',
    errorSeverity: DiagnosticSeverity.WARNING,
  );

  static const _targetMethods = {
    'where',
    'orWhere',
    'andWhere',
    'having',
    'orHaving',
  };

  @override
  void run(
    CustomLintResolver resolver,
    DiagnosticReporter reporter,
    CustomLintContext context,
  ) {
    context.registry.addMethodInvocation((MethodInvocation node) {
      if (!_targetMethods.contains(node.methodName.name)) return;

      final args = node.argumentList.arguments;
      // 3-arg form: where(col, op, val)
      if (args.length < 3) return;

      final opArg = args[1];
      if (opArg is! StringLiteral) return;

      final op = opArg.stringValue?.toLowerCase();
      if (op == null) return;

      if (!_validOps.contains(op)) {
        reporter.atNode(opArg, _code, arguments: [opArg.stringValue ?? op]);
      }
    });
  }
}
