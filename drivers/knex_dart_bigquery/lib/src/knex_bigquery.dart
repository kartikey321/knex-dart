import 'package:knex_dart/knex_dart.dart';

import 'bigquery_client.dart';

/// Google BigQuery Knex wrapper.
///
/// BigQuery is Google's serverless data warehouse. Uses GoogleSQL:
/// - Backtick-quoted identifiers (`` `project.dataset.table` ``)
/// - `@param_name` named parameters (this wrapper maps `?` → `@p1`, `@p2`)
///
/// Example:
/// ```dart
/// final db = KnexBigQuery(
///   projectId: 'my-gcp-project',
///   token: 'ya29.oauth_token',
///   defaultDataset: 'analytics',
///   location: 'US',
/// );
///
/// final rows = await db.select(
///   db.queryBuilder().from('events').where('date', '=', '2024-01-01'),
/// );
///
/// db.close();
/// ```
class KnexBigQuery {
  final BigQueryClient _client;

  KnexBigQuery({
    required String projectId,
    required String token,
    String? defaultDataset,
    String? location,
  }) : _client = BigQueryClient(
         projectId: projectId,
         token: token,
         defaultDataset: defaultDataset,
         location: location,
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

  /// Create a query builder scoped to the BigQuery dialect.
  ///
  /// Uses backtick-quoted identifiers and `?` positional parameters
  /// (automatically converted to `@p1`, `@p2` in the HTTP transport).
  QueryBuilder queryBuilder() => _BigQuerySchemaClient().queryBuilder();

  /// Callable shorthand for `queryBuilder().table(name)`.
  QueryBuilder call([String? tableName]) {
    final builder = queryBuilder();
    return tableName != null ? builder.table(tableName) : builder;
  }

  /// Execute schema DDL operations.
  ///
  /// Note: BigQuery DDL (CREATE TABLE, etc.) auto-commits — there are no
  /// schema transactions.
  Future<void> executeSchema(
    void Function(SchemaBuilder schema) callback,
  ) async {
    final mock = _BigQuerySchemaClient();
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

  /// Alias for [close], matching the core `Knex` API.
  void destroy() => close();
}

// ============================================================================
// INTERNAL SCHEMA CLIENT
// ============================================================================

/// Internal BigQuery-flavored schema client for SQL generation only.
///
/// BigQuery uses backtick-quoted identifiers and `?` positional parameters.
class _BigQuerySchemaClient extends Client {
  _BigQuerySchemaClient()
    : super(KnexConfig(client: 'bigquery', connection: {}));

  @override
  String get driverName => 'bigquery';

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

  // BigQuery uses backtick-quoted identifiers
  @override
  String wrapIdentifierImpl(String identifier) => '`$identifier`';

  @override
  String parameterPlaceholder(int index) => '?';

  @override
  String formatValue(value) => value.toString();
}
