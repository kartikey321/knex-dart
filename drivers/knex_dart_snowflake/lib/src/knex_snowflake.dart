import 'package:knex_dart/knex_dart.dart';

import 'snowflake_client.dart';

/// Snowflake Knex wrapper.
class KnexSnowflake {
  final SnowflakeClient _client;
  final KnexInterceptorPipeline _pipeline;

  KnexSnowflake({
    required String account,
    required String token,
    String? database,
    String? schema,
    String? warehouse,
    String? role,
    bool asyncExecution = false,
    List<QueryInterceptor> interceptors = const [],
  })  : _client = SnowflakeClient(
          account: account,
          token: token,
          database: database,
          schema: schema,
          warehouse: warehouse,
          role: role,
          asyncExecution: asyncExecution,
        ),
        _pipeline = KnexInterceptorPipeline(
          dbSystem: 'snowflake',
          database: database,
          serverAddress: '$account.snowflakecomputing.com',
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

  QueryBuilder queryBuilder() => _SnowflakeSchemaClient().queryBuilder();

  QueryBuilder call([String? tableName]) {
    final builder = queryBuilder();
    return tableName != null ? builder.table(tableName) : builder;
  }

  Future<List<Map<String, dynamic>>> getAsyncResult(String statementHandle) =>
      _client.getAsyncResult(statementHandle);

  Future<void> executeSchema(
    void Function(SchemaBuilder schema) callback,
  ) async {
    final mock = _SnowflakeSchemaClient();
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

class _SnowflakeSchemaClient extends Client {
  _SnowflakeSchemaClient()
      : super(KnexConfig(client: 'snowflake', connection: {}));

  @override
  String get driverName => 'snowflake';

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
