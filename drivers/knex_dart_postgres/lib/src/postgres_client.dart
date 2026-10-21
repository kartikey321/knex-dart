import 'dart:async';

import 'package:postgres/postgres.dart';
import 'package:knex_dart/knex_dart.dart';

/// PostgreSQL database client backed by a connection pool.
///
/// Connects to PostgreSQL databases and executes queries compiled by QueryBuilder.
/// Uses the `postgres` package's native [Pool] for connection pooling.
class PostgresClient {
  final Pool<void> _pool;
  bool _isClosed = false;

  /// Zone key under which [runInTransaction] pins the active [_PinnedSession].
  ///
  /// A plain instance field cannot distinguish "the same logical transaction
  /// calling back into itself" from "a completely unrelated concurrent
  /// caller" — both just see a non-null field. Storing the session as a
  /// [Zone] value instead means each top-level [runInTransaction] call forks
  /// its own zone: a genuine nested call (made from within [action]'s own
  /// async call graph) inherits that zone and correctly reuses the session,
  /// while a concurrent, unrelated call runs in a sibling zone that never
  /// sees it — so it correctly acquires its own connection and transaction
  /// instead of silently sharing (and corrupting) someone else's.
  ///
  /// **Must be a per-instance key, not a shared constant**: a `static`/const
  /// key would make one [PostgresClient]'s pinned session visible to every
  /// *other* [PostgresClient] instance whose code happens to run nested
  /// inside the same zone (e.g. a callback that reaches into a second
  /// client) — routing that second client's queries onto the first
  /// client's connection. A fresh [Object] per instance rules that out:
  /// `Zone` value lookups key on identity, so no other instance's key can
  /// ever match this one's.
  final Object _txSessionZoneKey = Object();

  /// Pinned transaction session for the currently executing zone, set only
  /// while [runInTransaction] is active on this call chain.
  ///
  /// When non-null, [rawSql] and [_run] route queries through this session
  /// instead of acquiring a new pool connection — ensuring all statements
  /// inside the migration step land on the same physical connection.
  ///
  /// See [_txSessionZoneKey] for why this is zone-scoped rather than a plain
  /// field: that's what makes concurrent [runInTransaction] calls on the same
  /// client instance safe, not just sequential ones. Fully concurrent
  /// transaction use can also reach for [trx], which scopes the session to
  /// the callback closure explicitly.
  ///
  /// Throws [StateError] if the pinned session's [runInTransaction] call has
  /// already completed — this happens if [action] leaks an un-awaited
  /// callback (a detached `Future`, a `Timer`, a stream listener) that
  /// outlives [action] itself and later tries to run a query. That callback
  /// still runs inside the forked zone (zone values are retained by
  /// anything scheduled from within it, not just [action]'s own direct
  /// execution), so without this check it would silently reuse a session
  /// whose connection may already be back in the pool — the throw makes
  /// that a loud, immediate failure instead.
  TxSession? get _txSession {
    final pinned = Zone.current[_txSessionZoneKey] as _PinnedSession?;
    if (pinned == null) return null;
    if (pinned.completed) {
      throw StateError(
        'PostgresClient: attempted to use a transaction session after its '
        'runInTransaction() call already completed. This happens when '
        '`action` leaves an un-awaited Future/Timer/stream listener running '
        'that later executes a query — await all work started inside '
        'runInTransaction() before it returns.',
      );
    }
    return pinned.session;
  }

  PostgresClient._(this._pool);

