import 'package:postgres/postgres.dart';
import 'package:knex_dart/knex_dart.dart';

/// PostgreSQL database client backed by a connection pool.
///
/// Connects to PostgreSQL databases and executes queries compiled by QueryBuilder.
/// Uses the `postgres` package's native [Pool] for connection pooling.
class PostgresClient {
  final Pool<void> _pool;
  bool _isClosed = false;

  /// Pinned transaction session, set only while [runInTransaction] is active.
  ///
  /// When non-null, [rawSql] and [_run] route queries through this session
  /// instead of acquiring a new pool connection — ensuring all statements
  /// inside the migration step land on the same physical connection.
  ///
  /// Dart's single-threaded event loop makes this field safe for sequential
  /// callers (e.g., the Migrator). Concurrent transactions should use [trx]
  /// instead, which scopes the session to the callback closure.
  TxSession? _txSession;

  PostgresClient._(this._pool);

  /// Creates a new PostgreSQL client connected to the database via a pool.
  ///
  /// [poolConfig] controls pool size and acquire timeout.
  static Future<PostgresClient> connect({
    required String host,
    int port = 5432,
    required String database,
    required String username,
    String? password,
    bool useSSL = false,
    PoolConfig poolConfig = const PoolConfig(),
  }) async {
    final endpoint = Endpoint(
      host: host,
      port: port,
      database: database,
      username: username,
      password: password,
    );

    final pool = Pool<void>.withEndpoints(
      [endpoint],
      settings: PoolSettings(
        maxConnectionCount: poolConfig.max,
        sslMode: useSSL ? SslMode.require : SslMode.disable,
        connectTimeout: Duration(milliseconds: poolConfig.acquireTimeoutMillis),
      ),
    );

    return PostgresClient._(pool);
  }

  /// Executes a SELECT query and returns the results.
  Future<List<Map<String, dynamic>>> select(QueryBuilder query) => _run(query);

  /// Execute any QueryBuilder query (SELECT, INSERT, UPDATE, DELETE)
  Future<List<Map<String, dynamic>>> execute(QueryBuilder query) => _run(query);

  /// Execute an INSERT query.
  /// Returns the inserted rows if a RETURNING clause is present.
  Future<List<Map<String, dynamic>>> insert(QueryBuilder query) => _run(query);

  /// Execute an UPDATE query.
  Future<List<Map<String, dynamic>>> update(QueryBuilder query) => _run(query);

  /// Execute a DELETE query.
  Future<List<Map<String, dynamic>>> delete(QueryBuilder query) => _run(query);

  Future<List<Map<String, dynamic>>> _run(QueryBuilder query) async {
    if (_isClosed) {
      throw StateError('Cannot execute query on closed pool');
    }

    final compiled = query.toSQL();

    // Debug: Print SQL and bindings
    print('SQL: ${compiled.sql}');
    print('Bindings: ${compiled.bindings}');

    if (_txSession != null) {
      final result = await _txSession!.execute(
        compiled.sql,
        parameters: compiled.bindings,
      );
      return _mapResults(result);
    }

    return _pool.withConnection((conn) async {
      final result = await conn.execute(
        compiled.sql,
        parameters: compiled.bindings,
      );
      return _mapResults(result);
    });
  }

  /// Converts PostgreSQL Result to List of Maps.
  List<Map<String, dynamic>> _mapResults(Result pgResult) {
    final results = <Map<String, dynamic>>[];

    for (final row in pgResult) {
      final map = <String, dynamic>{};
      final schema = pgResult.schema;

      for (var i = 0; i < schema.columns.length; i++) {
        final columnName = schema.columns[i].columnName ?? 'column_$i';
        map[columnName] = row[i];
      }

      results.add(map);
    }

    return results;
  }

  /// Closes the connection pool.
  Future<void> close() async {
    if (!_isClosed) {
      _isClosed = true;
      await _pool.close();
    }
  }

  /// Execute a raw SQL query directly and return results as a List of Maps.
  ///
  /// When [runInTransaction] is active, queries are automatically routed to
  /// the pinned transaction session.
  Future<List<Map<String, dynamic>>> rawSql(
    String sql, [
    List<dynamic>? bindings,
  ]) async {
    if (_isClosed) {
      throw StateError('Cannot execute query on closed pool');
    }
    print('SQL: $sql');
    print('Bindings: $bindings');
    final params = bindings ?? [];
    if (_txSession != null) {
      final result = await _txSession!.execute(sql, parameters: params);
      return _mapResults(result);
    }
    return _pool.withConnection((conn) async {
      final result = await conn.execute(sql, parameters: params);
      return _mapResults(result);
    });
  }

  /// Database dialect name.
  String get dialect => 'postgres';

  /// Whether the pool is closed.
  bool get isClosed => _isClosed;

  // ─── Transaction support ──────────────────────────────────────────────────

