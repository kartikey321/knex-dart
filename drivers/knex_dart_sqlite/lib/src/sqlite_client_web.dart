import 'dart:async';

import 'package:knex_dart/knex_dart.dart';
import 'package:sqlite3/wasm.dart';

import 'sqlite_storage_mode.dart';

enum SQLiteWebStorageMode { memory, indexedDb, opfs, auto }

/// SQLite database client for web/WASM.
class SQLiteClient extends Client {
  CommonDatabase? _db;
  final String _filename;
  final Uri _wasmUri;
  final SQLiteWebStorageMode _storageMode;
  bool _isClosed = false;

  /// The virtual file system created for this client during
  /// [_initializeImpl], kept so it can be released in [destroyPool].
  ///
  /// [SimpleOpfsFileSystem] holds open `FileSystemSyncAccessHandle`s and
  /// [IndexedDbFileSystem] holds an open `IDBDatabase` connection; both must
  /// be explicitly closed or they outlive this client (browsers do not
  /// promptly release either just because the Dart object is unreferenced),
  /// which then blocks any later attempt to delete/replace the underlying
  /// storage (OPFS `removeEntry` / `indexedDB.deleteDatabase`).
  VirtualFileSystem? _fileSystem;

  /// Depth counter for nested transactions (0 = no active transaction).
  int _transactionDepth = 0;

  // SQLite uses a single connection here, so unrelated top-level
  // transactions must not interleave. We queue only the outermost scopes;
  // nested transactions within the same logical flow still use savepoints.
  Future<void> _transactionQueue = Future<void>.value();
  static final Object _transactionZoneKey = Object();

  Future<void>? _initialization;
  final List<List<SqliteUpdate>> _txUpdateStack = [];
  final StreamController<SqliteUpdate> _updateController =
      StreamController<SqliteUpdate>.broadcast(sync: true);
  StreamSubscription<SqliteUpdate>? _updatesSub;

  SQLiteClient._(
    this._filename,
    this._wasmUri,
    this._storageMode,
    KnexConfig config,
  ) : super(config);

  static final Uri _defaultWasmUri = Uri.parse(
    'packages/knex_dart_sqlite/web_assets/sqlite3.wasm',
  );
  static final Uri _legacyWasmUri = Uri.parse('sqlite3.wasm');

  /// Create a SQLite client directly from [KnexConfig].
  ///
  /// Initialization is deferred until first use because wasm loading is async.
  static SQLiteClient fromConfig(KnexConfig config) {
    final connection = config.connection;
    final parsed = switch (connection) {
      String s => (
        filename: s,
        wasmUri: _defaultWasmUri,
        storageMode: SQLiteWebStorageMode.memory,
      ),
      Map m when m['filename'] is String => (
        filename: m['filename'] as String,
        wasmUri: _parseWasmUri(m['wasmUri']),
        storageMode: _parseStorageMode(m['storageMode']),
      ),
      _ => throw ArgumentError(
        'SQLite config.connection must be a filename String '
        'or Map containing a String "filename".',
      ),
    };

    return SQLiteClient._(
      parsed.filename,
      parsed.wasmUri,
      parsed.storageMode,
      config,
    );
  }

  static Uri _parseWasmUri(Object? value) {
    if (value == null) return _defaultWasmUri;
    if (value is Uri) return value;
    if (value is String) return Uri.parse(value);
    throw ArgumentError(
      'SQLite config.connection["wasmUri"] must be a String or Uri.',
    );
  }

  static SQLiteWebStorageMode _parseStorageMode(Object? value) {
    if (value == null) return SQLiteWebStorageMode.memory;
    if (value is SQLiteWebStorageMode) return value;
    if (value is! String) {
      throw ArgumentError(
        'SQLite config.connection["storageMode"] must be a String.',
      );
    }
    validateSQLiteWebStorageMode(value);
    return switch (value) {
      'memory' => SQLiteWebStorageMode.memory,
      'indexedDb' => SQLiteWebStorageMode.indexedDb,
      'opfs' => SQLiteWebStorageMode.opfs,
      'auto' => SQLiteWebStorageMode.auto,
      _ => throw StateError('Unreachable storageMode "$value".'),
    };
  }

  /// Creates and opens a SQLite client for [filename].
  static Future<SQLiteClient> connect({
    required String filename,
    String? webStorageMode,
  }) async {
    final config = KnexConfig(
      client: 'sqlite3',
      connection: {
        'filename': filename,
        'storageMode': webStorageMode ?? SQLiteWebStorageMode.memory.name,
      },
    );
    final client = SQLiteClient._(
      filename,
      _defaultWasmUri,
      _parseStorageMode(webStorageMode),
      config,
    );
    await client.initialize();
    return client;
  }

