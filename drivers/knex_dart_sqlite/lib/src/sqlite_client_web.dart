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
  /// Per-instance, not static — see the native client's equivalent field for
  /// the cross-client transaction interference a shared key caused. The value
  /// is a [_TxScope], so nested transactions can chain on their parent.
  final Object _transactionZoneKey = Object();

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
        storageMode: _defaultStorageModeFor(s),
      ),
      Map m when m['filename'] is String => (
        filename: m['filename'] as String,
        wasmUri: _parseWasmUri(m['wasmUri']),
        storageMode: _parseStorageMode(
          m['storageMode'],
          m['filename'] as String,
        ),
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

  /// The storage mode to use when the caller named none.
  ///
  /// A filename other than `:memory:` is a request for a database that
  /// outlives the page, so defaulting it to [SQLiteWebStorageMode.memory]
  /// handed back one that discarded everything — the same silent
  /// non-persistence as the OPFS bug fixed in 0.4.2, reached by omission
  /// rather than by a broken path.
  ///
  /// The default is [SQLiteWebStorageMode.indexedDb] rather than
  /// [SQLiteWebStorageMode.auto], even though `auto` would prefer the faster
  /// OPFS backend. `auto` falls back on *any* OPFS failure, and OPFS holds
  /// exclusive `FileSystemSyncAccessHandle`s: a second connection to the same
  /// name while the first still holds them does not fail, it quietly lands on
  /// IndexedDB instead. Two connections then read and write two different
  /// stores, each believing it has the database — no error, and writes from
  /// one invisible to the other and to later OPFS reopens. That is the same
  /// silent-divergence failure this release exists to remove, so it is not
  /// something to put on the default path.
  ///
  /// IndexedDB persists, works both on a page and in a worker (OPFS needs a
  /// dedicated worker), and has no exclusive-handle contention, so one name
  /// always resolves to one store. `auto` and `opfs` remain available
  /// explicitly for callers who want OPFS and can guarantee a single
  /// connection; the explicit `opfs` mode never falls back, so contention
  /// surfaces as an error there rather than as a second store.
  ///
  /// `:memory:` keeps meaning in-memory, matching the native driver.
  static SQLiteWebStorageMode _defaultStorageModeFor(String filename) =>
      filename == ':memory:'
      ? SQLiteWebStorageMode.memory
      : SQLiteWebStorageMode.indexedDb;

  static SQLiteWebStorageMode _parseStorageMode(
    Object? value,
    String filename,
  ) {
    if (value == null) return _defaultStorageModeFor(filename);
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
    final mode = _parseStorageMode(webStorageMode, filename);
    final config = KnexConfig(
      client: 'sqlite3',
      connection: {'filename': filename, 'storageMode': mode.name},
    );
    final client = SQLiteClient._(filename, _defaultWasmUri, mode, config);
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

    // If registration or open() throws, this Future rejects and connect()
    // never returns a client — so no caller can ever reach close() to
    // release fileSystem. Release it here instead, on the way out.
    CommonDatabase? opened;
    try {
      sqlite.registerVirtualFileSystem(fileSystem, makeDefault: true);
      opened = sqlite.open(_databasePathFor(fileSystem));
      if (_isClosed) {
        opened.close();
        await _closeFileSystem();
        return;
      }
      _db = opened;
      _setupUpdateHook(opened);
    } catch (_) {
      opened?.close();
      await _closeFileSystem();
      rethrow;
    }
  }

  /// The sqlite3 path to open on [fs].
  ///
  /// [SimpleOpfsFileSystem] persists exactly two paths, `/database` and
  /// `/database-journal`, and its `xOpen` falls through to an
  /// [InMemoryFileSystem] for anything else — silently, so writes to any other
  /// path succeed and then vanish when the client closes. Opening [_filename]
  /// there meant a named OPFS database never persisted at all.
  ///
  /// Databases stay separated by the OPFS *directory*, which
  /// `loadFromStorage(_filename)` already keys by name, so each name still
  /// gets its own store; only the path inside that directory is fixed.
  ///
  /// Keyed off the filesystem actually created rather than [_storageMode] so
  /// that `auto` mode is covered whenever it selects OPFS. The other two
  /// backends address files by name and are left alone.
  String _databasePathFor(VirtualFileSystem fs) =>
      fs is SimpleOpfsFileSystem ? '/database' : _filename;

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

  /// Whether [error] is OPFS refusing the lock because another connection
  /// already holds it, rather than OPFS being unusable in this context.
  ///
  /// The distinction is what makes [_createAutoFileSystem] safe. OPFS sync
  /// access handles are exclusive, so falling back on contention does not
  /// degrade gracefully — it puts this connection on a *different store* than
  /// the one that already has the database. Both then read and write happily,
  /// each invisible to the other and to any later OPFS reopen, with nothing
  /// raised anywhere.
  ///
  /// Matched on the error text because the thrown value arrives as an opaque
  /// `JSObject`; there is no Dart type to catch. The wording was observed in
  /// Chrome rather than assumed (see the `opfsContentionProbe` worker action):
  ///
  ///     NoModificationAllowedError: Failed to execute
  ///     'createSyncAccessHandle' on 'FileSystemFileHandle': Access Handles
  ///     cannot be created if there is another open Access Handle or Writable
  ///     stream associated with the same file.
  ///
  /// `NoModificationAllowedError` is the error the File System standard
  /// requires when a lock cannot be taken, so it should hold wherever OPFS
  /// works at all. It is still a string match against one browser's rendering
  /// of a DOM error name: a browser that reports contention some other way
  /// would fall through to the fallback below and could still diverge. This
  /// narrows the window rather than closing it everywhere.
  static bool _isOpfsLockContention(Object error) =>
      error.toString().contains('NoModificationAllowedError');

  Future<VirtualFileSystem> _createAutoFileSystem() async {
    try {
      return await SimpleOpfsFileSystem.loadFromStorage(_filename);
    } on Object catch (error) {
      // Not every OPFS failure means "OPFS is unavailable here". A second
      // connection to the same database hits an exclusive-handle conflict, and
      // falling back then is what silently splits the data — see
      // [_isOpfsLockContention]. Surface it instead.
      if (_isOpfsLockContention(error)) rethrow;

      // Genuinely unusable here — most often because this is a page's main
      // thread and `createSyncAccessHandle` is dedicated-worker only.
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
    // Re-check: close() may have run while the await above was pending and
    // won the race against a still-in-flight _initializeImpl() (which then
    // takes its early-return branch and leaves _db null without throwing) —
    // that's "closed concurrently", not "failed to initialize", and deserves
    // the accurate error rather than the misleading wasm-loading message
    // below.
    if (_isClosed) throw StateError('SQLiteClient is closed');
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
    } catch (_) {
      // initialize() may have failed (e.g. VFS registration or sqlite.open()
      // threw) — that failure already propagated once to whoever originally
      // awaited initialize()/connect(); close() is cleanup, not a second
      // place to report it, and must still release whatever
      // _initializeImpl() managed to create (_fileSystem) before it failed
      // — which the finally block below does regardless of this catch.
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

  /// Always `0`: this client prepares a statement per call and keeps no
  /// cache, so there is nothing to bound. Present so the public surface
  /// matches the native client, which is exported under the same name.
  int get cachedStatementCount => 0;

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
  // ignore: deprecated_member_use
  Future<Transaction> transaction([TransactionConfig? config]) async {
    throw UnimplementedError('Use beginTransaction() for SQLite transactions');
  }

  /// Implements [Client.runInTransaction] by delegating to [trx].
  @override
  Future<T> runInTransaction<T>(Future<T> Function() action) {
    return trx((_) => action());
  }

  /// Executes [callback] in a transaction/savepoint scope.
  Future<T> trx<T>(Future<T> Function(SQLiteClient trx) callback) {
    final parent = Zone.current[_transactionZoneKey] as _TxScope?;

    // Nested: queue behind this scope's previous child. Without this, two
    // nested transactions started concurrently under one parent interleave
    // their SAVEPOINT/RELEASE pairs, and because SQLite savepoints form a
    // stack, releasing the outer one discards the inner — surfacing as
    // "no such savepoint".
    if (parent != null) {
      final previousSibling = parent.lastChild;
      final base = previousSibling.then((_) => _runInNewScope(callback));

      // Internal chain: the signal for when the next sibling may start, with
      // errors swallowed so one failed sibling does not block every later one.
      parent.lastChild = base.then((_) {}, onError: (_) {});

      // External chain, deliberately a *separate* future rather than `base`.
      // The line above attaches an error handler to `base`, which marks its
      // error handled — so returning `base` itself made an unawaited failing
      // nested transaction fail silently instead of reporting an unhandled
      // async error. Handing the caller its own derived future restores that:
      // ignore it and Dart still complains. knex.js splits the two chains for
      // exactly this reason (`_promise` vs `_lastChild`,
      // lib/execution/transaction.js:82-92).
      return base.then((value) => value);
    }

    // Top level: queue behind other top-level transactions on this client,
    // which shares a single connection.
    final completer = Completer<T>();
    _transactionQueue = _transactionQueue.catchError((_) {}).then((_) async {
      try {
        completer.complete(await _runInNewScope(callback));
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  /// Runs [callback] in a fresh [_TxScope].
  ///
  /// Each nesting level gets its own scope so that a transaction's children
  /// chain against each other, not against its siblings — the parentage that
  /// keeps the chain from waiting on itself.
  Future<T> _runInNewScope<T>(
    Future<T> Function(SQLiteClient trx) callback,
  ) {
    return runZoned(
      () => _runTransactionScope(callback),
      zoneValues: {_transactionZoneKey: _TxScope()},
    );
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
        try {
          db.execute('ROLLBACK');
        } catch (_) {
          // See sqlite_client.dart's equivalent guard (native client): a
          // failing ROLLBACK here (already-ended transaction, concurrent
          // close) must not skip the update-hook stack cleanup below or mask
          // the original error with the rollback's own — mirrors the
          // SAVEPOINT branch above, which already guards its ROLLBACK TO
          // SAVEPOINT the same way.
        }
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

  var _spCount = 0;
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

    // See the native client's _execute for why this neither inspects the SQL
    // text nor uses the execute() branch, and why a trailing statement is an
    // error rather than a silent drop.
    final stmt = db.prepare(sql, checkNoTail: true);
    try {
      return _mapResults(stmt.select(params));
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

/// One transaction scope's chain of child transactions.
///
/// Mirrors knex.js's `Transaction._lastChild` (lib/execution/transaction.js): a
/// nested transaction awaits its parent's [lastChild] before starting and then
/// becomes the new tail, so siblings under one parent run strictly in sequence
/// rather than interleaving.
///
/// Held per scope rather than per client so that independent transaction trees
/// do not block each other, and so a transaction started inside another's body
/// chains against *that* transaction's children — whose chain is fresh — rather
/// than waiting on the sibling chain it is itself part of.
class _TxScope {
  Future<void> lastChild = Future<void>.value();
}
