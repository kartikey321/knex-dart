import 'package:knex_dart/src/query/query_builder.dart';
import 'package:knex_dart/src/raw.dart';
import 'package:knex_dart/src/schema/schema_builder.dart';

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

  Future<void> close() => _client.close();
}
