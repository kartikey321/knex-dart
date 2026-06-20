import 'dart:async';

import 'package:knex_dart/knex_dart.dart';
// common.dart (not sqlite3.dart) so this compiles for web too — sqlite3.dart
// pulls in the FFI implementation with `external` members that dart2js/dart
// compile js reject. SqliteUpdate is defined in the platform-neutral common.
import 'package:sqlite3/common.dart' show SqliteUpdate;

import 'sqlite_client.dart'
    if (dart.library.js_interop) 'sqlite_client_web.dart';

/// Returns the set of table names referenced by [query] (primary + joined).
Set<String> _tablesFrom(QueryBuilder query) {
  final tables = <String>{};
  final t = query.tableName;
  if (t is String) tables.add(t);
  for (final stmt in query.statements) {
    if (stmt['grouping'] == 'join') {
      final joinTable = stmt['table'];
      if (joinTable is String) {
        tables.add(joinTable);
      } else if (joinTable is JoinClause) {
        tables.add(joinTable.table);
      }
    }
  }
  return tables;
}

/// Wraps [source] with a batch-ceiling debounce.
///
/// Emits one event after [duration] of silence, OR after [maxCount] events
/// accumulate — whichever ceiling is hit first. Both are optional; if neither
/// is set the original stream is returned unchanged.
Stream<T> _batchDebounce<T>(
  Stream<T> source, {
  Duration? duration,
  int? maxCount,
}) {
  if (duration == null && maxCount == null) return source;

  late StreamController<T> controller;
  StreamSubscription<T>? sub;
  Timer? timer;
  int pending = 0;
  T? last;

  void flush() {
    timer?.cancel();
    timer = null;
    if (pending == 0) return; // nothing buffered — avoid re-emit on close
    pending = 0;
    final value = last as T;
    last = null;
    controller.add(value);
  }

  controller = StreamController<T>(
    onListen: () {
      sub = source.listen(
        (event) {
          last = event;
          pending++;
          if (maxCount != null && pending >= maxCount) {
            flush();
            return;
          }
          if (duration != null) {
            timer?.cancel();
            timer = Timer(duration, flush);
          }
        },
        onError: controller.addError,
        onDone: () {
          flush(); // emit any pending event before closing
          controller.close();
        },
      );
    },
    onCancel: () async {
      timer?.cancel();
      await sub?.cancel();
    },
  );
  return controller.stream;
}

/// SQLite-specific Knex wrapper.
class KnexSQLite with WatchableClient {
  final SQLiteClient _client;
  final KnexInterceptorPipeline _pipeline;

  KnexSQLite._(this._client, {required KnexInterceptorPipeline pipeline})
    : _pipeline = pipeline;

  /// Create a Knex instance connected to SQLite.
  ///
  /// Example:
  /// ```dart
  /// final db = await KnexSQLite.connect(filename: ':memory:');
  /// await db.executeSchema((s) {
  ///   s.createTable('users', (t) {
  ///     t.increments('id');
  ///     t.string('name');
  ///   });
  /// });
  ///
  /// await db.insert(db.queryBuilder().table('users').insert({'name': 'Alice'}));
  /// final rows = await db.select(db.queryBuilder().table('users'));
  /// await db.close();
  /// ```
  static Future<KnexSQLite> connect({
    required String filename,
    String? webStorageMode,
    List<QueryInterceptor> interceptors = const [],
  }) async {
    final client = await SQLiteClient.connect(
      filename: filename,
      webStorageMode: webStorageMode,
    );
    return KnexSQLite._(
      client,
      pipeline: KnexInterceptorPipeline(
        dbSystem: 'sqlite',
        interceptors: interceptors,
      ),
    );
  }

  /// Executes a SELECT-style query and returns rows.
  Future<List<Map<String, dynamic>>> select(QueryBuilder query) {
    final compiled = query.toSQL();
    return _pipeline.runCompiled(query, compiled, _client.executeCompiled);
  }

  /// Executes any compiled query and returns rows/result payload.
  Future<List<Map<String, dynamic>>> execute(QueryBuilder query) =>
      select(query);

  /// Executes an INSERT query.
  Future<List<Map<String, dynamic>>> insert(QueryBuilder query) =>
      select(query);

  /// Executes an UPDATE query.
  Future<List<Map<String, dynamic>>> update(QueryBuilder query) =>
      select(query);

  /// Executes a DELETE query.
  Future<List<Map<String, dynamic>>> delete(QueryBuilder query) =>
      select(query);

  /// Creates a raw SQL fragment for use inside QueryBuilder clauses.
  Raw raw(String sql, [List<dynamic>? bindings]) => _client.raw(sql, bindings);

  /// Execute a raw SQL string directly (runs through the interceptor pipeline).
  Future<List<Map<String, dynamic>>> rawSql(
    String sql, [
    List<dynamic>? bindings,
  ]) => _pipeline.runRaw(sql, bindings ?? const [], () async {
    final result = await _client.rawQuery(sql, bindings ?? []);
    return result is List<Map<String, dynamic>> ? result : [];
  });

  /// Creates a new query builder bound to this SQLite client.
  QueryBuilder queryBuilder() => _client.queryBuilder();

  /// Callable shorthand for `queryBuilder().table(name)`.
  QueryBuilder call([String? tableName]) {
    final builder = queryBuilder();
    return tableName != null ? builder.table(tableName) : builder;
  }

  /// Get a schema builder for executing DDL against this SQLite database.
  SchemaBuilder get schema => _client.schemaBuilder();

