import 'package:knex_dart/knex_dart.dart';

import 'snowflake_client.dart';

/// Snowflake Knex wrapper.
///
/// Snowflake is a cloud data warehouse. Queries are executed via the
/// Snowflake SQL API v2. Uses double-quoted identifiers and `?` positional
/// parameters.
///
/// **Authentication**: Provide an OAuth token or a Snowflake JWT token.
/// For service accounts, use a key-pair JWT; for interactive apps, use OAuth.
///
/// Example:
/// ```dart
/// final db = KnexSnowflake(
///   account: 'myorg-myaccount',
///   token: 'oauth_token_or_jwt',
///   database: 'MY_DATABASE',
///   schema: 'PUBLIC',
///   warehouse: 'COMPUTE_WH',
/// );
///
/// final rows = await db.select(
///   db.queryBuilder().from('SALES').where('region', '=', 'EMEA'),
/// );
///
/// db.close();
/// ```
class KnexSnowflake {
  final SnowflakeClient _client;

  KnexSnowflake({
    required String account,
    required String token,
    String? database,
    String? schema,
    String? warehouse,
    String? role,
    bool asyncExecution = false,
  }) : _client = SnowflakeClient(
         account: account,
         token: token,
         database: database,
         schema: schema,
         warehouse: warehouse,
         role: role,
         asyncExecution: asyncExecution,
       );

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

  /// Execute a raw SQL string directly.
  Future<List<Map<String, dynamic>>> raw(
    String sql, [
    List<dynamic>? bindings,
  ]) => _client.raw(sql, bindings);

  /// Create a query builder scoped to the Snowflake dialect.
  ///
  /// Uses double-quote identifiers and `?` positional parameters.
  QueryBuilder queryBuilder() => _SnowflakeSchemaClient().queryBuilder();

  /// Poll for an async query result.
  ///
  /// Use when [asyncExecution] is `true` and a query returned a statement
  /// handle instead of data.
  Future<List<Map<String, dynamic>>> getAsyncResult(String statementHandle) =>
      _client.getAsyncResult(statementHandle);

  /// Execute schema DDL operations.
  Future<void> executeSchema(
    void Function(SchemaBuilder schema) callback,
  ) async {
    final mock = _SnowflakeSchemaClient();
    final builder = mock.schemaBuilder();
    callback(builder);
    final statements = builder.toSQL();
    for (final stmt in statements) {
      await _client.raw(
        stmt['sql'] as String,
        stmt['bindings'] as List<dynamic>?,
      );
    }
  }

  /// Close the underlying HTTP client.
  void close() => _client.close();
}

// ============================================================================
// INTERNAL SCHEMA CLIENT
// ============================================================================

/// Internal Snowflake-flavored schema client for SQL generation only.
///
/// Snowflake uses double-quote identifiers and `?` positional parameters.
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
