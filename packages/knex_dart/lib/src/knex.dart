import 'client/client.dart';
import 'query/query_builder.dart';
import 'schema/schema_builder.dart';
import 'raw.dart';
import 'ref.dart';
import 'migration/migrator.dart';
import 'migration/migration.dart';
import 'migration/migration_source.dart';

/// Main Knex factory class — pure query-builder wrapper.
///
/// Takes a [Client] directly. Use the driver packages to create a client:
///
/// ```dart
/// // SQLite
/// import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';
/// final client = await SQLiteClient.connect(filename: ':memory:');
/// final knex = Knex(client);
///
/// // PostgreSQL
/// import 'package:knex_dart_postgres/knex_dart_postgres.dart';
/// final db = await KnexPostgres.connect(host: '...', database: '...', username: '...', password: '...');
///
/// // MySQL
/// import 'package:knex_dart_mysql/knex_dart_mysql.dart';
/// final db = await KnexMySQL.connect(host: '...', database: '...', user: '...', password: '...');
/// ```
class Knex {
  final Client _client;

  Knex(Client client) : _client = client;

  /// Create a query builder for a table
  ///
  /// If tableName is provided, starts a query on that table.
  /// If null, returns a plain query builder.
  QueryBuilder call([String? tableName]) {
    final builder = _client.queryBuilder();
    return tableName != null ? builder.table(tableName) : builder;
  }

  /// Get the schema builder
  SchemaBuilder get schema => _client.schemaBuilder();

  /// Get the migrator
  Migrator get migrate => Migrator(this, config: _client.config.migrations);

  /// Create a migrator with explicitly registered migration units.
  Migrator migrator({
    List<MigrationUnit> migrations = const [],
    List<MigrationSource> sources = const [],
  }) {
    return Migrator(
      this,
      migrations: migrations,
      sources: sources,
      config: _client.config.migrations,
    );
  }

  /// Create a raw query
  Raw raw(String sql, [dynamic bindings]) {
    return _client.raw(sql, bindings);
  }

  /// Create a column reference
  Ref ref(String columnRef) {
    return _client.ref(columnRef);
  }

  /// Start a transaction
  Future<T> transaction<T>(Future<T> Function(dynamic trx) callback) async {
    throw UnimplementedError('Transaction not yet implemented');
  }

  /// Destroy the connection pool
  Future<void> destroy() => _client.destroy();

  /// Access the underlying client (for advanced use)
  Client get client => _client;
}
