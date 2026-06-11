import 'dart:async';
import 'package:sqlite3/sqlite3.dart';

import 'package:knex_dart/knex_dart.dart';

/// SQLite database client.
class SQLiteClient extends Client {
  late Database _db;
  final String _filename;
  bool _isClosed = false;

  /// Depth counter for nested transactions (0 = no active transaction).
  int _transactionDepth = 0;

  /// Per-level update buffers. One entry is pushed per BEGIN/SAVEPOINT and
  /// popped on COMMIT/ROLLBACK. Events are forwarded to [_updateController]
  /// only on the outermost COMMIT, preventing watch() from seeing phantom rows
  /// from uncommitted or rolled-back transactions.
  final List<List<SqliteUpdate>> _txUpdateStack = [];

  late final StreamController<SqliteUpdate> _updateController;
  StreamSubscription<SqliteUpdate>? _updatesSub;

  /// Prepared statement cache keyed by SQL string.
  ///
  /// Avoids repeated `sqlite3_prepare` calls for identical SQL, which is the
  /// dominant cost for short repeated queries (SELECT/INSERT/UPDATE/DELETE).
  /// Statements are disposed when [close] is called.
  final Map<String, PreparedStatement> _stmtCache = {};

  SQLiteClient._(this._filename, KnexConfig config) : super(config);

  /// Create a SQLite client directly from [KnexConfig].
  ///
  /// This is synchronous because sqlite3 opens local files synchronously.
  static SQLiteClient fromConfig(KnexConfig config) {
    final connection = config.connection;
    final filename = switch (connection) {
      String s => s,
      Map m when m['filename'] is String => m['filename'] as String,
      _ => throw ArgumentError(
        'SQLite config.connection must be a filename String '
        'or Map containing a String "filename".',
      ),
    };

    final client = SQLiteClient._(filename, config);
    client._db = sqlite3.open(filename);
    client._setupUpdateHook();
    return client;
  }

  /// Creates and opens a SQLite client for [filename].
  static Future<SQLiteClient> connect({required String filename}) async {
    final config = KnexConfig(
      client: 'sqlite3',
      connection: {'filename': filename},
    );
    final client = SQLiteClient._(filename, config);
    await client.initialize();
    return client;
  }

  /// Opens the underlying SQLite database file.
  Future<void> initialize() async {
    _db = sqlite3.open(_filename);
    _setupUpdateHook();
  }

  void _setupUpdateHook() {
    // sync: true ensures watch() listeners are notified within the same call
    // stack as the write, matching Drift's internal dispatch pattern.
    _updateController = StreamController<SqliteUpdate>.broadcast(sync: true);
    _updatesSub = _db.updates.listen((update) {
      if (_updateController.isClosed) return;
      if (_txUpdateStack.isNotEmpty) {
        _txUpdateStack.last.add(update);
      } else {
        _updateController.add(update);
      }
    });
  }

  @override
  String get driverName => 'sqlite3';

  @override
  void initializeDriver() {
    // No-op for sqlite3 package
  }

  @override
  void initializePool([PoolConfig? poolConfig]) {
    // No pool for SQLite in this phase
  }

  @override
  Future<dynamic> acquireConnection() async {
    return _db;
  }

  @override
  Future<void> releaseConnection(dynamic connection) async {
    // No-op
  }

  Future<void> destroyPool() async {
    if (_isClosed) return;
    _isClosed = true;
    for (final stmt in _stmtCache.values) {
      stmt.dispose();
    }
    _stmtCache.clear();
    // Cancel before dispose so any in-flight async events from _db.updates
    // don't reach _updateController after it is closed.
    await _updatesSub?.cancel();
    _db.dispose();
    await _updateController.close();
  }

  /// Whether the connection is closed.
  bool get isClosed => _isClosed;

  /// Stream of low-level table mutation events from SQLite's UPDATE_HOOK.
  ///
  /// Events are buffered while a transaction is active and flushed only on
  /// top-level COMMIT, so [watch] never sees phantom rows from uncommitted or
  /// rolled-back writes.
  Stream<SqliteUpdate> get updates => _updateController.stream;

