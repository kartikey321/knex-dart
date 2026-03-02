import '../knex.dart';
import '../schema/schema_ast.dart';
import '../schema/schema_builder.dart';
import '../util/knex_exception.dart';

/// One executable migration unit with an explicit [name] and reversible steps.
///
/// This is the runtime contract used by the migrator engine.
abstract class MigrationUnit {
  String get name;

  Future<void> up(Knex knex);
  Future<void> down(Knex knex);
}

/// Backward-compatible base type for user-defined migrations.
///
/// New code can implement [MigrationUnit] directly.
abstract class Migration implements MigrationUnit {}

/// SQL-first migration implementation.
///
/// Each entry in [upSql] / [downSql] is executed as one statement.
/// Multi-statement parsing is intentionally not done in core.
class SqlMigration implements MigrationUnit {
  @override
  final String name;
  final List<String> upSql;
  final List<String> downSql;

  const SqlMigration({
    required this.name,
    required this.upSql,
    this.downSql = const [],
  });

  @override
  Future<void> up(Knex knex) async {
    await _executeSqlList(knex, upSql);
  }

  @override
  Future<void> down(Knex knex) async {
    if (downSql.isEmpty) {
      throw KnexMigrationException(
        'Migration "$name" cannot rollback: no downSql provided',
      );
    }
    await _executeSqlList(knex, downSql);
  }
}

/// Migration that projects schema AST into CREATE TABLE DDL.
///
/// Down migration is optional. If [dropOnDown] is false, rollback throws.
class SchemaAstMigration implements MigrationUnit {
  @override
  final String name;
  final KnexSchemaAst schema;
  final bool ifNotExists;
  final bool dropOnDown;

  const SchemaAstMigration({
    required this.name,
    required this.schema,
    this.ifNotExists = false,
    this.dropOnDown = false,
  });

  @override
  Future<void> up(Knex knex) async {
    final builder = knex.schema;
    SchemaAstProjector.projectToCreateTables(
      builder,
      schema,
      ifNotExists: ifNotExists,
    );
    await _executeSchemaBuilder(knex, builder);
  }

  @override
  Future<void> down(Knex knex) async {
    if (!dropOnDown) {
      throw KnexMigrationException(
        'Migration "$name" cannot rollback automatically. '
        'Set dropOnDown=true or provide SqlMigration with downSql.',
      );
    }
    final builder = knex.schema;
    for (final table in schema.tables.reversed) {
      builder.dropTableIfExists(table.name);
    }
    await _executeSchemaBuilder(knex, builder);
  }
}

Future<void> _executeSqlList(Knex knex, List<String> sqlList) async {
  for (final sql in sqlList) {
    final trimmed = sql.trim();
    if (trimmed.isEmpty) continue;
    await knex.client.rawQuery(trimmed, const []);
  }
}

Future<void> _executeSchemaBuilder(Knex knex, SchemaBuilder builder) async {
  final statements = builder.toSQL();
  for (final stmt in statements) {
    final sql = stmt['sql'] as String;
    final bindings = stmt['bindings'] as List<dynamic>? ?? const [];
    await knex.client.rawQuery(sql, bindings);
  }
}