  /// Creates a new PostgreSQL client connected to the database via a pool.
  ///
  /// [poolConfig] controls pool size and acquire timeout.
  ///
  /// [applicationName], if set, is sent to the server as the
  /// `application_name` startup parameter — visible in `pg_stat_activity`
  /// and server logs, useful for identifying which application/service a
  /// given connection belongs to. Left unset by default (no parameter sent).
  ///
  /// [queryTimeout], if set, aborts a single query after it runs this long
  /// (protects against a runaway query holding a connection indefinitely).
  /// Distinct from [PoolConfig.acquireTimeoutMillis], which only bounds how
  /// long acquiring a connection from the pool may take.
  ///
  /// [timeZone], if set, is sent as the session's `TimeZone` startup
  /// parameter (e.g. `'UTC'`, `'America/New_York'`) — equivalent to `SET
  /// TIME ZONE` for every connection in the pool.
  static Future<PostgresClient> connect({
    required String host,
    int port = 5432,
    required String database,
    required String username,
    String? password,
    bool useSSL = false,
    PoolConfig poolConfig = const PoolConfig(),
    String? applicationName,
    Duration? queryTimeout,
    String? timeZone,
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
        applicationName: applicationName,
        queryTimeout: queryTimeout,
        timeZone: timeZone,
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
  /// and pins [_txSession] (via a forked [Zone], see [_txSessionZoneKey]) for
  /// the duration of [action]. Any [rawSql] or query call made inside
  /// [action] — including through further `await`s — is automatically
  /// routed to that pinned session.
  ///
  /// **Reentrancy guard**: if [_txSession] is already set *on this call
  /// chain* (i.e., [action] itself calls back into [runInTransaction]),
  /// the nested call runs directly without opening a new transaction —
  /// preventing nested `BEGIN` errors. A concurrent, unrelated
  /// [runInTransaction] call on the same [PostgresClient] runs in a sibling
  /// zone and correctly opens its own independent transaction instead of
  /// colliding with this one.
  ///
  /// This is the correct hook for the knex-dart Migrator when
  /// `MigrationConfig.disableTransactions` is `false`. The migrator's internal
  /// `rawQuery` calls (e.g., INSERT into `knex_migrations`) are routed through
  /// the same session as the migration SQL itself.
  Future<T> runInTransaction<T>(Future<T> Function() action) {
    if (_txSession != null) {
      // Already pinned on this call chain — run directly to avoid nested BEGIN.
      return action();
    }
    return _pool.withConnection(
      (conn) => conn.runTx((session) async {
        final pinned = _PinnedSession(session);
        try {
          return await runZoned(
            action,
            zoneValues: {_txSessionZoneKey: pinned},
          );
        } finally {
          // Marks the session unusable for anything that outlived `action`
          // (a leaked Future/Timer/stream listener) — see _txSession's doc
          // comment. Without this, such a caller would silently reuse a
          // session whose connection may already be back in the pool.
          pinned.completed = true;
        }
      }),
    );
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

/// Wraps a [TxSession] pinned via [PostgresClient.runInTransaction] with a
/// liveness flag, so a callback that outlives its [PostgresClient._run]
/// (a leaked `Future`/`Timer`/stream listener) fails loudly instead of
/// silently reusing a session whose connection may already be back in the
/// pool. See [PostgresClient._txSession]'s doc comment.
class _PinnedSession {
  final TxSession session;
  bool completed = false;

  _PinnedSession(this.session);
}

/// Low-level transaction-scoped Postgres session executor.
///
/// This is an implementation detail of [KnexPostgres]. User code should
/// interact with [KnexPostgresTransaction] received from [KnexPostgres.trx],
/// which routes queries through the [KnexInterceptorPipeline].
class PostgresTrxClient {
  final TxSession _session;

  PostgresTrxClient._(this._session);

  /// Callable shorthand for `queryBuilder().table(name)` within the PG dialect.
  QueryBuilder call([String? tableName]) {
    final builder = KnexQuery.forClient('pg').queryBuilder();
    return tableName != null ? builder.table(tableName) : builder;
  }

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
    } catch (e, st) {
      try {
        await rawSql('ROLLBACK TO SAVEPOINT $sp');
      } catch (_) {}
      Error.throwWithStackTrace(e, st);
    }
  }

  static var _spCount = 0;
  String _savepointId() => 'sp_${(++_spCount).toRadixString(36)}';
}
