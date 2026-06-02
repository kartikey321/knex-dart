import 'package:knex_dart/knex_dart.dart';

import 'mysql_client.dart';

/// MySQL-specific Knex wrapper.
///
/// Also supports MariaDB via the named constructor — MariaDB is wire-compatible
/// with MySQL so no separate package is needed:
///
/// ```dart
/// final db = await KnexMySQL.mariadb(
///   host: 'localhost', database: 'myapp', user: 'user', password: 'password',
/// );
/// ```
class KnexMySQL {
  final MySQLClient _client;
  final String _dialectName;
  final KnexInterceptorPipeline _pipeline;

  KnexMySQL._(
    this._client, {
    String dialectName = 'mysql2',
    required KnexInterceptorPipeline pipeline,
  })  : _dialectName = dialectName,
        _pipeline = pipeline;

  /// Create a Knex instance connected to MySQL.
  static Future<KnexMySQL> connect({
    required String host,
    int port = 3306,
    required String user,
    String? password,
    required String database,
    bool useSSL = false,
    PoolConfig poolConfig = const PoolConfig(),
    List<QueryInterceptor> interceptors = const [],
  }) async {
    final client = await MySQLClient.connect(
      host: host,
      port: port,
      user: user,
      password: password,
      database: database,
      useSSL: useSSL,
      poolConfig: poolConfig,
    );
    return KnexMySQL._(
      client,
      pipeline: KnexInterceptorPipeline(
        dbSystem: 'mysql',
        database: database,
        serverAddress: host,
        serverPort: port,
        interceptors: interceptors,
      ),
    );
  }

  /// Create a Knex instance connected to MariaDB.
  ///
  /// MariaDB is wire-compatible with MySQL. Compared to MySQL, MariaDB adds:
  /// - `RETURNING` clause (10.5+)
  /// - `FULL OUTER JOIN` support
  /// - `INTERSECT` / `EXCEPT` (10.3+)
  static Future<KnexMySQL> mariadb({
    required String host,
    int port = 3306,
    required String user,
    String? password,
    required String database,
    bool useSSL = false,
    PoolConfig poolConfig = const PoolConfig(),
    List<QueryInterceptor> interceptors = const [],
  }) async {
    final client = await MySQLClient.connect(
      host: host,
      port: port,
      user: user,
      password: password,
      database: database,
      useSSL: useSSL,
      poolConfig: poolConfig,
    );
    return KnexMySQL._(
      client,
      dialectName: 'mariadb',
      pipeline: KnexInterceptorPipeline(
        dbSystem: 'mariadb',
        database: database,
        serverAddress: host,
        serverPort: port,
        interceptors: interceptors,
      ),
    );
  }

  /// Executes a SELECT-style query and returns rows.
  Future<List<Map<String, dynamic>>> select(QueryBuilder query) =>
      _pipeline.run(query, () => _client.select(query));

  /// Executes any compiled query and returns rows/result payload.
  Future<List<Map<String, dynamic>>> execute(QueryBuilder query) =>
      _pipeline.run(query, () => _client.execute(query));

  /// Executes an INSERT query.
  Future<List<Map<String, dynamic>>> insert(QueryBuilder query) =>
      _pipeline.run(query, () => _client.insert(query));

  /// Executes an UPDATE query.
  Future<List<Map<String, dynamic>>> update(QueryBuilder query) =>
      _pipeline.run(query, () => _client.update(query));

  /// Executes a DELETE query.
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

  /// Streams query results row by row.
  Stream<Map<String, dynamic>> streamQuery(QueryBuilder query) =>
      _pipeline.runStream(query, () => _client.streamQuery(query));

  /// Create a query builder scoped to the active dialect.
  QueryBuilder queryBuilder() => _MySQLSchemaClient(_dialectName).queryBuilder();

  /// Callable shorthand for `queryBuilder().table(name)`.
  QueryBuilder call([String? tableName]) {
    final builder = queryBuilder();
    return tableName != null ? builder.table(tableName) : builder;
  }

  /// Run a transaction.
  Future<T> trx<T>(Future<T> Function(KnexMySQLTransaction tx) callback) =>
      _client.trx((rawTrx) {
        final txId = _pipeline.nextUid();
        return callback(
          KnexMySQLTransaction._(rawTrx, _pipeline, _dialectName, txId),
        );
      });

  /// Execute schema DDL operations.
  Future<void> executeSchema(
    void Function(SchemaBuilder schema) callback,
  ) async {
    final mysqlMock = _MySQLSchemaClient(_dialectName);
    final builder = mysqlMock.schemaBuilder();
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

  /// Closes the underlying MySQL connection pool.
  Future<void> close() => _client.close();

  /// Alias for [close], matching the core `Knex` API.
  Future<void> destroy() => close();
}

// ============================================================================
// WRAPPER-LEVEL TRANSACTION FACADE
// ============================================================================

class KnexMySQLTransaction extends KnexTransaction {
  final MySQLTrxClient _trx;
  final KnexInterceptorPipeline _pipeline;
  final String _dialectName;

  @override
  final String txId;

  KnexMySQLTransaction._(this._trx, this._pipeline, this._dialectName, this.txId);

  @override
  QueryBuilder queryBuilder() => _MySQLSchemaClient(_dialectName).queryBuilder();

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
        () => _trx.rawSql(sql, bindings),
        txId: txId,
      );

  @override
  Future<T> trx<T>(Future<T> Function(KnexTransaction tx) callback) async {
    final sp = 'sp_${_pipeline.nextUid()}';
    final childTxId = '${txId}_$sp';
    await rawSql('SAVEPOINT $sp');
    try {
      final result = await callback(
        KnexMySQLTransaction._(_trx, _pipeline, _dialectName, childTxId),
      );
      await rawSql('RELEASE SAVEPOINT $sp');
      return result;
    } catch (e, st) {
      try {
        await rawSql('ROLLBACK TO SAVEPOINT $sp');
      } catch (_) {}
      Error.throwWithStackTrace(e, st);
    }
  }
}

// ============================================================================
// INTERNAL SCHEMA CLIENT
// ============================================================================

/// Internal MySQL-flavored schema client for SQL generation only.
///
/// Accepts a [dialectName] so MariaDB callers get correct capability checks.
class _MySQLSchemaClient extends Client {
  final String _dialectName;

  _MySQLSchemaClient([String dialectName = 'mysql2'])
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
  String wrapIdentifierImpl(String identifier) => '`$identifier`';

  @override
  String parameterPlaceholder(int index) => '?';

  @override
  String formatValue(value) => value.toString();
}
