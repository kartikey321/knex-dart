import 'package:knex_dart/knex_dart.dart';

import 'postgres_client.dart';

/// PostgreSQL-specific Knex wrapper.
class KnexPostgres {
  final PostgresClient _pgClient;

  KnexPostgres._(this._pgClient);

  /// Create a Knex instance connected to PostgreSQL.
  ///
  /// Example:
  /// ```dart
  /// final db = await KnexPostgres.connect(
  ///   host: 'localhost',
  ///   database: 'myapp',
  ///   username: 'user',
  ///   password: 'password',
  /// );
  ///
  /// final users = await db.select(
  ///   db.queryBuilder().from('users').where('active', '=', true)
  /// );
  ///
  /// await db.close();
  /// ```
  static Future<KnexPostgres> connect({
    required String host,
    int port = 5432,
    required String database,
    required String username,
    String? password,
    bool useSSL = false,
    PoolConfig poolConfig = const PoolConfig(),
  }) async {
    final client = await PostgresClient.connect(
      host: host,
      port: port,
      database: database,
      username: username,
      password: password,
      useSSL: useSSL,
      poolConfig: poolConfig,
    );
    return KnexPostgres._(client);
  }

  /// Executes a SELECT-style query and returns rows.
  Future<List<Map<String, dynamic>>> select(QueryBuilder query) =>
      _pgClient.select(query);

  /// Executes any compiled query and returns rows/result payload.
  Future<List<Map<String, dynamic>>> execute(QueryBuilder query) =>
      _pgClient.execute(query);

  /// Executes an INSERT query.
  Future<List<Map<String, dynamic>>> insert(QueryBuilder query) =>
      _pgClient.insert(query);

  /// Executes an UPDATE query.
  Future<List<Map<String, dynamic>>> update(QueryBuilder query) =>
      _pgClient.update(query);

  /// Executes a DELETE query.
  Future<List<Map<String, dynamic>>> delete(QueryBuilder query) =>
      _pgClient.delete(query);

  /// Execute a raw SQL string directly.
  Future<List<Map<String, dynamic>>> rawSql(
    String sql, [
    List<dynamic>? bindings,
  ]) => _pgClient.rawSql(sql, bindings);

  /// Create a query builder.
  QueryBuilder queryBuilder() => _PgSchemaClient().queryBuilder();

  /// Run a transaction. See [PostgresClient.trx].
  Future<T> trx<T>(Future<T> Function(PostgresTrxClient trx) callback) =>
      _pgClient.trx(callback);

  /// Execute schema DDL operations.
  ///
  /// Takes a [SchemaBuilder] callback, generates dialect-aware SQL, and runs
  /// each statement against the database.
  Future<void> executeSchema(
    void Function(SchemaBuilder schema) callback,
  ) async {
    final pgMock = _PgSchemaClient();
    final builder = pgMock.schemaBuilder();
    callback(builder);
    final statements = builder.toSQL();
    for (final stmt in statements) {
      await _pgClient.rawSql(
        stmt['sql'] as String,
        stmt['bindings'] as List<dynamic>?,
      );
    }
  }

  Future<void> close() => _pgClient.close();
}

// ============================================================================
// INTERNAL SCHEMA CLIENT
// Lightweight "stub" client used only for SQL generation.
// Does not connect to any database.
// ============================================================================

/// Internal PG-flavored schema client for SQL generation only.
class _PgSchemaClient extends Client {
  _PgSchemaClient() : super(KnexConfig(client: 'pg', connection: {}));

  @override
  String get driverName => 'pg';

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
