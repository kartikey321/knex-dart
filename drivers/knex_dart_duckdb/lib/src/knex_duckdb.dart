import 'package:knex_dart/knex_dart.dart';

import 'duckdb_client.dart'
    if (dart.library.js_interop) 'duckdb_client_web.dart';

/// DuckDB Knex wrapper.
class KnexDuckDB {
  final DuckDBClient _client;
  final KnexInterceptorPipeline _pipeline;

  KnexDuckDB._(this._client, {required KnexInterceptorPipeline pipeline})
      : _pipeline = pipeline;

  static Future<KnexDuckDB> memory({
    List<QueryInterceptor> interceptors = const [],
  }) async =>
      KnexDuckDB._(
        await DuckDBClient.open(':memory:'),
        pipeline: KnexInterceptorPipeline(
          dbSystem: 'duckdb',
          interceptors: interceptors,
        ),
      );

  static Future<KnexDuckDB> file(
    String path, {
    List<QueryInterceptor> interceptors = const [],
  }) async =>
      KnexDuckDB._(
        await DuckDBClient.open(path),
        pipeline: KnexInterceptorPipeline(
          dbSystem: 'duckdb',
          interceptors: interceptors,
        ),
      );

  Future<List<Map<String, dynamic>>> select(QueryBuilder query) =>
      _pipeline.run(query, () => _client.select(query));

  Future<List<Map<String, dynamic>>> execute(QueryBuilder query) =>
      _pipeline.run(query, () => _client.execute(query));

  Future<List<Map<String, dynamic>>> insert(QueryBuilder query) =>
      _pipeline.run(query, () => _client.insert(query));

  Future<List<Map<String, dynamic>>> update(QueryBuilder query) =>
      _pipeline.run(query, () => _client.update(query));

  Future<List<Map<String, dynamic>>> delete(QueryBuilder query) =>
      _pipeline.run(query, () => _client.delete(query));

  /// Execute a raw SQL string directly.
  Future<List<Map<String, dynamic>>> rawSql(
    String sql, [
    List<dynamic>? bindings,
  ]) =>
      _pipeline.runRaw(
        sql,
        bindings ?? const [],
        () => _client.raw(sql, bindings),
      );

  /// Alias for [rawSql].
  Future<List<Map<String, dynamic>>> raw(
    String sql, [
    List<dynamic>? bindings,
  ]) =>
      rawSql(sql, bindings);

  /// Streams query results row by row.
  Stream<Map<String, dynamic>> stream(QueryBuilder query) =>
      _pipeline.runStream(query, () => _client.stream(query));

  QueryBuilder queryBuilder() => _DuckDBSchemaClient().queryBuilder();

  QueryBuilder call([String? tableName]) {
    final builder = queryBuilder();
    return tableName != null ? builder.table(tableName) : builder;
  }

  Future<T> trx<T>(Future<T> Function(KnexDuckDBTransaction tx) callback) =>
      _client.trx((rawTrx) {
        final txId = _pipeline.nextUid();
        return callback(KnexDuckDBTransaction._(rawTrx, _pipeline, txId));
      });

  Future<void> executeSchema(
    void Function(SchemaBuilder schema) callback,
  ) async {
    final mock = _DuckDBSchemaClient();
    final builder = mock.schemaBuilder();
    callback(builder);
    final statements = builder.toSQL();
    for (final stmt in statements) {
      await _pipeline.runRaw(
        stmt['sql'] as String,
        (stmt['bindings'] as List<dynamic>?) ?? const [],
        () => _client.raw(
          stmt['sql'] as String,
          stmt['bindings'] as List<dynamic>?,
        ),
      );
    }
  }

  Future<void> close() => _client.close();

  Future<void> destroy() => close();
}

// ============================================================================
// WRAPPER-LEVEL TRANSACTION FACADE
// ============================================================================

class KnexDuckDBTransaction extends KnexTransaction {
  final DuckDBTrxClient _trx;
  final KnexInterceptorPipeline _pipeline;

  @override
  final String txId;

  KnexDuckDBTransaction._(this._trx, this._pipeline, this.txId);