  /// Close the database connection.
  Future<void> close() => destroyPool();

  @override
  QueryBuilder queryBuilder() {
    return QueryBuilder(this);
  }

  /// Callable shorthand for `queryBuilder().table(name)`.
  QueryBuilder call([String? tableName]) {
    final builder = queryBuilder();
    return tableName != null ? builder.table(tableName) : builder;
  }

  @override
  QueryCompiler queryCompiler(QueryBuilder builder) {
    return QueryCompiler(this, builder);
  }

  @override
  dynamic formatter(dynamic builder) {
    return Formatter(this, builder);
  }

  @override
  SchemaBuilder schemaBuilder() {
    return SchemaBuilder(this);
  }

  @override
  SchemaCompiler schemaCompiler(SchemaBuilder builder) {
    return SchemaCompiler(this, builder);
  }

  @override
  Future<Transaction> transaction([TransactionConfig? config]) async {
    throw UnimplementedError('Use beginTransaction() for SQLite transactions');
  }

  /// Run [callback] inside a SQLite transaction (or savepoint for nesting).
  ///
  /// The callback receives this same [SQLiteClient] instance.
  ///
  /// - **Top-level** (`_transactionDepth == 0`): wraps with BEGIN / COMMIT /
  ///   ROLLBACK.
  /// - **Nested** (`_transactionDepth > 0`): uses SAVEPOINT / RELEASE SAVEPOINT
  ///   / ROLLBACK TO SAVEPOINT, so the inner scope can roll back independently
  ///   without affecting the outer transaction.
  ///
  /// Example:
  /// ```dart
  /// await client.trx((outer) async {
  ///   await outer.insert(...);
  ///   await outer.trx((inner) async {   // uses SAVEPOINT
  ///     await inner.insert(...);
  ///   });
  /// });
  /// ```
  /// Implements [Client.runInTransaction] by delegating to [trx].
  ///
  /// This ensures the migrator's `runInTransaction` calls respect the
  /// [_transactionDepth] counter and produce SAVEPOINT SQL when nested.
  @override
  Future<T> runInTransaction<T>(Future<T> Function() action) {
    return trx((_) => action());
  }

  /// Executes [callback] in a transaction/savepoint scope.
  Future<T> trx<T>(Future<T> Function(SQLiteClient trx) callback) async {
    if (_transactionDepth > 0) {
      final sp = _savepointId();
      _transactionDepth++;
      _txUpdateStack.add([]);
      _db.execute('SAVEPOINT $sp');
      try {
        final result = await callback(this);
        _db.execute('RELEASE SAVEPOINT $sp');
        // Merge savepoint's buffered updates into the parent level so they
        // survive to the outermost COMMIT.
        final saved = _txUpdateStack.removeLast();
        _txUpdateStack.last.addAll(saved);
        return result;
      } catch (e, st) {
        try {
          _db.execute('ROLLBACK TO SAVEPOINT $sp');
        } catch (_) {}
        _txUpdateStack.removeLast(); // discard rolled-back updates
        Error.throwWithStackTrace(e, st);
      } finally {
        _transactionDepth--;
      }
    } else {
      _transactionDepth++;
      _txUpdateStack.add([]);
      _db.execute('BEGIN');
      try {
        final result = await callback(this);
        _db.execute('COMMIT');
        // Flush all buffered updates now that the transaction is committed.
        final committed = _txUpdateStack.removeLast();
        for (final u in committed) {
          if (!_updateController.isClosed) _updateController.add(u);
        }
        return result;
      } catch (e) {
        _db.execute('ROLLBACK');
        _txUpdateStack.removeLast(); // discard all uncommitted updates
        rethrow;
      } finally {
        _transactionDepth--;
      }
    }
  }

  static var _spCount = 0;
  String _savepointId() => 'sp_${(++_spCount).toRadixString(36)}';

