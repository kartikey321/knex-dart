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
  final KnexInterceptorPipeline _pipeline;


  KnexPostgres._(
    this._pgClient, {
    String dialectName = 'pg',
    required KnexInterceptorPipeline pipeline,
  })  : _dialectName = dialectName,
        _pipeline = pipeline;

  /// Create a Knex instance connected to PostgreSQL.
  static Future<KnexPostgres> connect({
    required String host,
    int port = 5432,
    required String database,
    required String username,
    String? password,
    bool useSSL = false,
    PoolConfig poolConfig = const PoolConfig(),
    List<QueryInterceptor> interceptors = const [],
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
    return KnexPostgres._(
      client,
      pipeline: KnexInterceptorPipeline(
        dbSystem: 'postgresql',
        database: database,
        serverAddress: host,
        serverPort: port,
        interceptors: interceptors,
      ),
    );
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
    List<QueryInterceptor> interceptors = const [],
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
    return KnexPostgres._(
      client,
      dialectName: 'cockroachdb',
      pipeline: KnexInterceptorPipeline(
        dbSystem: 'cockroachdb',
        database: database,
        serverAddress: host,
        serverPort: port,
        interceptors: interceptors,
      ),
    );
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
    List<QueryInterceptor> interceptors = const [],
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
    return KnexPostgres._(
      client,
      dialectName: 'redshift',
      pipeline: KnexInterceptorPipeline(
        dbSystem: 'redshift',
        database: database,
        serverAddress: host,
        serverPort: port,
        interceptors: interceptors,
      ),
    );
  }

  /// Executes a SELECT-style query and returns rows.
  Future<List<Map<String, dynamic>>> select(QueryBuilder query) =>
      _pipeline.run(query, () => _pgClient.select(query));

  /// Executes any compiled query and returns rows/result payload.
  Future<List<Map<String, dynamic>>> execute(QueryBuilder query) =>
      _pipeline.run(query, () => _pgClient.execute(query));

  /// Executes an INSERT query.
  Future<List<Map<String, dynamic>>> insert(QueryBuilder query) =>
      _pipeline.run(query, () => _pgClient.insert(query));

  /// Executes an UPDATE query.
  Future<List<Map<String, dynamic>>> update(QueryBuilder query) =>
      _pipeline.run(query, () => _pgClient.update(query));

  /// Executes a DELETE query.
  Future<List<Map<String, dynamic>>> delete(QueryBuilder query) =>
      _pipeline.run(query, () => _pgClient.delete(query));

  /// Execute a raw SQL string directly.
  Future<List<Map<String, dynamic>>> rawSql(
    String sql, [
    List<dynamic>? bindings,
  ]) =>
      _pipeline.runRaw(
        sql,
        bindings ?? const [],
        () => _pgClient.rawSql(sql, bindings),
      );

  /// Create a query builder scoped to the active dialect.
  QueryBuilder queryBuilder() => _PgSchemaClient(_dialectName).queryBuilder();

  /// Callable shorthand for `queryBuilder().table(name)`.
  QueryBuilder call([String? tableName]) {
    final builder = queryBuilder();
    return tableName != null ? builder.table(tableName) : builder;
  }

  /// Run a transaction.
  ///
  /// The callback receives a [KnexPostgresTransaction] which exposes the same
  /// query API as [KnexPostgres] and routes every query through the interceptor
  /// pipeline with [QueryExecutionContext.txId] set.
  Future<T> trx<T>(Future<T> Function(KnexPostgresTransaction tx) callback) =>
      _pgClient.trx((rawTrx) {
        final txId = _pipeline.nextUid();
        return callback(
          KnexPostgresTransaction._(rawTrx, _pipeline, _dialectName, txId),
        );
      });

  /// Execute schema DDL operations.
  Future<void> executeSchema(
    void Function(SchemaBuilder schema) callback,
  ) async {
    final pgMock = _PgSchemaClient(_dialectName);
    final builder = pgMock.schemaBuilder();
    callback(builder);
    final statements = builder.toSQL();
    for (final stmt in statements) {
      await _pipeline.runRaw(
        stmt['sql'] as String,
        (stmt['bindings'] as List<dynamic>?) ?? const [],
        () => _pgClient.rawSql(
          stmt['sql'] as String,
          stmt['bindings'] as List<dynamic>?,
        ),
      );
    }
  }

  Future<void> close() => _pgClient.close();

  /// Alias for [close], matching the core `Knex` API.
  Future<void> destroy() => close();
}

// ============================================================================
// WRAPPER-LEVEL TRANSACTION FACADE
// ============================================================================

/// Transaction facade returned by [KnexPostgres.trx].
///
/// Implements [KnexTransaction] so queries run inside a transaction are routed
/// through the same [KnexInterceptorPipeline] as top-level queries, with
/// [QueryExecutionContext.txId] set for span correlation.
///
/// Nested calls to [trx] create a savepoint, not a new physical transaction.
class KnexPostgresTransaction extends KnexTransaction {
  final PostgresTrxClient _trx;
  final KnexInterceptorPipeline _pipeline;
  final String _dialectName;

  @override
  final String txId;

  KnexPostgresTransaction._(
    this._trx,
    this._pipeline,
    this._dialectName,
    this.txId,
  );

  @override
  QueryBuilder queryBuilder() => _PgSchemaClient(_dialectName).queryBuilder();

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
  Future<List<Map<String, dynamic>>> rawSql(
    String sql, [
    List<dynamic>? bindings,
  ]) =>
      _pipeline.runRaw(
        sql,
        bindings ?? const [],
        () => _trx.rawSql(sql, bindings),
        txId: txId,
      );

  /// Creates a savepoint inside this transaction.
  ///
  /// The inner [KnexPostgresTransaction] shares the same session but gets a
  /// child [txId] so spans can be correlated.
  @override
  Future<T> trx<T>(Future<T> Function(KnexTransaction tx) callback) async {
    final sp = 'sp_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    final childTxId = '${txId}_$sp';
    await rawSql('SAVEPOINT $sp');
    try {
      final result = await callback(
        KnexPostgresTransaction._(_trx, _pipeline, _dialectName, childTxId),
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