  @override
  QueryBuilder queryBuilder() => _DuckDBSchemaClient().queryBuilder();

  @override
  QueryBuilder call([String? tableName]) {
    final builder = queryBuilder();
    return tableName != null ? builder.table(tableName) : builder;
  }

  @override
  Future<List<Map<String, dynamic>>> select(QueryBuilder query) =>
      _pipeline.run(query, () => _trx.select(query), txId: txId);

  @override
  Future<List<Map<String, dynamic>>> execute(QueryBuilder query) =>
      _pipeline.run(query, () => _trx.execute(query), txId: txId);

  @override
  Future<List<Map<String, dynamic>>> insert(QueryBuilder query) =>
      _pipeline.run(query, () => _trx.insert(query), txId: txId);

  @override
  Future<List<Map<String, dynamic>>> update(QueryBuilder query) =>
      _pipeline.run(query, () => _trx.update(query), txId: txId);

  @override
  Future<List<Map<String, dynamic>>> delete(QueryBuilder query) =>
      _pipeline.run(query, () => _trx.delete(query), txId: txId);

  @override
  Future<List<Map<String, dynamic>>> rawSql(String sql, [List<dynamic>? bindings]) =>
      _pipeline.runRaw(
        sql, bindings ?? const [],
        () => _trx.raw(sql, bindings),
        txId: txId,
      );

  /// Streams results inside this transaction.
  Stream<Map<String, dynamic>> stream(QueryBuilder query) =>
      _pipeline.runStream(query, () => _trx.stream(query), txId: txId);

  @override
  Stream<Map<String, dynamic>> streamQuery(QueryBuilder query) => stream(query);

  @override
  Future<T> trx<T>(Future<T> Function(KnexTransaction tx) callback) async {
    final sp = 'sp_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    final childTxId = '${txId}_$sp';
    await rawSql('SAVEPOINT $sp');
    try {
      final result = await callback(
        KnexDuckDBTransaction._(_trx, _pipeline, childTxId),
      );
      await rawSql('RELEASE SAVEPOINT $sp');
      return result;
    } catch (e) {
      await rawSql('ROLLBACK TO SAVEPOINT $sp');
      rethrow;
    }
  }
}

// ============================================================================
// INTERNAL SCHEMA CLIENT
// ============================================================================

class _DuckDBSchemaClient extends Client {
  _DuckDBSchemaClient() : super(KnexConfig(client: 'duckdb', connection: {}));

  @override
  String get driverName => 'duckdb';

  @override
  SchemaCompiler schemaCompiler(SchemaBuilder builder) =>
      SchemaCompiler(this, builder);

  @override
  QueryBuilder queryBuilder() => QueryBuilder(this);

  @override
  Future<dynamic> rawQuery(String sql, List<dynamic> bindings) =>
      throw UnimplementedError();

  @override
  Future<List<Map<String, dynamic>>> query(
    dynamic connection,
    String sql,
    List<dynamic> bindings,
  ) => throw UnimplementedError();

  @override
  Stream<Map<String, dynamic>> streamQuery(
    dynamic connection,
    String sql,
    List<dynamic> bindings,
  ) => throw UnimplementedError();

  @override
  Future<void> destroy() => Future.value();

  @override
  Future<Transaction> transaction([TransactionConfig? config]) =>
      throw UnimplementedError();

  @override
  void initializeDriver() {}

  @override
  void initializePool([poolConfig]) {}

  @override
  QueryCompiler queryCompiler(QueryBuilder builder) =>
      QueryCompiler(this, builder);

  @override
  dynamic formatter(dynamic builder) => Formatter(this, builder);

  @override
  SchemaBuilder schemaBuilder() => SchemaBuilder(this);

  @override
  Future acquireConnection() => throw UnimplementedError();

  @override
  Future<void> releaseConnection(connection) => Future.value();

  @override
  String wrapIdentifierImpl(String identifier) => '"$identifier"';

  @override
  String parameterPlaceholder(int index) => '\$$index';

  @override
  String formatValue(value) => value.toString();
}
