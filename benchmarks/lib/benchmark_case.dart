import 'package:knex_dart/knex_dart.dart';

typedef BenchmarkBuild = BenchmarkOutput Function(KnexDialect dialect);

enum BenchmarkMode { queryGeneration, schemaGeneration, rawGeneration }

class BenchmarkOutput {
  final String sql;
  final List<dynamic> bindings;
  final String method;
  final int statementCount;

  const BenchmarkOutput({
    required this.sql,
    required this.bindings,
    required this.method,
    this.statementCount = 1,
  });

  factory BenchmarkOutput.fromSqlString(SqlString sql) {
    return BenchmarkOutput(
      sql: sql.sql,
      bindings: sql.bindings,
      method: sql.method ?? 'raw',
    );
  }

  factory BenchmarkOutput.fromSchema(List<Map<String, dynamic>> statements) {
    return BenchmarkOutput(
      sql: statements.map((statement) => statement['sql'] as String).join('; '),
      bindings: [
        for (final statement in statements)
          ...(statement['bindings'] as List<dynamic>? ?? const []),
      ],
      method: 'schema',
      statementCount: statements.length,
    );
  }
}

class BenchmarkCase {
  final String id;
  final String name;
  final String category;
  final BenchmarkMode mode;
  final String complexity;
  final List<String> features;
  final Set<KnexDialect>? dialects;
  final String? notes;
  final BenchmarkBuild build;

  const BenchmarkCase({
    required this.id,
    required this.name,
    required this.category,
    required this.mode,
    required this.complexity,
    required this.features,
    required this.build,
    this.dialects,
    this.notes,
  });

  bool supports(KnexDialect dialect) =>
      dialects == null || dialects!.contains(dialect);

  Map<String, dynamic> toMetadataJson() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'mode': mode.name,
      'complexity': complexity,
      'features': features,
      if (dialects != null)
        'dialects': (dialects!.map((d) => d.name).toList()..sort()),
      if (notes != null) 'notes': notes,
    };
  }
}

const allBenchmarkDialects = [
  KnexDialect.postgres,
  KnexDialect.mysql,
  KnexDialect.sqlite,
  KnexDialect.mariadb,
  KnexDialect.redshift,
  KnexDialect.turso,
  KnexDialect.d1,
  KnexDialect.duckdb,
  KnexDialect.snowflake,
  KnexDialect.bigquery,
  KnexDialect.mssql,
];
