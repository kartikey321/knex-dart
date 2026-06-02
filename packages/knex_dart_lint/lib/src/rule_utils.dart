import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/listener.dart' show DiagnosticReporter;
import 'package:custom_lint_builder/custom_lint_builder.dart';
import 'package:knex_dart_capabilities/knex_dart_capabilities.dart';

import 'dialect_resolution.dart';

String dialectLabel(KnexDialect dialect) {
  switch (dialect) {
    case KnexDialect.postgres:
      return 'postgres';
    case KnexDialect.mysql:
      return 'mysql';
    case KnexDialect.sqlite:
      return 'sqlite';
    case KnexDialect.mariadb:
      return 'mariadb';
    case KnexDialect.redshift:
      return 'redshift';
    case KnexDialect.turso:
      return 'turso';
    case KnexDialect.d1:
      return 'cloudflare-d1';
    case KnexDialect.duckdb:
      return 'duckdb';
    case KnexDialect.snowflake:
      return 'snowflake';
    case KnexDialect.bigquery:
      return 'bigquery';
    case KnexDialect.mssql:
      return 'mssql';
  }
}

void reportIfUnsupported({
  required MethodInvocation node,
  required DiagnosticReporter reporter,
  required LintCode code,
  required SqlCapability capability,
}) {
  final info = resolveDialectForInvocation(node);
  if (!info.isHighConfidence || info.dialect == null) return;

  final dialect = info.dialect!;
  if (supportsCapability(dialect, capability)) return;

  reporter.atNode(node.methodName, code, arguments: [dialectLabel(dialect)]);
}
