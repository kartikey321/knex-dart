import 'dart:async';

import 'package:mysql_client/mysql_client.dart';
import 'package:knex_dart/src/query/query_builder.dart';
import 'package:knex_dart/src/client/knex_config.dart';

import 'pool.dart';

// ─── Public client ────────────────────────────────────────────────────────────

/// MySQL database client backed by a connection pool.
///
/// Connects to MySQL databases and executes queries compiled by QueryBuilder.
/// Uses the `mysql_client` package for modern MySQL 8.0 support.
class MySQLClient {
  final TarnPool<MySQLConnection> _pool;
  bool _isClosed = false;

  /// Pinned transaction connection, set only while [runInTransaction] is active.
  ///
  /// When non-null, [_execute] routes queries through this connection instead
  /// of acquiring a new pool connection — ensuring all statements inside the
  /// migration step land on the same physical connection.
  ///
  /// Dart's single-threaded event loop makes this field safe for sequential
  /// callers (e.g., the Migrator). Concurrent transactions should use [trx]
  /// instead, which scopes the connection to the callback closure.
  MySQLConnection? _txConn;

  MySQLClient._(this._pool);

  /// Creates a new MySQL client connected to the database via a pool.
  ///
  /// [poolConfig] controls pool size, acquire timeout, idle reaping, and min connections.
  static Future<MySQLClient> connect({
    required String host,
    int port = 3306,
    required String user,
    String? password,
    required String database,
    bool useSSL = false,
    PoolConfig poolConfig = const PoolConfig(),
  }) async {
    Future<MySQLConnection> makeConnection() async {
      final conn = await MySQLConnection.createConnection(
        host: host,
        port: port,
        userName: user,
        password: password ?? '',
        databaseName: database,
        secure: useSSL,
      );
      await conn.connect();
      return conn;
    }

    final pool = TarnPool<MySQLConnection>(
      create: makeConnection,
      destroy: (conn) => conn.close(),
      min: poolConfig.min,
      max: poolConfig.max,
      acquireTimeout: Duration(milliseconds: poolConfig.acquireTimeoutMillis),
      idleTimeout: Duration(
        milliseconds: poolConfig.idleTimeoutMillis ?? 30000,
      ),
      reapInterval: Duration(milliseconds: poolConfig.reapIntervalMillis),
    );

    return MySQLClient._(pool);
  }

  /// Executes a query (SELECT, INSERT, UPDATE, DELETE) and returns results.
  Future<List<Map<String, dynamic>>> query(QueryBuilder queryBuilder) async {
    if (_isClosed) {
      throw StateError('Cannot execute query on closed pool');
    }

    final compiled = queryBuilder.toSQL();

    // Debug: Print SQL and bindings
    print('SQL: ${compiled.sql}');
    print('Bindings: ${compiled.bindings}');

    return _execute(compiled.sql, compiled.bindings);
  }

  /// Executes a raw SQL query
  Future<List<Map<String, dynamic>>> raw(
    String sql, [
    List<dynamic>? bindings,
  ]) async {
    if (_isClosed) {
      throw StateError('Cannot execute query on closed pool');
    }
    return _execute(sql, bindings);
  }

  Future<List<Map<String, dynamic>>> _execute(
    String sql, [
    List<dynamic>? bindings,
  ]) async {
    // Route through the pinned connection when inside runInTransaction.
    if (_txConn != null) {
      return _executeOnConn(_txConn!, sql, bindings);
    }

    final conn = await _pool.acquire();
    bool success = false;
    try {
      final result = await _executeOnConn(conn, sql, bindings);
      success = true;
      return result;
    } finally {
      if (success) {
        // Query succeeded — connection is healthy, return to pool.
        _pool.release(conn);
      } else {
        // Query threw — connection may be broken; discard rather than recycle.
        _pool.discard(conn);
      }
    }
  }

  /// Execute [sql] on [conn] without any pool acquire/release.
  Future<List<Map<String, dynamic>>> _executeOnConn(
    MySQLConnection conn,
    String sql, [
    List<dynamic>? bindings,
  ]) async {
    if (bindings == null || bindings.isEmpty) {
      final res = await conn.execute(sql);
      return _mapResults(res);
    }
    final stmt = await conn.prepare(sql);
    try {
      final res = await stmt.execute(bindings);
      return _mapResults(res);
    } finally {
      await stmt.deallocate();
    }
  }

  /// Alias for query() to match PostgresClient API
  Future<List<Map<String, dynamic>>> select(QueryBuilder queryBuilder) =>
      query(queryBuilder);

  /// Execute any QueryBuilder query (SELECT, INSERT, UPDATE, DELETE)
  Future<List<Map<String, dynamic>>> execute(QueryBuilder queryBuilder) =>
      query(queryBuilder);

  /// Execute an INSERT query.
  Future<List<Map<String, dynamic>>> insert(QueryBuilder queryBuilder) =>
      query(queryBuilder);

  /// Execute an UPDATE query.
  Future<List<Map<String, dynamic>>> update(QueryBuilder queryBuilder) =>
      query(queryBuilder);

  /// Execute a DELETE query.
  Future<List<Map<String, dynamic>>> delete(QueryBuilder queryBuilder) =>
      query(queryBuilder);

  /// Maps MySQL Results to a standard List<Map> format.
  List<Map<String, dynamic>> _mapResults(IResultSet results) {
    final rows = <Map<String, dynamic>>[];
    for (final row in results.rows) {
      rows.add(row.typedAssoc());
    }
    return rows;
  }

