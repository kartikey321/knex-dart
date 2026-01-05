import 'client/client.dart';
import 'client/knex_config.dart';
import 'query/query_builder.dart';
import 'schema/schema_builder.dart';
import 'raw.dart';
import 'ref.dart';
import 'migration/migrator.dart';

/// Main Knex factory class
///
/// Example:
/// ```dart
/// final knex = Knex(KnexConfig(
///   client: 'postgres',
///   connection: {'host': 'localhost', 'database': 'mydb'},
/// ));
///
/// final users = await knex('users').select(['*']);
/// ```
class Knex {
  final Client _client;

  Knex(KnexConfig config) : _client = _createClient(config);

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
  Migrator get migrate => Migrator();

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

  static Client _createClient(KnexConfig config) {
    // For now, throw an error - dialects will be implemented in later weeks
    throw UnimplementedError(
      'Dialect "${config.client}" not yet implemented. '
      'PostgreSQL dialect will be added in Phase 2 (Week 4-5).',
    );
  }
}
