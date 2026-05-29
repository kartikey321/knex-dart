import 'package:knex_dart/knex_dart.dart';

import 'turso_client.dart';

/// Turso (libSQL) Knex wrapper.
class KnexTurso {
  final TursoClient _client;
  final KnexInterceptorPipeline _pipeline;

  KnexTurso({
    required String url,
    String? authToken,
    List<QueryInterceptor> interceptors = const [],
  })  : _client = TursoClient(url: url, authToken: authToken),
        _pipeline = KnexInterceptorPipeline(
          dbSystem: 'sqlite',
          serverAddress: url,
          interceptors: interceptors,
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

  Raw raw(String sql, [List<dynamic>? bindings]) =>
      _TursoSchemaClient().raw(sql, bindings);

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
  Future<List<Map<String, dynamic>>> executeRaw(
    String sql, [
    List<dynamic>? bindings,
  ]) =>
      rawSql(sql, bindings);

  QueryBuilder queryBuilder() => _TursoSchemaClient().queryBuilder();

  QueryBuilder call([String? tableName]) {
    final builder = queryBuilder();
    return tableName != null ? builder.table(tableName) : builder;
  }

  Future<T> trx<T>(Future<T> Function(KnexTursoTransaction tx) callback) =>
      _client.trx((rawTrx) {
        final txId = _pipeline.nextUid();
        return callback(KnexTursoTransaction._(rawTrx, _pipeline, txId));
      });

  Future<void> executeSchema(
    void Function(SchemaBuilder schema) callback,
  ) async {
    final mock = _TursoSchemaClient();
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

  void close() => _client.close();

  void destroy() => close();
}

// ============================================================================
// WRAPPER-LEVEL TRANSACTION FACADE
// ============================================================================

class KnexTursoTransaction implements KnexTransaction {
  final TursoTrxClient _trx;
  final KnexInterceptorPipeline _pipeline;

  @override
  final String txId;

  KnexTursoTransaction._(this._trx, this._pipeline, this.txId);

  @override
  QueryBuilder queryBuilder() => _TursoSchemaClient().queryBuilder();

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

  @override
  Future<T> trx<T>(Future<T> Function(KnexTransaction tx) callback) async {
    final sp = 'sp_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    final childTxId = '${txId}_$sp';
    await rawSql('SAVEPOINT $sp');
    try {
      final result = await callback(
        KnexTursoTransaction._(_trx, _pipeline, childTxId),
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

class _TursoSchemaClient extends Client {
  _TursoSchemaClient() : super(KnexConfig(client: 'turso', connection: {}));

  @override
  String get driverName => 'turso';

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
  String parameterPlaceholder(int index) => '?';

  @override
  String formatValue(value) => value.toString();
}
