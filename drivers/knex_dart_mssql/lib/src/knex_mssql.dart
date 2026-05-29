import 'package:knex_dart/knex_dart.dart';

import 'mssql_client.dart';

export 'mssql_client.dart' show MssqlTrxClient;

/// SQL Server Knex wrapper.
class KnexMssql {
  final MssqlClient _client;
  final KnexInterceptorPipeline _pipeline;

  KnexMssql._(this._client, {required KnexInterceptorPipeline pipeline})
      : _pipeline = pipeline;

  static Future<KnexMssql> connect({
    required String host,
    String port = '1433',
    required String database,
    required String username,
    required String password,
    int timeoutSeconds = 15,
    List<QueryInterceptor> interceptors = const [],
  }) async {
    final client = await MssqlClient.connect(
      host: host,
      port: port,
      database: database,
      username: username,
      password: password,
      timeoutSeconds: timeoutSeconds,
    );
    return KnexMssql._(
      client,
      pipeline: KnexInterceptorPipeline(
        dbSystem: 'mssql',
        database: database,
        serverAddress: host,
        serverPort: int.tryParse(port),
        interceptors: interceptors,
      ),
    );
  }

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

  /// Create a raw SQL fragment for use inside QueryBuilder clauses.
  Raw raw(String sql, [List<dynamic>? bindings]) =>
      _MssqlSchemaClient().raw(sql, bindings);

  /// Execute a raw SQL statement directly.
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

  QueryBuilder queryBuilder() => _MssqlSchemaClient().queryBuilder();

  QueryBuilder call([String? tableName]) {
    final builder = queryBuilder();
    return tableName != null ? builder.table(tableName) : builder;
  }

  Future<T> trx<T>(Future<T> Function(KnexMssqlTransaction tx) callback) =>
      _client.trx((rawTrx) {
        final txId = _pipeline.nextUid();
        return callback(KnexMssqlTransaction._(rawTrx, _pipeline, txId));
      });

  Future<void> executeSchema(
    void Function(SchemaBuilder schema) callback,
  ) async {
    final mock = _MssqlSchemaClient();
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

class KnexMssqlTransaction implements KnexTransaction {
  final MssqlTrxClient _trx;
  final KnexInterceptorPipeline _pipeline;

  @override
  final String txId;

  KnexMssqlTransaction._(this._trx, this._pipeline, this.txId);

  @override
  QueryBuilder queryBuilder() => _MssqlSchemaClient().queryBuilder();

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

  // SQL Server savepoints: no explicit RELEASE, rolled back with ROLLBACK TRANSACTION <name>
  @override
  Future<T> trx<T>(Future<T> Function(KnexTransaction tx) callback) async {
    final sp = 'sp${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    final childTxId = '${txId}_$sp';
    await rawSql('SAVE TRANSACTION $sp');
    try {
      final result = await callback(
        KnexMssqlTransaction._(_trx, _pipeline, childTxId),
      );
      return result;
    } catch (e) {
      await rawSql('ROLLBACK TRANSACTION $sp');
      rethrow;
    }
  }
}

// ============================================================================
// INTERNAL SCHEMA CLIENT
// ============================================================================

class _MssqlSchemaClient extends Client {
  _MssqlSchemaClient() : super(KnexConfig(client: 'mssql', connection: {}));

  @override
  String get driverName => 'mssql';

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
  String wrapIdentifierImpl(String identifier) =>
      '[${identifier.replaceAll(']', ']]')}]';

  @override
  String parameterPlaceholder(int index) => '?';

  @override
  String formatValue(value) => value.toString();
}