  /// Opens the underlying SQLite database (WASM).
  Future<void> initialize() {
    return _initialization ??= _initializeImpl();
  }

  Future<void> _initializeImpl() async {
    final sqlite = await _loadSqlite3();
    final fileSystem = await _createFileSystem();
    // Store the reference immediately so it can be released even if a step
    // below (registration, open) throws, or if the client is closed before
    // initialization finishes.
    _fileSystem = fileSystem;
    sqlite.registerVirtualFileSystem(fileSystem, makeDefault: true);

    final opened = sqlite.open(_filename);
    if (_isClosed) {
      opened.close();
      await _closeFileSystem();
      return;
    }
    _db = opened;
    _setupUpdateHook(opened);
  }

  /// Releases the resources held by [_fileSystem], if any.
  ///
  /// [SimpleOpfsFileSystem] and [IndexedDbFileSystem] each hold a real,
  /// exclusive browser-level resource (OPFS sync access handles / an
  /// `IDBDatabase` connection) that is not released just because this Dart
  /// object becomes unreferenced — it must be closed explicitly, or it
  /// blocks later attempts to delete/replace the same storage.
  /// [InMemoryFileSystem] holds nothing external and needs no cleanup.
  ///
  /// This must never throw: it always runs from a `finally` block, and an
  /// exception here must not mask the original error or skip the rest of
  /// that cleanup.
  Future<void> _closeFileSystem() async {
    final fs = _fileSystem;
    _fileSystem = null;
    if (fs == null) return;
    try {
      if (fs is SimpleOpfsFileSystem) {
        fs.close();
      } else if (fs is IndexedDbFileSystem) {
        await fs.close();
      }
    } catch (_) {
      // Best-effort cleanup; swallow so callers' finally blocks still run.
    }
  }

  void _setupUpdateHook(CommonDatabase db) {
    _updatesSub = db.updates.listen((update) {
      if (_updateController.isClosed) return;
      if (_txUpdateStack.isNotEmpty) {
        _txUpdateStack.last.add(update);
      } else {
        _updateController.add(update);
      }
    });
  }

  Future<VirtualFileSystem> _createFileSystem() async {
    return switch (_storageMode) {
      SQLiteWebStorageMode.memory => InMemoryFileSystem(),
      SQLiteWebStorageMode.indexedDb => await IndexedDbFileSystem.open(
        dbName: _filename,
      ),
      SQLiteWebStorageMode.opfs => await SimpleOpfsFileSystem.loadFromStorage(
        _filename,
      ),
      SQLiteWebStorageMode.auto => await _createAutoFileSystem(),
    };
  }

  Future<VirtualFileSystem> _createAutoFileSystem() async {
    try {
      return await SimpleOpfsFileSystem.loadFromStorage(_filename);
    } on Object {
      try {
        return await IndexedDbFileSystem.open(dbName: _filename);
      } on Object {
        return InMemoryFileSystem();
      }
    }
  }

  Future<WasmSqlite3> _loadSqlite3() async {
    try {
      return await WasmSqlite3.loadFromUrl(_wasmUri);
    } on Object {
      if (_wasmUri != _defaultWasmUri) rethrow;
      return WasmSqlite3.loadFromUrl(_legacyWasmUri);
    }
  }

  Future<CommonDatabase> _ensureDb() async {
    if (_isClosed) throw StateError('SQLiteClient is closed');
    await initialize();
    final db = _db;
    if (db == null) {
      throw StateError(
        'SQLiteClient failed to initialize. Ensure sqlite3.wasm is served '
        'or set connection["wasmUri"].',
      );
    }
    return db;
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
    return _ensureDb();
  }

  @override
  Future<void> releaseConnection(dynamic connection) async {
    // No-op
  }

  Future<void> destroyPool() async {
    if (_isClosed) return;
    try {
      await initialize();
    } finally {
      await _updatesSub?.cancel();
      // Close the sqlite3 database (and thus each open file's `xClose()`)
      // before releasing the VFS-level resources below — OPFS/IndexedDB
      // handles must stay valid until sqlite3 is done flushing them.
      _db?.close();
      _db = null;
      _isClosed = true;
      await _closeFileSystem();
      if (!_updateController.isClosed) {
        await _updateController.close();
      }
    }
  }

  /// Whether the connection is closed.
  bool get isClosed => _isClosed;

