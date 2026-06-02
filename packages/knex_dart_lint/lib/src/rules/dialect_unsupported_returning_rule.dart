import 'package:custom_lint_builder/custom_lint_builder.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/error.dart' show DiagnosticSeverity;
import 'package:analyzer/error/listener.dart' show DiagnosticReporter;

import 'package:knex_dart_capabilities/knex_dart_capabilities.dart';
import '../rule_utils.dart';

class DialectUnsupportedReturningRule extends DartLintRule {
  DialectUnsupportedReturningRule() : super(code: _code);

  static const LintCode _code = LintCode(
    name: 'dialect_unsupported_returning',
    problemMessage:
        'The .returning() method is not supported by the resolved {0} driver.',
    correctionMessage:
        'Use PostgreSQL for RETURNING support or refactor to a follow-up SELECT.',
    errorSeverity: DiagnosticSeverity.WARNING,
  );

  // Methods that accept an optional `returning` list as their last argument.
  static const _methodsWithReturningArg = {'insert', 'update', 'delete'};

  @override
  void run(
    CustomLintResolver resolver,
    DiagnosticReporter reporter,
    CustomLintContext context,
  ) {
    context.registry.addMethodInvocation((MethodInvocation node) {
      // .returning([...]) chained call
      if (node.methodName.name == 'returning') {
        reportIfUnsupported(
          node: node,
          reporter: reporter,
          code: _code,
          capability: SqlCapability.returning,
        );
        return;
      }

      // insert(values, returning), update(values, returning), delete(returning)
      if (!_methodsWithReturningArg.contains(node.methodName.name)) return;
      final args = node.argumentList.arguments;
      if (args.isEmpty) return;
      final lastArg = args.last;
      // Only flag when a non-null returning argument is explicitly provided.
      if (lastArg is NullLiteral) return;
      final isNamedReturning =
          lastArg is NamedExpression && lastArg.name.label.name == 'returning';
      final isPositionalReturning =
          lastArg is! NamedExpression &&
          ((node.methodName.name == 'delete' && args.length == 1) ||
           (node.methodName.name != 'delete' && args.length >= 2));
      if (!isNamedReturning && !isPositionalReturning) return;

      reportIfUnsupported(
        node: node,
        reporter: reporter,
        code: _code,
        capability: SqlCapability.returning,
      );
    });
  }
}
