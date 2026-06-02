import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/error.dart' show DiagnosticSeverity;
import 'package:analyzer/error/listener.dart' show DiagnosticReporter;
import 'package:custom_lint_builder/custom_lint_builder.dart';

/// Lint rule: `raw_null_identifier_binding`
///
/// Fires when a named `:key:` identifier binding in a `raw()` call is
/// assigned a `null` value.
///
/// `:key:` bindings expand to a quoted identifier in the SQL — they are
/// **never** emitted as a positional parameter.  Passing `null` for an
/// identifier binding silently leaves the original `:key:` placeholder
/// in the SQL, producing invalid SQL at runtime.
///
/// ```dart
/// // ❌ Flagged — :table: stays unresolved; SQL becomes 'SELECT * FROM :table:'
/// db.rawSql('SELECT * FROM :table:', {'table': null});
///
/// // ✅ Use a real table name or omit the binding entirely
/// db.rawSql('SELECT * FROM :table:', {'table': 'users'});
/// ```
class RawNullIdentifierBindingRule extends DartLintRule {
  RawNullIdentifierBindingRule() : super(code: _code);

  static const LintCode _code = LintCode(
    name: 'raw_null_identifier_binding',
    problemMessage:
        'Null value for identifier binding :{0}: — the placeholder will '
        'stay unresolved and produce invalid SQL.',
    correctionMessage:
        'Provide a non-null string for identifier bindings, or remove the key.',
    errorSeverity: DiagnosticSeverity.WARNING,
  );

  static const _rawMethods = {'raw', 'rawSql', 'whereRaw', 'havingRaw', 'orderByRaw', 'groupByRaw'};

  @override
  void run(
    CustomLintResolver resolver,
    DiagnosticReporter reporter,
    CustomLintContext context,
  ) {
    context.registry.addMethodInvocation((MethodInvocation node) {
      if (!_rawMethods.contains(node.methodName.name)) return;

      final args = node.argumentList.arguments;
      if (args.length < 2) return;

      // Second argument must be a map literal: {'key': value, ...}
      final mapArg = args[1];
      if (mapArg is! SetOrMapLiteral) return;

      for (final element in mapArg.elements) {
        if (element is! MapLiteralEntry) continue;
        final key = element.key;
        final value = element.value;

        // Key must be a string literal ending with ':' (identifier binding)
        if (key is! SimpleStringLiteral) continue;
        final keyStr = key.value.trim();
        if (!keyStr.endsWith(':')) continue;

        // Value is a null literal — this binding will stay unresolved.
        if (value is NullLiteral) {
          reporter.atNode(value, _code, arguments: [keyStr]);
        }
      }
    });
  }
}