  /// Stream of low-level table mutation events from SQLite's UPDATE_HOOK.
  ///
  /// Events are buffered while a transaction is active and flushed only on
  /// top-level COMMIT, so watch() behavior matches the native client.
  Stream<SqliteUpdate> get updates async* {
    await _ensureDb();
    yield* _updateController.stream;
  }

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

  /// Implements [Client.runInTransaction] by delegating to [trx].
  @override
  Future<T> runInTransaction<T>(Future<T> Function() action) {
    return trx((_) => action());
  }

  /// Executes [callback] in a transaction/savepoint scope.
  Future<T> trx<T>(Future<T> Function(SQLiteClient trx) callback) async {
    if (Zone.current[_transactionZoneKey] == true) {
      return _runTransactionScope(callback);
    }

    final completer = Completer<T>();
    _transactionQueue = _transactionQueue.catchError((_) {}).then((_) async {
      try {
        final result = await runZoned(
          () => _runTransactionScope(callback),
          zoneValues: {_transactionZoneKey: true},
        );
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<T> _runTransactionScope<T>(
    Future<T> Function(SQLiteClient trx) callback,
  ) async {
    final db = await _ensureDb();

    if (_transactionDepth > 0) {
      final sp = _savepointId();
      _transactionDepth++;
      _txUpdateStack.add([]);
      db.execute('SAVEPOINT $sp');
      try {
        final result = await callback(this);
        db.execute('RELEASE SAVEPOINT $sp');
        await _settleUpdateHookQueue();
        final saved = _txUpdateStack.removeLast();
        _txUpdateStack.last.addAll(saved);
        return result;
      } catch (e, st) {
        try {
          db.execute('ROLLBACK TO SAVEPOINT $sp');
        } catch (_) {}
        await _settleUpdateHookQueue();
        _txUpdateStack.removeLast();
        Error.throwWithStackTrace(e, st);
      } finally {
        _transactionDepth--;
      }
    } else {
      _transactionDepth++;
      _txUpdateStack.add([]);
      db.execute('BEGIN');
      try {
        final result = await callback(this);
        db.execute('COMMIT');
        await _settleUpdateHookQueue();
        final saved = _txUpdateStack.removeLast();
        for (final update in saved) {
          _updateController.add(update);
        }
        return result;
      } catch (e) {
        db.execute('ROLLBACK');
        await _settleUpdateHookQueue();
        _txUpdateStack.removeLast();
        rethrow;
      } finally {
        _transactionDepth--;
      }
    }
  }

  Future<void> _settleUpdateHookQueue() async {
    await Future<void>.microtask(() {});
  }

  static var _spCount = 0;
  String _savepointId() => 'sp_${(++_spCount).toRadixString(36)}';

  /// Executes raw SQL with positional [bindings].
  @override
  Future<dynamic> rawQuery(String sql, List<dynamic> bindings) async {
    return _execute(sql, bindings);
  }

  /// Executes an already compiled SQL query.
  Future<List<Map<String, dynamic>>> executeCompiled(SqlString compiled) =>
      _execute(compiled.sql, compiled.bindings);

  @override
  Future<List<Map<String, dynamic>>> query(
    dynamic connection,
    String sql,
    List<dynamic> bindings,
  ) async {
    return _execute(sql, bindings);
  }

  @override
  Stream<Map<String, dynamic>> streamQuery(
    dynamic connection,
    String sql,
    List<dynamic> bindings,
  ) async* {
    final db = await _ensureDb();
    final stmt = db.prepare(sql);
    try {
      final cursor = stmt.selectCursor(bindings.cast<Object?>());
      while (cursor.moveNext()) {
        final row = cursor.current;
        yield Map<String, dynamic>.from(row);
      }
    } finally {
      stmt.close();
    }
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
  ]) async {
    final db = await _ensureDb();
    final params = bindings ?? [];

    final stmt = db.prepare(sql);
    try {
      final upperSql = sql.trimLeft().toUpperCase();
      if (upperSql.startsWith('SELECT') ||
          upperSql.startsWith('PRAGMA') ||
          upperSql.contains('RETURNING')) {
        final result = stmt.select(params);
        return _mapResults(result);
      } else {
        stmt.execute(params);
        return [];
      }
    } finally {
      stmt.close();
    }
  }

  List<Map<String, dynamic>> _mapResults(ResultSet results) {
    final rows = <Map<String, dynamic>>[];
    for (final row in results) {
      rows.add(Map<String, dynamic>.from(row));
    }
    return rows;
  }

  /// Execute a SELECT query via QueryBuilder.
  Future<List<Map<String, dynamic>>> select(QueryBuilder queryBuilder) async {
    final compiled = queryBuilder.toSQL();
    return query(null, compiled.sql, compiled.bindings);
  }

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
