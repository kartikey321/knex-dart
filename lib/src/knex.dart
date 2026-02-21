import 'client/client.dart';
import 'client/knex_config.dart';
import 'client/mysql_client.dart';
import 'client/sqlite_client.dart';

import 'client/postgres_client.dart';
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

  /// Create a Knex instance connected to PostgreSQL.
  ///
  /// Returns a Knex-like interface that uses PostgresClient internally.
  /// Note: This is a simplified implementation for Phase 1.
  ///
  /// Example:
  /// ```dart
  /// final pg = await KnexPostgres.connect(
  ///   host: 'localhost',
  ///   database: 'myapp',
  ///   username: 'user',
  ///   password: 'password',
  /// );
  ///
  /// final users = await pg.select(
  ///   pg.table('users').where('active', '=', true)
  /// );
  ///
  /// await pg.close();
  /// ```
  static Future<KnexPostgres> postgres({
    required String host,
    int port = 5432,
    required String database,
    required String username,
    String? password,
    bool useSSL = false,
  }) async {
    final client = await PostgresClient.connect(
      host: host,
      port: port,
      database: database,
      username: username,
      password: password,
      useSSL: useSSL,
    );
    return KnexPostgres._(client);
  }

  /// Create a Knex instance connected to MySQL.
  static Future<KnexMySQL> mysql({
    required String host,
    int port = 3306,
    required String user,
    String? password,
    required String database,
    bool useSSL = false,
  }) async {
    final client = await MySQLClient.connect(
      host: host,
      port: port,
      user: user,
      password: password,
      database: database,
      useSSL: useSSL,
    );
    return KnexMySQL._(client);
  }

  /// Create a Knex instance connected to SQLite.
  static Future<KnexSQLite> sqlite({required String filename}) async {
    final client = await SQLiteClient.connect(filename: filename);
    return KnexSQLite._(client);
  }

  static Client _createClient(KnexConfig config) {
    final dialect = config.client.toLowerCase();

    switch (dialect) {
      case 'sqlite':
      case 'sqlite3':
        return SQLiteClient.fromConfig(config);
      case 'postgres':
      case 'postgresql':
      case 'pg':
        throw UnimplementedError(
          'Knex(KnexConfig) with PostgreSQL is not wired yet. '
          'Use Knex.postgres(...) for now.',
        );
      case 'mysql':
      case 'mysql2':
        throw UnimplementedError(
          'Knex(KnexConfig) with MySQL is not wired yet. '
          'Use Knex.mysql(...) for now.',
        );
      default:
        throw UnimplementedError(
          'Unsupported dialect "${config.client}". '
          'Supported in Knex(KnexConfig) right now: sqlite/sqlite3.',
        );
    }
  }
}

/// PostgreSQL-specific Knex wrapper.
class KnexPostgres {
  final PostgresClient _pgClient;

  KnexPostgres._(this._pgClient);

  Future<List<Map<String, dynamic>>> select(QueryBuilder query) =>
      _pgClient.select(query);

  Future<List<Map<String, dynamic>>> execute(QueryBuilder query) =>
      _pgClient.execute(query);

  Future<List<Map<String, dynamic>>> insert(QueryBuilder query) =>
      _pgClient.insert(query);

  Future<List<Map<String, dynamic>>> update(QueryBuilder query) =>
      _pgClient.update(query);

  Future<List<Map<String, dynamic>>> delete(QueryBuilder query) =>
      _pgClient.delete(query);

  /// Execute a raw SQL string directly.
  Future<List<Map<String, dynamic>>> rawSql(
    String sql, [
    List<dynamic>? bindings,
  ]) => _pgClient.rawSql(sql, bindings);

  /// Run a transaction. See [PostgresClient.trx].
  Future<T> trx<T>(Future<T> Function(PostgresTrxClient trx) callback) =>
      _pgClient.trx(callback);

  Future<void> close() => _pgClient.close();
}

/// MySQL-specific Knex wrapper.
class KnexMySQL {
  final MySQLClient _client;

  KnexMySQL._(this._client);

  Future<List<Map<String, dynamic>>> select(QueryBuilder query) =>
      _client.select(query);

  Future<List<Map<String, dynamic>>> execute(QueryBuilder query) =>
      _client.execute(query);

  Future<List<Map<String, dynamic>>> insert(QueryBuilder query) =>
      _client.insert(query);

  Future<List<Map<String, dynamic>>> update(QueryBuilder query) =>
      _client.update(query);

  Future<List<Map<String, dynamic>>> delete(QueryBuilder query) =>
      _client.delete(query);

  Future<List<Map<String, dynamic>>> raw(
    String sql, [
    List<dynamic>? bindings,
  ]) {
    return _client.raw(sql, bindings);
  }

  /// Run a transaction. See [MySQLClient.trx].
  Future<T> trx<T>(Future<T> Function(MySQLTrxClient trx) callback) =>
      _client.trx(callback);

  Future<void> close() => _client.close();
}

/// SQLite-specific Knex wrapper.
class KnexSQLite {
  final SQLiteClient _client;

  KnexSQLite._(this._client);

  Future<List<Map<String, dynamic>>> select(QueryBuilder query) =>
      _client.select(query);

  Future<List<Map<String, dynamic>>> execute(QueryBuilder query) =>
      _client.execute(query);

  Future<List<Map<String, dynamic>>> insert(QueryBuilder query) =>
      _client.insert(query);

  Future<List<Map<String, dynamic>>> update(QueryBuilder query) =>
      _client.update(query);

  Future<List<Map<String, dynamic>>> delete(QueryBuilder query) =>
      _client.delete(query);

  Raw raw(String sql, [List<dynamic>? bindings]) => _client.raw(sql, bindings);

  QueryBuilder queryBuilder() => _client.queryBuilder();

  /// Run a transaction. See [SQLiteClient.trx].
  Future<T> trx<T>(Future<T> Function(SQLiteClient trx) callback) =>
      _client.trx(callback);

  Future<void> close() => _client.close();
}
