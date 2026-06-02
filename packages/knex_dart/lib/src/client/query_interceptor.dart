import 'dart:math';

import '../query/query_builder.dart';
import '../query/sql_string.dart';
import '../util/enums.dart';

/// Metadata about a single query execution, passed through the interceptor
/// pipeline. Contains everything needed to produce OTel spans, metrics, or
/// log entries without any dependency on a specific observability library.
class QueryExecutionContext {
  /// Canonical database system identifier (e.g. `'postgresql'`, `'sqlite'`,
  /// `'mysql'`). Matches the OTel `db.system.name` semantic convention.
  final String dbSystem;

  /// Database name (OTel `db.namespace`). Null when not known or not
  /// applicable (e.g. in-memory SQLite, serverless HTTP drivers).
  final String? database;

  /// Hostname or IP of the database server (OTel `server.address`).
  final String? serverAddress;

  /// Port the driver is connected to (OTel `server.port`).
  final int? serverPort;

  /// Compiled, parameterized SQL text (OTel `db.query.text`).
  final String sql;

  /// Bound parameters for the query. Values are NOT included in spans by
  /// default — pass to a `requestHook` only when explicitly opted-in.
  final List<Object?> parameters;

  /// Primary SQL verb: `SELECT`, `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`,
  /// etc. Derived via [queryMethodToSqlOperation] or [sqlOperationFromRaw].
  /// Corresponds to OTel `db.operation.name`.
  final String operationName;

  /// Primary table or collection targeted by the query (OTel
  /// `db.collection.name`). Null for raw queries or multi-table operations.
  final String? collectionName;

  /// Low-cardinality query summary suitable as a span name (OTel
  /// `db.query.summary`). Typically `"SELECT users"` or `"INSERT orders"`.
  final String querySummary;

  /// Transaction identifier when the query runs inside a transaction.
  final String? txId;

  const QueryExecutionContext({
    required this.dbSystem,
    required this.sql,
    required this.parameters,
    required this.operationName,
    required this.querySummary,
    this.database,
    this.serverAddress,
    this.serverPort,
    this.collectionName,
    this.txId,
  });

  /// Returns a copy with [txId] set.
  QueryExecutionContext withTxId(String txId) => QueryExecutionContext(
    dbSystem: dbSystem,
    sql: sql,
    parameters: parameters,
    operationName: operationName,
    querySummary: querySummary,
    database: database,
    serverAddress: serverAddress,
    serverPort: serverPort,
    collectionName: collectionName,
    txId: txId,
  );
}

/// Intercepts query execution.
///
/// Implement this interface to add tracing, metrics, logging, or any other
/// cross-cutting concern to knex_dart driver wrappers.
///
/// Both [intercept] (for futures) and [interceptStream] (for streaming queries)
/// have the same pipeline contract. Implement only what you need — the default
/// [interceptStream] is a transparent passthrough.
///
/// ```dart
/// class TimingInterceptor extends QueryInterceptor {
///   @override
///   Future<T> intercept<T>(QueryExecutionContext ctx, Future<T> Function() next) async {
///     final sw = Stopwatch()..start();
///     try { return await next(); }
///     finally { print('${ctx.operationName} ${sw.elapsedMilliseconds}ms'); }
///   }
/// }
/// ```
abstract class QueryInterceptor {
  /// Intercepts a future-based query execution.
  Future<T> intercept<T>(QueryExecutionContext ctx, Future<T> Function() next);

  /// Intercepts a streaming query execution.
  ///
  /// The default implementation is a transparent passthrough so implementors
  /// only override this when they need stream-aware behaviour (e.g. ending a
  /// span when the stream closes or errors).
  ///
  /// Note: use `abstract class` (not `implements`) when extending so this
  /// default is inherited automatically.
  Stream<T> interceptStream<T>(
    QueryExecutionContext ctx,
    Stream<T> Function() next,
  ) => next();
}

/// Holds connection-level metadata and the ordered list of [QueryInterceptor]s
/// for a driver wrapper. Every query execution is routed through this pipeline.
///
/// When [interceptors] is empty the pipeline is a transparent no-op — all
/// methods delegate directly to [execute] with no overhead beyond a
/// list-length check.
class KnexInterceptorPipeline {
  /// OTel `db.system.name` value for this driver.
  final String dbSystem;

  /// Database name (`db.namespace`), null when unknown.
  final String? database;

  /// Server hostname (`server.address`), null for embedded/serverless drivers.
  final String? serverAddress;

  /// Server port (`server.port`), null for embedded/serverless drivers.
  final int? serverPort;