  /// Execute schema DDL operations.
  Future<void> executeSchema(
    void Function(SchemaBuilder schema) callback,
  ) async {
    final builder = _client.schemaBuilder();
    callback(builder);
    final statements = builder.toSQL();
    for (final stmt in statements) {
      final sql = stmt['sql'] as String;
      final bindings = (stmt['bindings'] as List<dynamic>?) ?? const [];
      await _pipeline.runRaw(
        sql,
        bindings,
        () => _client.rawQuery(sql, bindings),
      );
    }
  }

  /// Streams query results row by row.
  Stream<Map<String, dynamic>> streamQuery(
    QueryBuilder query,
  ) => _pipeline.runStream(query, () {
    final compiled = query.toSQL();
    // SQLiteClient.streamQuery uses the low-level (connection, sql, bindings)
    // signature; connection is ignored — SQLite is single-connection.
    return _client.streamQuery(null, compiled.sql, compiled.bindings);
  });

  /// Watches [query] and re-emits results whenever any of its source tables change.
  ///
  /// Emits the current result set immediately on subscription, then re-emits
  /// after each relevant write.
  ///
  /// [debounce] sets the silence window before a re-query is triggered.
  /// [maxPendingWrites] sets the write-count ceiling — a re-query fires as soon
  /// as this many writes accumulate, even if [debounce] has not elapsed.
  /// When both are set, whichever ceiling is hit first wins.
  ///
  /// Note: SQLite's UPDATE_HOOK does not fire for `DELETE` without a `WHERE`
  /// clause or for `WITHOUT ROWID` tables.
  @override
  Stream<List<Map<String, dynamic>>> watch(
    QueryBuilder query, {
    Duration? debounce,
    int? maxPendingWrites,
  }) {
    if (_client.isClosed) throw StateError('Cannot watch a closed database.');

    final tables = _tablesFrom(query);
    final controller = StreamController<List<Map<String, dynamic>>>();

    StreamSubscription<SqliteUpdate>? sub;
    var cancelled = false;
    var emitSeq = 0;

    Future<void> emit() async {
      if (cancelled || controller.isClosed) return;
      // Stamp this emission; discard result if a newer emit completes first.
      final seq = ++emitSeq;
      try {
        final rows = await select(query);
        if (seq == emitSeq && !cancelled && !controller.isClosed) {
          controller.add(rows);
        }
      } catch (e, st) {
        if (!cancelled && !controller.isClosed) controller.addError(e, st);
      }
    }

    controller.onListen = () {
      // Emit current results immediately after the listener attaches.
      Future.microtask(emit);

      Stream<SqliteUpdate> updateStream =
          _client.updates.where((u) => tables.contains(u.tableName));

      updateStream = _batchDebounce(
        updateStream,
        duration: debounce,
        maxCount: maxPendingWrites,
      );

      sub = updateStream.listen((_) => emit());
    };

    controller.onCancel = () async {
      cancelled = true;
      await sub?.cancel();
    };

    return controller.stream;
  }

  /// Run a transaction.
  Future<T> trx<T>(Future<T> Function(KnexSQLiteTransaction tx) callback) =>
      _client.trx((client) {
        final txId = _pipeline.nextUid();
        return callback(KnexSQLiteTransaction._(client, _pipeline, txId));
      });

  /// Closes the underlying SQLite database connection.
  Future<void> close() => _client.close();

  /// Alias for [close].
  Future<void> destroy() => close();
}

// ============================================================================
// WRAPPER-LEVEL TRANSACTION FACADE
// ============================================================================

class KnexSQLiteTransaction extends KnexTransaction {
  final SQLiteClient _client;
  final KnexInterceptorPipeline _pipeline;

  @override
  final String txId;

  KnexSQLiteTransaction._(this._client, this._pipeline, this.txId);

  @override
  QueryBuilder queryBuilder() => _client.queryBuilder();

  @override
  QueryBuilder call([String? tableName]) {
    final builder = queryBuilder();
    return tableName != null ? builder.table(tableName) : builder;
  }

  @override
  Future<List<Map<String, dynamic>>> select(QueryBuilder query) {
    final compiled = query.toSQL();
    return _pipeline.runCompiled(
      query,
      compiled,
      _client.executeCompiled,
      txId: txId,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> execute(QueryBuilder query) =>
      select(query);

  @override
  Future<List<Map<String, dynamic>>> insert(QueryBuilder query) =>
      select(query);

  @override
  Future<List<Map<String, dynamic>>> update(QueryBuilder query) =>
      select(query);

  @override
  Future<List<Map<String, dynamic>>> delete(QueryBuilder query) =>
      select(query);

  @override
  Future<List<Map<String, dynamic>>> rawSql(
    String sql, [
    List<dynamic>? bindings,
  ]) => _pipeline.runRaw(sql, bindings ?? const [], () async {
    final result = await _client.rawQuery(sql, bindings ?? []);
    return result is List<Map<String, dynamic>> ? result : [];
  }, txId: txId);

  /// Stream results inside this transaction.
  @override
  Stream<Map<String, dynamic>> streamQuery(QueryBuilder query) =>
      _pipeline.runStream(query, () {
        final compiled = query.toSQL();
        return _client.streamQuery(null, compiled.sql, compiled.bindings);
      }, txId: txId);

  @override
  Future<T> trx<T>(
    Future<T> Function(KnexTransaction tx) callback,
  ) => _client.trx((client) {
    // SQLite manages savepoints internally via its own trx() — no SAVEPOINT
    // SQL flows through the pipeline.  Child txId still carries parent prefix
    // so OTel spans can be correlated by txId hierarchy.
    final childTxId = '${txId}_sp_${_pipeline.nextUid()}';
    return callback(KnexSQLiteTransaction._(client, _pipeline, childTxId));
  });
}
