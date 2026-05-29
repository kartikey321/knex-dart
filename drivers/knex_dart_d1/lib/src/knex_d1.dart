import 'package:knex_dart/knex_dart.dart';

import 'd1_client.dart';

/// Cloudflare D1 Knex wrapper.
class KnexD1 {
  final D1Client _client;
  final KnexInterceptorPipeline _pipeline;

  KnexD1({
    required String accountId,
    required String databaseId,
    required String apiToken,
    List<QueryInterceptor> interceptors = const [],
  })  : _client = D1Client(
          accountId: accountId,
          databaseId: databaseId,
          apiToken: apiToken,
        ),
        _pipeline = KnexInterceptorPipeline(
          dbSystem: 'sqlite',
          database: databaseId,
          serverAddress: 'api.cloudflare.com',
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

  QueryBuilder queryBuilder() => _D1SchemaClient().queryBuilder();

  QueryBuilder call([String? tableName]) {
    final builder = queryBuilder();
    return tableName != null ? builder.table(tableName) : builder;
  }

  Future<List<List<Map<String, dynamic>>>> batch(
    void Function(D1BatchBuilder batch) callback,
  ) =>
      _pipeline.runBatch(() => _client.batch(callback));

  /// Simulated transaction via D1 batch API.
  ///
  /// All statements collected inside [callback] are sent as a single atomic
  /// HTTP batch.  The entire batch is surfaced to interceptors as one `BATCH`
  /// span — individual buffered statements are not individually observable
  /// because D1's REST API executes them server-side as a unit.
  Future<T> trx<T>(Future<T> Function(D1TrxClient trx) callback) =>
      _pipeline.runBatch(() => _client.trx(callback));

  Future<void> executeSchema(
    void Function(SchemaBuilder schema) callback,
  ) async {
    final mock = _D1SchemaClient();
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
// INTERNAL SCHEMA CLIENT
// ============================================================================

class _D1SchemaClient extends Client {
  _D1SchemaClient() : super(KnexConfig(client: 'd1', connection: {}));

  @override
  String get driverName => 'd1';

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