  /// Ordered interceptor list. Interceptors run from index 0 outward.
  final List<QueryInterceptor> interceptors;

  /// Unique identifier for this pipeline instance.
  ///
  /// Generated randomly at construction time so UIDs produced by [nextUid]
  /// are globally unique across multiple deployed nodes. You can supply a
  /// fixed value for deterministic behaviour in tests.
  final String instanceId;

  int _uidCounter = 0;

  /// Returns a UID that is unique within this pipeline and across nodes.
  ///
  /// Format: `<instanceId>_<monotonic-counter>` — e.g. `3a9f_1`, `3a9f_2`.
  String nextUid() => '${instanceId}_${++_uidCounter}';

  KnexInterceptorPipeline({
    required this.dbSystem,
    this.database,
    this.serverAddress,
    this.serverPort,
    this.interceptors = const [],
    String? instanceId,
  }) : instanceId = instanceId ?? _generateId();

  // 32-bit cryptographic random — birthday collision at ~77 000 nodes (50%).
  static String _generateId() =>
      Random.secure().nextInt(0xFFFFFFFF).toRadixString(16).padLeft(8, '0');

  bool get _active => interceptors.isNotEmpty;

  // ── Builder query ──────────────────────────────────────────────────────────

  /// Runs [execute] through the interceptor pipeline for a [QueryBuilder]-based
  /// query. Skips the pipeline entirely when no interceptors are registered.
  Future<T> run<T>(
    QueryBuilder query,
    Future<T> Function() execute, {
    String? txId,
  }) {
    if (!_active) return execute();
    final compiled = query.toSQL();
    return runCompiled(query, compiled, (_) => execute(), txId: txId);
  }

  /// Runs [execute] through the interceptor pipeline using an already compiled
  /// query. Driver wrappers can use this to avoid calling `toSQL()` twice when
  /// interceptors need SQL metadata before execution.
  Future<T> runCompiled<T>(
    QueryBuilder query,
    SqlString compiled,
    Future<T> Function(SqlString compiled) execute, {
    String? txId,
  }) {
    if (!_active) return execute(compiled);
    final op = queryMethodToSqlOperation(query.method);
    final table = query.tableName;
    final ctx = QueryExecutionContext(
      dbSystem: dbSystem,
      database: database,
      serverAddress: serverAddress,
      serverPort: serverPort,
      sql: compiled.sql,
      parameters: compiled.bindings,
      operationName: op,
      collectionName: table,
      querySummary: table != null ? '$op $table' : op,
      txId: txId,
    );
    return _chain(ctx, 0, () => execute(compiled));
  }

  // ── Raw SQL ────────────────────────────────────────────────────────────────

  /// Runs [execute] through the interceptor pipeline for a raw SQL call.
  /// Skips the pipeline entirely when no interceptors are registered.
  Future<T> runRaw<T>(
    String sql,
    List<Object?> parameters,
    Future<T> Function() execute, {
    String? txId,
  }) {
    if (!_active) return execute();
    final op = sqlOperationFromRaw(sql);
    final ctx = QueryExecutionContext(
      dbSystem: dbSystem,
      database: database,
      serverAddress: serverAddress,
      serverPort: serverPort,
      sql: sql,
      parameters: parameters,
      operationName: op,
      collectionName: null,
      querySummary: op,
      txId: txId,
    );
    return _chain(ctx, 0, execute);
  }

  // ── Streaming ──────────────────────────────────────────────────────────────

  /// Runs [execute] through the interceptor pipeline for a streaming query.
  ///
  /// Interceptors that implement [QueryInterceptor.interceptStream] can track
  /// span lifetime tied to stream completion, error, or cancellation. The
  /// default passthrough means zero overhead for interceptors that don't
  /// override [interceptStream].
  Stream<T> runStream<T>(
    QueryBuilder query,
    Stream<T> Function() execute, {
    String? txId,
  }) {
    if (!_active) return execute();
    final compiled = query.toSQL();
    final op = queryMethodToSqlOperation(query.method);
    final table = query.tableName;
    final ctx = QueryExecutionContext(
      dbSystem: dbSystem,
      database: database,
      serverAddress: serverAddress,
      serverPort: serverPort,
      sql: compiled.sql,
      parameters: compiled.bindings,
      operationName: op,
      collectionName: table,
      querySummary: table != null ? '$op $table' : op,
      txId: txId,
    );
    return _chainStream(ctx, 0, execute);
  }

  // ── Explicit operation ─────────────────────────────────────────────────────

