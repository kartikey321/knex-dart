import 'package:knex_dart/knex_dart.dart';

import 'sqlite_client.dart';

/// SQLite-specific Knex wrapper.
class KnexSQLite {
  final SQLiteClient _client;

  KnexSQLite._(this._client);

  /// Create a Knex instance connected to SQLite.
  ///
  /// Example:
  /// ```dart
  /// final db = await KnexSQLite.connect(filename: ':memory:');
  /// await db.executeSchema((s) {
  ///   s.createTable('users', (t) {
  ///     t.increments('id');
  ///     t.string('name');
  ///   });
  /// });
  ///
  /// await db.insert(db.queryBuilder().table('users').insert({'name': 'Alice'}));
  /// final rows = await db.select(db.queryBuilder().table('users'));
  /// await db.close();
  /// ```
  static Future<KnexSQLite> connect({required String filename}) async {
    final client = await SQLiteClient.connect(filename: filename);
    return KnexSQLite._(client);
  }

  /// Executes a SELECT-style query and returns rows.
  Future<List<Map<String, dynamic>>> select(QueryBuilder query) =>
      _client.select(query);

  /// Executes any compiled query and returns rows/result payload.
  Future<List<Map<String, dynamic>>> execute(QueryBuilder query) =>
      _client.execute(query);

  /// Executes an INSERT query.
  Future<List<Map<String, dynamic>>> insert(QueryBuilder query) =>
      _client.insert(query);

  /// Executes an UPDATE query.
  Future<List<Map<String, dynamic>>> update(QueryBuilder query) =>
      _client.update(query);

  /// Executes a DELETE query.
  Future<List<Map<String, dynamic>>> delete(QueryBuilder query) =>
      _client.delete(query);

  /// Creates a raw SQL fragment.
  Raw raw(String sql, [List<dynamic>? bindings]) => _client.raw(sql, bindings);

  /// Creates a new query builder bound to this SQLite client.
  QueryBuilder queryBuilder() => _client.queryBuilder();

  /// Get a schema builder for executing DDL against this SQLite database.
  SchemaBuilder get schema => _client.schemaBuilder();

  /// Execute schema DDL operations.
  Future<void> executeSchema(
    void Function(SchemaBuilder schema) callback,
  ) async {
    final builder = _client.schemaBuilder();
    callback(builder);
    await builder.execute();
  }

  /// Run a transaction. See [SQLiteClient.trx].
  Future<T> trx<T>(Future<T> Function(SQLiteClient trx) callback) =>
      _client.trx(callback);

  /// Closes the underlying SQLite database connection.
  Future<void> close() => _client.close();
}
