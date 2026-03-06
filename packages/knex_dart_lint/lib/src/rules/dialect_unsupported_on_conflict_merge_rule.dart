import 'package:analyzer/error/listener.dart' show DiagnosticReporter;
import 'package:custom_lint_builder/custom_lint_builder.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/error.dart' show DiagnosticSeverity;

import 'package:knex_dart_capabilities/knex_dart_capabilities.dart';
import '../dialect_resolution.dart';
import '../rule_utils.dart';

class DialectUnsupportedOnConflictMergeRule extends DartLintRule {
  DialectUnsupportedOnConflictMergeRule() : super(code: _code);

  static const LintCode _code = LintCode(
    name: 'dialect_unsupported_on_conflict_merge',
    problemMessage:
        'onConflict().merge() is not supported by the resolved {0} driver.',
    correctionMessage:
        'Use dialect-specific upsert support available for your driver or refactor query strategy.',
    errorSeverity: DiagnosticSeverity.WARNING,
  );

  @override
  void run(
    CustomLintResolver resolver,
    DiagnosticReporter reporter,
    CustomLintContext context,
  ) {
    context.registry.addMethodInvocation((MethodInvocation node) {
      if (node.methodName.name != 'merge') return;
      if (!hasOnConflictInChain(node)) return;

      reportIfUnsupported(
        node: node,
        reporter: reporter,
        code: _code,
        capability: SqlCapability.onConflictMerge,
      );
    });
  }
}