  /// Runs [execute] through the pipeline with fully explicit OTel attributes.
  ///
  /// Use this for operations that are not standard SQL verbs and would
  /// otherwise fall through to the `'DB'` catch-all in [sqlOperationFromRaw].
  /// For example, Snowflake async result polling:
  ///
  /// ```dart
  /// _pipeline.runOperation(
  ///   operationName: 'GET_ASYNC_RESULT',
  ///   querySummary: 'GET_ASYNC_RESULT',
  ///   queryText: '<snowflake async result>',
  ///   execute: () => _client.getAsyncResult(handle),
  /// );
  /// ```
  Future<T> runOperation<T>({
    required String operationName,
    required String querySummary,
    String queryText = '',
    required Future<T> Function() execute,
    String? txId,
  }) {
    if (!_active) return execute();
    final ctx = QueryExecutionContext(
      dbSystem: dbSystem,
      database: database,
      serverAddress: serverAddress,
      serverPort: serverPort,
      sql: queryText,
      parameters: const [],
      operationName: operationName,
      collectionName: null,
      querySummary: querySummary,
      txId: txId,
    );
    return _chain(ctx, 0, execute);
  }

  // ── Batch ──────────────────────────────────────────────────────────────────

  /// Runs a batch operation through the interceptor pipeline as a single span.
  ///
  /// Used by D1 and similar batch-mode drivers where statements are buffered
  /// and sent atomically. The pipeline sees one `BATCH` operation context.
  Future<T> runBatch<T>(Future<T> Function() execute) {
    if (!_active) return execute();
    final ctx = QueryExecutionContext(
      dbSystem: dbSystem,
      database: database,
      serverAddress: serverAddress,
      serverPort: serverPort,
      sql: '<batch>',
      parameters: const [],
      operationName: 'BATCH',
      querySummary: 'BATCH',
    );
    return _chain(ctx, 0, execute);
  }

  // ── Internal chaining ──────────────────────────────────────────────────────

  Future<T> _chain<T>(
    QueryExecutionContext ctx,
    int index,
    Future<T> Function() execute,
  ) {
    if (index >= interceptors.length) return execute();
    return interceptors[index].intercept(
      ctx,
      () => _chain(ctx, index + 1, execute),
    );
  }

  Stream<T> _chainStream<T>(
    QueryExecutionContext ctx,
    int index,
    Stream<T> Function() execute,
  ) {
    if (index >= interceptors.length) return execute();
    return interceptors[index].interceptStream(
      ctx,
      () => _chainStream(ctx, index + 1, execute),
    );
  }
}

// ── Transaction facade interface ───────────────────────────────────────────

/// Common interface for wrapper-level transaction facades.
///
/// All driver wrappers expose a `trx()` method whose callback receives an
/// object implementing this interface — never a raw low-level session client.
/// This ensures that queries executed inside a transaction are routed through
/// the same [KnexInterceptorPipeline] as top-level queries, with [txId] set
/// so OTel spans can be linked to the parent transaction span.
///
/// ```dart
/// await db.trx((KnexTransaction tx) async {
///   await tx.insert(tx.queryBuilder().table('users').insert({'name': 'Alice'}));
///   await tx.insert(tx.queryBuilder().table('orders').insert({'user_id': 1}));
/// });
/// ```
abstract class KnexTransaction {
  /// Opaque identifier for this transaction, included in every
  /// [QueryExecutionContext.txId] produced inside this scope.
  String get txId;

  /// Creates a query builder scoped to this transaction's dialect.
  QueryBuilder queryBuilder();

  /// Callable shorthand for `queryBuilder().table(name)`.
  QueryBuilder call([String? tableName]);

  Future<List<Map<String, dynamic>>> select(QueryBuilder query);
  Future<List<Map<String, dynamic>>> execute(QueryBuilder query);
  Future<List<Map<String, dynamic>>> insert(QueryBuilder query);
  Future<List<Map<String, dynamic>>> update(QueryBuilder query);
  Future<List<Map<String, dynamic>>> delete(QueryBuilder query);

  /// Execute a raw SQL string inside this transaction.
  Future<List<Map<String, dynamic>>> rawSql(
    String sql, [
    List<dynamic>? bindings,
  ]);

  /// Stream rows inside this transaction.
  ///
  /// Supported by SQLite and DuckDB transaction facades. Other drivers throw
  /// [UnsupportedError] — check driver docs before calling.
  Stream<Map<String, dynamic>> streamQuery(QueryBuilder query) =>
      throw UnsupportedError(
        '$runtimeType.streamQuery() is not supported by this driver.',
      );

  /// Nest a transaction / savepoint inside this one.
  Future<T> trx<T>(Future<T> Function(KnexTransaction tx) callback);
}
