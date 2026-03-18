import 'package:knex_dart/knex_dart.dart';

import 'turso_client.dart';

/// Turso (libSQL) Knex wrapper.
///
/// Turso uses a SQLite-compatible SQL dialect over the libSQL HTTP API.
/// Identifiers are double-quoted; parameters use `?` positional placeholders.
///
/// Example:
/// ```dart
/// final db = KnexTurso(
///   url: 'https://my-db-org.turso.io',
///   authToken: 'eyJ...',
/// );
///
/// final users = await db.select(
///   db.queryBuilder().from('users').where('active', '=', 1),
/// );
///
/// await db.trx((trx) async {
///   await trx.insert(db.queryBuilder().table('users').insert({'name': 'Alice'}));
///   await trx.insert(db.queryBuilder().table('orders').insert({'user': 'Alice'}));
/// });
///
/// db.close();
/// ```
class KnexTurso {
  final TursoClient _client;

  KnexTurso({
    required String url,
    String? authToken,
  }) : _client = TursoClient(url: url, authToken: authToken);

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

  /// Create a query builder scoped to the Turso/SQLite dialect.
  ///
  /// Uses double-quote identifiers and `?` positional parameters.
  QueryBuilder queryBuilder() => _TursoSchemaClient().queryBuilder();

  /// Run a transaction.
  ///
  /// Sends `BEGIN` before the callback and `COMMIT` on success, or
  /// `ROLLBACK` on error. Nested calls inside the [TursoTrxClient] use
  /// SAVEPOINTs for safe nesting.
  Future<T> trx<T>(Future<T> Function(TursoTrxClient trx) callback) =>
      _client.trx(callback);

  /// Execute schema DDL operations.
  ///
  /// Takes a [SchemaBuilder] callback, generates SQLite-dialect DDL, and runs
  /// each statement against the database.
  Future<void> executeSchema(
    void Function(SchemaBuilder schema) callback,
  ) async {
    final mock = _TursoSchemaClient();
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
// Lightweight "stub" client used only for SQL generation.
// Does not connect to any database.
// ============================================================================

/// Internal Turso/SQLite-flavored schema client for SQL generation only.
class _TursoSchemaClient extends Client {
  _TursoSchemaClient()
    : super(KnexConfig(client: 'turso', connection: {}));

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

  // SQLite-compatible: double-quote identifiers, `?` parameters
  @override
  String wrapIdentifierImpl(String identifier) => '"$identifier"';

  @override
  String parameterPlaceholder(int index) => '?';

  @override
  String formatValue(value) => value.toString();
}
