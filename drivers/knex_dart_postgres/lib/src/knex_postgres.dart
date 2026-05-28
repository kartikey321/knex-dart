import 'package:knex_dart/knex_dart.dart';

import 'postgres_client.dart';

/// PostgreSQL-specific Knex wrapper.
///
/// Also supports CockroachDB and Amazon Redshift via named constructors —
/// both speak the PostgreSQL wire protocol so no separate package is needed:
///
/// ```dart
/// // CockroachDB (port 26257, insecure dev mode)
/// final db = await KnexPostgres.cockroachdb(
///   host: 'localhost', database: 'defaultdb', username: 'root', useSSL: false,
/// );
///
/// // Amazon Redshift (port 5439)
/// final db = await KnexPostgres.redshift(
///   host: 'my-cluster.us-east-1.redshift.amazonaws.com',
///   database: 'dev', username: 'awsuser', password: 'secret',
/// );
/// ```
class KnexPostgres {
  final PostgresClient _pgClient;
  final String _dialectName;

  KnexPostgres._(this._pgClient, {String dialectName = 'pg'})
    : _dialectName = dialectName;

  /// Create a Knex instance connected to PostgreSQL.
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

  /// Create a Knex instance connected to CockroachDB.
  ///
  /// CockroachDB is wire-compatible with PostgreSQL. Default port: 26257.
  /// TLS is disabled by default for local/dev clusters (`--insecure` mode).
  /// Set [useSSL] to `true` for production deployments.
  static Future<KnexPostgres> cockroachdb({
    required String host,
    int port = 26257,
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
    return KnexPostgres._(client); // 'pg' dialect — capabilities identical to postgres
  }

  /// Create a Knex instance connected to Amazon Redshift.
  ///
  /// Redshift is wire-compatible with PostgreSQL. Default port: 5439.
  ///
  /// Redshift dialect notes — avoid these features (not supported):
  /// - `.returning()` — Redshift has no RETURNING clause.
  /// - `.joinLateral()` — LATERAL joins are not supported.
  /// - JSONB operators (`@>`, `<@`, etc.) — use plain JSON functions instead.
  static Future<KnexPostgres> redshift({
    required String host,
    int port = 5439,
    required String database,
    required String username,
    String? password,
    bool useSSL = true,
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
    return KnexPostgres._(client, dialectName: 'redshift');
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

  /// Create a query builder scoped to the active dialect.
  QueryBuilder queryBuilder() => _PgSchemaClient(_dialectName).queryBuilder();

  /// Callable shorthand for `queryBuilder().table(name)`.
  QueryBuilder call([String? tableName]) {
    final builder = queryBuilder();
    return tableName != null ? builder.table(tableName) : builder;
  }

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
    final pgMock = _PgSchemaClient(_dialectName);
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

  /// Alias for [close], matching the core `Knex` API.
  Future<void> destroy() => close();
}

// ============================================================================
// INTERNAL SCHEMA CLIENT
// Lightweight "stub" client used only for SQL generation.
// Does not connect to any database.
// ============================================================================

/// Internal PG-flavored schema client for SQL generation only.
///
/// Accepts a [dialectName] so CockroachDB and Redshift callers get
/// dialect-aware capability checks without a separate package.
class _PgSchemaClient extends Client {
  final String _dialectName;

  _PgSchemaClient([String dialectName = 'pg'])
    : _dialectName = dialectName,
      super(KnexConfig(client: dialectName, connection: {}));

  @override
  String get driverName => _dialectName;

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