  /// Closes the connection pool.
  Future<void> close() async {
    if (!_isClosed) {
      _isClosed = true;
      await _pool.close();
    }
  }

  /// Database dialect name.
  String get dialect => 'mysql';

  /// Whether the pool is closed.
  bool get isClosed => _isClosed;

  // ─── Transaction support ──────────────────────────────────────────────────

  /// Run [action] inside a MySQL transaction, pinning one pool connection.
  ///
  /// Acquires a single connection, issues `START TRANSACTION`, and sets
  /// [_txConn] for the duration of [action]. Any [_execute] call made inside
  /// [action] (via [query], [raw], etc.) is automatically routed to that
  /// pinned connection.
  ///
  /// **Reentrancy guard**: if [_txConn] is already set (i.e., this is called
  /// from within an active [runInTransaction] scope), [action] is run directly
  /// without issuing a new `START TRANSACTION` — preventing nested transaction
  /// errors.
  ///
  /// This is the correct hook for the knex-dart Migrator when
  /// `MigrationConfig.disableTransactions` is `false`. The migrator's internal
  /// rawQuery calls (e.g., INSERT into `knex_migrations`) are routed through
  /// the same connection as the migration SQL itself.
  Future<T> runInTransaction<T>(Future<T> Function() action) async {
    if (_txConn != null) {
      // Already pinned — run directly to avoid nested START TRANSACTION.
      return action();
    }
    if (_isClosed) throw StateError('Pool is closed');
    final conn = await _pool.acquire();
    bool success = false;
    try {
      await conn.execute('START TRANSACTION');
      _txConn = conn;
      try {
        final result = await action();
        await conn.execute('COMMIT');
        success = true;
        return result;
      } catch (e) {
        await conn.execute('ROLLBACK');
        rethrow;
      } finally {
        _txConn = null;
      }
    } finally {
      if (success) {
        _pool.release(conn);
      } else {
        _pool.discard(conn);
      }
    }
  }

  /// Run [callback] inside a MySQL transaction.
  ///
  /// Acquires a single connection from the pool, pins it for the entire
  /// transaction, then releases it. The callback receives a [MySQLTrxClient]
  /// that runs all queries on that pinned connection.
  ///
  /// Automatically COMMITs on success and ROLLBACKs on error.
  ///
  /// Example:
  /// ```dart
  /// await client.trx((trx) async {
  ///   await trx.execute(mockClient.queryBuilder().table('accounts')
  ///     .where('id', 1).update({'balance': 500}));
  ///   await trx.execute(mockClient.queryBuilder().table('accounts')
  ///     .where('id', 2).update({'balance': 1500}));
  /// });
  /// ```
  Future<T> trx<T>(Future<T> Function(MySQLTrxClient trx) callback) async {
    if (_isClosed) throw StateError('Pool is closed');
    final conn = await _pool.acquire();
    try {
      await conn.execute('START TRANSACTION');
      try {
        final result = await callback(MySQLTrxClient._(conn));
        await conn.execute('COMMIT');
        return result;
      } catch (e) {
        await conn.execute('ROLLBACK');
        rethrow;
      }
    } finally {
      _pool.release(conn);
    }
  }
}

/// A transaction-scoped MySQL client.
///
/// Wraps the underlying [MySQLConnection] and exposes the same
/// execute/insert/update/delete/select API as [MySQLClient], so callbacks
/// passed to [MySQLClient.trx] work identically.
class MySQLTrxClient {
  final MySQLConnection _connection;

  MySQLTrxClient._(this._connection);

  Future<List<Map<String, dynamic>>> select(QueryBuilder queryBuilder) =>
      _run(queryBuilder);

  Future<List<Map<String, dynamic>>> execute(QueryBuilder queryBuilder) =>
      _run(queryBuilder);

  Future<List<Map<String, dynamic>>> insert(QueryBuilder queryBuilder) =>
      _run(queryBuilder);

  Future<List<Map<String, dynamic>>> update(QueryBuilder queryBuilder) =>
      _run(queryBuilder);

  Future<List<Map<String, dynamic>>> delete(QueryBuilder queryBuilder) =>
      _run(queryBuilder);

  Future<List<Map<String, dynamic>>> _run(QueryBuilder queryBuilder) async {
    final compiled = queryBuilder.toSQL();
    print('TRX SQL: ${compiled.sql}');
    print('TRX Bindings: ${compiled.bindings}');
    if (compiled.bindings.isEmpty) {
      final result = await _connection.execute(compiled.sql);
      return _mapResults(result);
    }
    final stmt = await _connection.prepare(compiled.sql);
    final result = await stmt.execute(compiled.bindings);
    await stmt.deallocate();
    return _mapResults(result);
  }

  List<Map<String, dynamic>> _mapResults(IResultSet results) {
    final rows = <Map<String, dynamic>>[];
    for (final row in results.rows) {
      rows.add(row.typedAssoc());
    }
    return rows;
  }

  // ─── Nested transactions (savepoints) ────────────────────────────────────

  /// Run [callback] inside a savepoint on this already-open transaction.
  ///
  /// Allows nested transaction semantics: the inner scope can roll back
  /// without aborting the outer transaction.
  Future<T> trx<T>(Future<T> Function(MySQLTrxClient trx) callback) async {
    final sp = _savepointId();
    await _connection.execute('SAVEPOINT $sp');
    try {
      final result = await callback(this);
      await _connection.execute('RELEASE SAVEPOINT $sp');
      return result;
    } catch (e) {
      await _connection.execute('ROLLBACK TO SAVEPOINT $sp');
      rethrow;
    }
  }

  String _savepointId() =>
      'sp_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
}
