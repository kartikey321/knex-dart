import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart' show DiagnosticSeverity;
import 'package:analyzer/error/listener.dart' show DiagnosticReporter;
import 'package:custom_lint_builder/custom_lint_builder.dart';

/// Lint rules that use type inference to catch type-mismatch arguments.
///
/// Only fires when the static type is concretely and provably wrong.
/// Stays silent for `dynamic` arguments to avoid false positives.

// ─────────────────────────────────────────────────────────────────────────────
/// Lint rule: `limit_non_int_argument`
///
/// Fires when `.limit()` or `.offset()` is called with a value whose
/// static type is definitely not `int`.
///
/// ```dart
/// final n = '10';          // String
/// db('users').limit(n);    // ❌ String passed to limit()
///
/// // ✅ Correct
/// db('users').limit(10);
/// db('users').limit(int.parse(n));
/// ```
class LimitNonIntArgumentRule extends DartLintRule {
  LimitNonIntArgumentRule() : super(code: _code);

  static const LintCode _code = LintCode(
    name: 'limit_non_int_argument',
    problemMessage: '.{0}() expects an int argument, but a {1} was passed.',
    correctionMessage:
        'Pass an integer literal or convert with int.parse() / .toInt().',
    errorSeverity: DiagnosticSeverity.WARNING,
  );

  static const _targetMethods = {'limit', 'offset'};

  @override
  void run(
    CustomLintResolver resolver,
    DiagnosticReporter reporter,
    CustomLintContext context,
  ) {
    context.registry.addMethodInvocation((MethodInvocation node) {
      final method = node.methodName.name;
      if (!_targetMethods.contains(method)) return;

      final args = node.argumentList.arguments;
      if (args.isEmpty) return;

      final arg = args.first;
      final type = arg.staticType;
      if (type == null || type is DynamicType) return;

      if (!type.isDartCoreInt) {
        reporter.atNode(
          arg,
          _code,
          arguments: [method, type.getDisplayString()],
        );
      }
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
/// Lint rule: `insert_wrong_value_type`
///
/// Fires when `.insert()` is called with a value whose static type is
/// neither `Map` nor `List`.
///
/// ```dart
/// db('users').insert('name=John');  // ❌ String is wrong
///
/// // ✅ Correct
/// db('users').insert({'name': 'John'});
/// db('users').insert([{'name': 'Alice'}, {'name': 'Bob'}]);
/// ```
class InsertWrongValueTypeRule extends DartLintRule {
  InsertWrongValueTypeRule() : super(code: _code);

  static const LintCode _code = LintCode(
    name: 'insert_wrong_value_type',
    problemMessage:
        '.insert() expects a Map<String, dynamic> or List<Map>, but a {0} was passed.',
    correctionMessage:
        'Pass a map of column→value pairs, or a list of such maps for batch inserts.',
    errorSeverity: DiagnosticSeverity.WARNING,
  );

  @override
  void run(
    CustomLintResolver resolver,
    DiagnosticReporter reporter,
    CustomLintContext context,
  ) {
    context.registry.addMethodInvocation((MethodInvocation node) {
      if (node.methodName.name != 'insert') return;

      final args = node.argumentList.arguments;
      if (args.isEmpty) return;

      final arg = args.first;
      final type = arg.staticType;
      if (type == null || type is DynamicType) return;

      final isMap = type.isDartCoreMap;
      final isList = type.isDartCoreList;
      if (!isMap && !isList) {
        reporter.atNode(arg, _code, arguments: [type.getDisplayString()]);
      }
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
/// Lint rule: `where_null_typed_value`
///
/// Extends [WhereNullValueRule] to also catch variables of `Null` type, not
/// just `null` literal.
///
/// ```dart
/// Null nothing;
/// db('users').where('col', nothing); // ❌ Null-typed variable
///
/// // ✅ Correct
/// db('users').whereNull('col');
/// ```
class WhereNullTypedValueRule extends DartLintRule {
  WhereNullTypedValueRule() : super(code: _code);

  static const LintCode _code = LintCode(
    name: 'where_null_typed_value',
    problemMessage:
        'A Null-typed value was passed to .where(), producing `col = NULL` '
        'which is always false in SQL.',
    correctionMessage: 'Use .whereNull(col) or .whereNotNull(col) instead.',
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

      // 2-arg: where(col, nullVar) — position 1
      // 3-arg: where(col, op, nullVar) — position 2
      final valueIndex = args.length == 2 ? 1 : (args.length == 3 ? 2 : -1);
      if (valueIndex < 0) return;

      final valueArg = args[valueIndex];
      // Skip null literals — those are already caught by WhereNullValueRule
      if (valueArg is NullLiteral) return;

      final type = valueArg.staticType;
      if (type == null) return;

      if (type.isDartCoreNull) {
        reporter.atNode(valueArg, _code);
      }
    });
  }
}
