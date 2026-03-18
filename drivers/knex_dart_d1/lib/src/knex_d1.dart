import 'package:knex_dart/knex_dart.dart';

import 'd1_client.dart';

/// Cloudflare D1 Knex wrapper.
///
/// D1 is Cloudflare's serverless SQLite database, accessed via the
/// Cloudflare REST API. Uses SQLite-compatible SQL (double-quote identifiers,
/// `?` positional parameters).
///
/// Example:
/// ```dart
/// final db = KnexD1(
///   accountId: 'your-cloudflare-account-id',
///   databaseId: 'your-d1-database-id',
///   apiToken: 'your-cloudflare-api-token',
/// );
///
/// final users = await db.select(
///   db.queryBuilder().from('users').where('active', '=', 1),
/// );
///
/// // Atomic batch (true D1 transaction over REST API)
/// await db.batch((b) {
///   b.add(db.queryBuilder().table('users').insert({'name': 'Alice'}));
///   b.add(db.queryBuilder().table('audit').insert({'action': 'create'}));
/// });
///
/// db.close();
/// ```
class KnexD1 {
  final D1Client _client;

  KnexD1({
    required String accountId,
    required String databaseId,
    required String apiToken,
  }) : _client = D1Client(
         accountId: accountId,
         databaseId: databaseId,
         apiToken: apiToken,
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

  /// Create a query builder scoped to the D1/SQLite dialect.
  QueryBuilder queryBuilder() => _D1SchemaClient().queryBuilder();

  /// Execute multiple statements as an atomic D1 batch.
  ///
  /// All statements in the callback are sent in a single REST API request
  /// and executed atomically (all-or-nothing).
  Future<List<List<Map<String, dynamic>>>> batch(
    void Function(D1BatchBuilder batch) callback,
  ) => _client.batch(callback);

  /// Simulated transaction via D1 batch API.
  ///
  /// Buffers all operations and sends them atomically after the callback
  /// completes. Individual return values within the callback are empty.
  Future<T> trx<T>(Future<T> Function(D1TrxClient trx) callback) =>
      _client.trx(callback);

  /// Execute schema DDL operations.
  Future<void> executeSchema(
    void Function(SchemaBuilder schema) callback,
  ) async {
    final mock = _D1SchemaClient();
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

/// Internal D1/SQLite-flavored schema client for SQL generation only.
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