  /// Run [action] inside a Postgres transaction, pinning one pool connection.
  ///
  /// Acquires a single connection, opens a transaction via [Connection.runTx],
  /// and sets [_txSession] for the duration of [action]. Any [rawSql] or query
  /// call made inside [action] is automatically routed to that pinned session.
  ///
  /// **Reentrancy guard**: if [_txSession] is already set (i.e., this is called
  /// from within an active [runInTransaction] scope), [action] is run directly
  /// without opening a new transaction — preventing nested `BEGIN` errors.
  ///
  /// This is the correct hook for the knex-dart Migrator when
  /// `MigrationConfig.disableTransactions` is `false`. The migrator's internal
  /// `rawQuery` calls (e.g., INSERT into `knex_migrations`) are routed through
  /// the same session as the migration SQL itself.
  Future<T> runInTransaction<T>(Future<T> Function() action) {
    if (_txSession != null) {
      // Already pinned — run directly to avoid nested BEGIN.
      return action();
    }
    return _pool.withConnection(
      (conn) => conn.runTx(
        (session) => _withPinnedSession(session, action),
      ),
    );
  }

  /// Sets [_txSession] for the duration of [action], then clears it.
  Future<T> _withPinnedSession<T>(
    TxSession session,
    Future<T> Function() action,
  ) async {
    _txSession = session;
    try {
      return await action();
    } finally {
      _txSession = null;
    }
  }

  /// Run [callback] inside a Postgres transaction.
  ///
  /// Acquires a single connection from the pool, pins it for the duration of
  /// the transaction, then releases it. The callback receives a
  /// [PostgresTrxClient] backed by the transaction session.
  ///
  /// Automatically COMMITs on success and ROLLBACKs on error.
  ///
  /// Example:
  /// ```dart
  /// await pgClient.trx((trx) async {
  ///   await trx.execute(mockClient.queryBuilder().table('users')
  ///     .where('id', 1).update({'active': false}));
  ///   await trx.execute(mockClient.queryBuilder().table('audit')
  ///     .insert({'action': 'deactivate', 'user_id': 1}));
  /// });
  /// ```
  Future<T> trx<T>(Future<T> Function(PostgresTrxClient trx) callback) async {
    if (_isClosed) throw StateError('Pool is closed');
    return _pool.withConnection(
      (conn) => conn.runTx(
        (session) => callback(PostgresTrxClient._(session)),
      ),
    );
  }
}

/// A transaction-scoped Postgres client.
///
/// Wraps a [TxSession] and exposes the same execute/insert/update/delete/select
/// API as [PostgresClient], so callbacks passed to [PostgresClient.trx] can
/// use the exact same interface.
class PostgresTrxClient {
  final TxSession _session;

  PostgresTrxClient._(this._session);

  /// Executes a SELECT-style query inside this transaction.
  Future<List<Map<String, dynamic>>> select(QueryBuilder query) => _run(query);

  /// Executes any compiled query inside this transaction.
  Future<List<Map<String, dynamic>>> execute(QueryBuilder query) => _run(query);

  /// Executes an INSERT query inside this transaction.
  Future<List<Map<String, dynamic>>> insert(QueryBuilder query) => _run(query);

  /// Executes an UPDATE query inside this transaction.
  Future<List<Map<String, dynamic>>> update(QueryBuilder query) => _run(query);

  /// Executes a DELETE query inside this transaction.
  Future<List<Map<String, dynamic>>> delete(QueryBuilder query) => _run(query);

  /// Executes raw SQL inside this transaction.
  Future<List<Map<String, dynamic>>> rawSql(
    String sql, [
    List<dynamic>? bindings,
  ]) async {
    final result = await _session.execute(sql, parameters: bindings ?? []);
    return _mapResults(result);
  }

  Future<List<Map<String, dynamic>>> _run(QueryBuilder query) async {
    final compiled = query.toSQL();
    print('TRX SQL: ${compiled.sql}');
    print('TRX Bindings: ${compiled.bindings}');
    final result = await _session.execute(
      compiled.sql,
      parameters: compiled.bindings,
    );
    return _mapResults(result);
  }

  List<Map<String, dynamic>> _mapResults(Result pgResult) {
    final results = <Map<String, dynamic>>[];
    for (final row in pgResult) {
      final map = <String, dynamic>{};
      final schema = pgResult.schema;
      for (var i = 0; i < schema.columns.length; i++) {
        final columnName = schema.columns[i].columnName ?? 'column_$i';
        map[columnName] = row[i];
      }
      results.add(map);
    }
    return results;
  }

  // ─── Nested transactions (savepoints) ────────────────────────────────────

  /// Run [callback] inside a savepoint on this already-open transaction.
  ///
  /// Allows nested transaction semantics: the inner scope can roll back
  /// without aborting the outer transaction.
  Future<T> trx<T>(Future<T> Function(PostgresTrxClient trx) callback) async {
    final sp = _savepointId();
    await rawSql('SAVEPOINT $sp');
    try {
      final result = await callback(this);
      await rawSql('RELEASE SAVEPOINT $sp');
      return result;
    } catch (e) {
      await rawSql('ROLLBACK TO SAVEPOINT $sp');
      rethrow;
    }
  }

  String _savepointId() =>
      'sp_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
}
