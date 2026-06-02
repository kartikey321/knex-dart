import 'package:knex_dart/knex_dart.dart';

import 'sqlite_client.dart'
    if (dart.library.js_interop) 'sqlite_client_web.dart';

/// SQLite-specific Knex wrapper.
class KnexSQLite {
  final SQLiteClient _client;
  final KnexInterceptorPipeline _pipeline;

  KnexSQLite._(this._client, {required KnexInterceptorPipeline pipeline})
      : _pipeline = pipeline;

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
  static Future<KnexSQLite> connect({
    required String filename,
    List<QueryInterceptor> interceptors = const [],
  }) async {
    final client = await SQLiteClient.connect(filename: filename);
    return KnexSQLite._(
      client,
      pipeline: KnexInterceptorPipeline(
        dbSystem: 'sqlite',
        interceptors: interceptors,
      ),
    );
  }

  /// Executes a SELECT-style query and returns rows.
  Future<List<Map<String, dynamic>>> select(QueryBuilder query) =>
      _pipeline.run(query, () => _client.select(query));

  /// Executes any compiled query and returns rows/result payload.
  Future<List<Map<String, dynamic>>> execute(QueryBuilder query) =>
      _pipeline.run(query, () => _client.execute(query));

  /// Executes an INSERT query.
  Future<List<Map<String, dynamic>>> insert(QueryBuilder query) =>
      _pipeline.run(query, () => _client.insert(query));

  /// Executes an UPDATE query.
  Future<List<Map<String, dynamic>>> update(QueryBuilder query) =>
      _pipeline.run(query, () => _client.update(query));

  /// Executes a DELETE query.
  Future<List<Map<String, dynamic>>> delete(QueryBuilder query) =>
      _pipeline.run(query, () => _client.delete(query));

  /// Creates a raw SQL fragment for use inside QueryBuilder clauses.
  Raw raw(String sql, [List<dynamic>? bindings]) => _client.raw(sql, bindings);

  /// Execute a raw SQL string directly (runs through the interceptor pipeline).
  Future<List<Map<String, dynamic>>> rawSql(
    String sql, [
    List<dynamic>? bindings,
  ]) =>
      _pipeline.runRaw(
        sql,
        bindings ?? const [],
        () async {
          final result = await _client.rawQuery(sql, bindings ?? []);
          return result is List<Map<String, dynamic>> ? result : [];
        },
      );

  /// Creates a new query builder bound to this SQLite client.
  QueryBuilder queryBuilder() => _client.queryBuilder();

  /// Callable shorthand for `queryBuilder().table(name)`.
  QueryBuilder call([String? tableName]) {
    final builder = queryBuilder();
    return tableName != null ? builder.table(tableName) : builder;
  }

  /// Get a schema builder for executing DDL against this SQLite database.
  SchemaBuilder get schema => _client.schemaBuilder();

  /// Execute schema DDL operations.
  Future<void> executeSchema(
    void Function(SchemaBuilder schema) callback,
  ) async {
    final builder = _client.schemaBuilder();
    callback(builder);
    final statements = builder.toSQL();
    for (final stmt in statements) {
      final sql = stmt['sql'] as String;
      final bindings = (stmt['bindings'] as List<dynamic>?) ?? const [];
      await _pipeline.runRaw(
        sql,
        bindings,
        () => _client.rawQuery(sql, bindings),
      );
    }
  }

  /// Streams query results row by row.
  Stream<Map<String, dynamic>> streamQuery(QueryBuilder query) =>
      _pipeline.runStream(query, () {
        final compiled = query.toSQL();
        // SQLiteClient.streamQuery uses the low-level (connection, sql, bindings)
        // signature; connection is ignored — SQLite is single-connection.
        return _client.streamQuery(null, compiled.sql, compiled.bindings);
      });

  /// Run a transaction.
  Future<T> trx<T>(Future<T> Function(KnexSQLiteTransaction tx) callback) =>
      _client.trx((client) {
        final txId = _pipeline.nextUid();
        return callback(KnexSQLiteTransaction._(client, _pipeline, txId));
      });

  /// Closes the underlying SQLite database connection.
  Future<void> close() => _client.close();

  /// Alias for [close].
  Future<void> destroy() => close();
}

// ============================================================================
// WRAPPER-LEVEL TRANSACTION FACADE
// ============================================================================

class KnexSQLiteTransaction extends KnexTransaction {
  final SQLiteClient _client;
  final KnexInterceptorPipeline _pipeline;

  @override
  final String txId;

  KnexSQLiteTransaction._(this._client, this._pipeline, this.txId);

  @override
  QueryBuilder queryBuilder() => _client.queryBuilder();

  @override
  QueryBuilder call([String? tableName]) {
    final builder = queryBuilder();
    return tableName != null ? builder.table(tableName) : builder;
  }

  @override
  Future<List<Map<String, dynamic>>> select(QueryBuilder query) =>
      _pipeline.run(query, () => _client.select(query), txId: txId);

  @override
  Future<List<Map<String, dynamic>>> execute(QueryBuilder query) =>
      _pipeline.run(query, () => _client.execute(query), txId: txId);

  @override
  Future<List<Map<String, dynamic>>> insert(QueryBuilder query) =>
      _pipeline.run(query, () => _client.insert(query), txId: txId);

  @override
  Future<List<Map<String, dynamic>>> update(QueryBuilder query) =>
      _pipeline.run(query, () => _client.update(query), txId: txId);

  @override
  Future<List<Map<String, dynamic>>> delete(QueryBuilder query) =>
      _pipeline.run(query, () => _client.delete(query), txId: txId);

  @override
  Future<List<Map<String, dynamic>>> rawSql(String sql, [List<dynamic>? bindings]) =>
      _pipeline.runRaw(
        sql, bindings ?? const [],
        () async {
          final result = await _client.rawQuery(sql, bindings ?? []);
          return result is List<Map<String, dynamic>> ? result : [];
        },
        txId: txId,
      );

  /// Stream results inside this transaction.
  @override
  Stream<Map<String, dynamic>> streamQuery(QueryBuilder query) =>
      _pipeline.runStream(query, () {
        final compiled = query.toSQL();
        return _client.streamQuery(null, compiled.sql, compiled.bindings);
      }, txId: txId);

  @override
  Future<T> trx<T>(Future<T> Function(KnexTransaction tx) callback) =>
      _client.trx((client) {
        // SQLite manages savepoints internally via its own trx() — no SAVEPOINT
        // SQL flows through the pipeline.  Child txId still carries parent prefix
        // so OTel spans can be correlated by txId hierarchy.
        final childTxId =
            '${txId}_sp_${_pipeline.nextUid()}';
        return callback(
          KnexSQLiteTransaction._(client, _pipeline, childTxId),
        );
      });

}