  /// Executes raw SQL with positional [bindings].
  @override
  Future<dynamic> rawQuery(String sql, List<dynamic> bindings) =>
      _execute(sql, bindings);

  @override
  Future<List<Map<String, dynamic>>> query(
    dynamic connection,
    String sql,
    List<dynamic> bindings,
  ) => _execute(sql, bindings);

  @override
  Stream<Map<String, dynamic>> streamQuery(
    dynamic connection,
    String sql,
    List<dynamic> bindings,
  ) {
    final stmt = _db.prepare(sql);
    final cursor = stmt.selectCursor(bindings.cast<Object?>());

    Iterable<Map<String, dynamic>> rows() sync* {
      try {
        while (cursor.moveNext()) {
          final row = cursor.current;
          yield Map<String, dynamic>.fromIterables(
            row.keys,
            row.values.cast<dynamic>(),
          );
        }
      } finally {
        stmt.dispose();
      }
    }

    return Stream.fromIterable(rows());
  }

  @override
  String wrapIdentifierImpl(String identifier) {
    if (identifier == '*') return identifier;
    return '"$identifier"';
  }

  @override
  String parameterPlaceholder(int index) {
    return '?';
  }

  @override
  String formatValue(dynamic value) {
    if (value == null) return 'NULL';
    if (value is bool) return value ? '1' : '0';
    if (value is num) return value.toString();
    if (value is String) return "'${value.replaceAll("'", "''")}'";
    return value.toString();
  }

  Future<List<Map<String, dynamic>>> _execute(
    String sql, [
    List<dynamic>? bindings,
  ]) {
    try {
      if (_isClosed) throw StateError('SQLiteClient is closed');
      final params = bindings ?? [];
      final stmt = _stmtCache.putIfAbsent(sql, () => _db.prepare(sql));
      final upperSql = sql.trimLeft().toUpperCase();
      if (upperSql.startsWith('SELECT') ||
          upperSql.startsWith('PRAGMA') ||
          upperSql.contains('RETURNING')) {
        final result = stmt.select(params);
        return Future.value(_mapResults(result));
      } else {
        stmt.execute(params);
        return Future.value([]);
      }
    } catch (e, st) {
      return Future.error(e, st);
    }
  }

  List<Map<String, dynamic>> _mapResults(ResultSet results) {
    final rows = <Map<String, dynamic>>[];
    final columns = results.columnNames;
    for (final row in results.rows) {
      final mapped = <String, dynamic>{};
      for (var i = 0; i < columns.length; i++) {
        mapped[columns[i]] = row[i];
      }
      rows.add(mapped);
    }
    return rows;
  }

  /// Execute a SELECT query via QueryBuilder.
  Future<List<Map<String, dynamic>>> select(QueryBuilder queryBuilder) {
    final compiled = queryBuilder.toSQL();
    return executeCompiled(compiled);
  }

  /// Execute a precompiled query without calling QueryBuilder.toSQL() again.
  Future<List<Map<String, dynamic>>> executeCompiled(SqlString compiled) =>
      query(null, compiled.sql, compiled.bindings);

  /// Execute any QueryBuilder query (SELECT, INSERT, UPDATE, DELETE).
  Future<List<Map<String, dynamic>>> execute(QueryBuilder queryBuilder) =>
      select(queryBuilder);

  /// Execute an INSERT query.
  Future<List<Map<String, dynamic>>> insert(QueryBuilder queryBuilder) =>
      select(queryBuilder);

  /// Execute an UPDATE query.
  Future<List<Map<String, dynamic>>> update(QueryBuilder queryBuilder) =>
      select(queryBuilder);

  /// Execute a DELETE query.
  Future<List<Map<String, dynamic>>> delete(QueryBuilder queryBuilder) =>
      select(queryBuilder);

  /// Creates a raw SQL fragment with optional [bindings].
  ///
  /// This is useful for embedding SQL snippets into QueryBuilder chains.
  @override
  Raw raw(String sql, [dynamic bindings]) => super.raw(sql, bindings);
}
