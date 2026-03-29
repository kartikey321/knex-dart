import 'package:knex_dart/knex_dart.dart';
import 'package:sqlite3/wasm.dart';

/// SQLite database client for web/WASM.
class SQLiteClient extends Client {
  CommonDatabase? _db;
  final String _filename;
  final Uri _wasmUri;
  bool _isClosed = false;

  /// Depth counter for nested transactions (0 = no active transaction).
  int _transactionDepth = 0;

  Future<void>? _initialization;

  SQLiteClient._(this._filename, this._wasmUri, KnexConfig config)
    : super(config);

  static final Uri _defaultWasmUri = Uri.parse(
    'packages/sqlite3/src/wasm/sqlite3.wasm',
  );
  static final Uri _legacyWasmUri = Uri.parse('sqlite3.wasm');

  /// Create a SQLite client directly from [KnexConfig].
  ///
  /// Initialization is deferred until first use because wasm loading is async.
  static SQLiteClient fromConfig(KnexConfig config) {
    final connection = config.connection;
    final parsed = switch (connection) {
      String s => (filename: s, wasmUri: _defaultWasmUri),
      Map m when m['filename'] is String => (
        filename: m['filename'] as String,
        wasmUri: _parseWasmUri(m['wasmUri']),
      ),
      _ => throw ArgumentError(
        'SQLite config.connection must be a filename String '
        'or Map containing a String "filename".',
      ),
    };

    return SQLiteClient._(parsed.filename, parsed.wasmUri, config);
  }

  static Uri _parseWasmUri(Object? value) {
    if (value == null) return _defaultWasmUri;
    if (value is Uri) return value;
    if (value is String) return Uri.parse(value);
    throw ArgumentError(
      'SQLite config.connection["wasmUri"] must be a String or Uri.',
    );
  }

  /// Creates and opens a SQLite client for [filename].
  static Future<SQLiteClient> connect({required String filename}) async {
    final config = KnexConfig(
      client: 'sqlite3',
      connection: {'filename': filename},
    );
    final client = SQLiteClient._(filename, _defaultWasmUri, config);
    await client.initialize();
    return client;
  }

  /// Opens the underlying SQLite database (WASM).
  Future<void> initialize() {
    return _initialization ??= _initializeImpl();
  }

  Future<void> _initializeImpl() async {
    final sqlite = await _loadSqlite3();
    sqlite.registerVirtualFileSystem(InMemoryFileSystem(), makeDefault: true);

    final opened = sqlite.open(_filename);
    if (_isClosed) {
      opened.dispose();
      return;
    }
    _db = opened;
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
      _db?.dispose();
      _db = null;
      _isClosed = true;
    }
  }

  /// Whether the connection is closed.
  bool get isClosed => _isClosed;

  /// Close the database connection.
  Future<void> close() => destroyPool();

  @override
  QueryBuilder queryBuilder() {
    return QueryBuilder(this);
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
    final db = await _ensureDb();

    if (_transactionDepth > 0) {
      final sp = _savepointId();
      _transactionDepth++;
      db.execute('SAVEPOINT $sp');
      try {
        final result = await callback(this);
        db.execute('RELEASE SAVEPOINT $sp');
        return result;
      } catch (e) {
        db.execute('ROLLBACK TO SAVEPOINT $sp');
        rethrow;
      } finally {
        _transactionDepth--;
      }
    } else {
      _transactionDepth++;
      db.execute('BEGIN');
      try {
        final result = await callback(this);
        db.execute('COMMIT');
        return result;
      } catch (e) {
        db.execute('ROLLBACK');
        rethrow;
      } finally {
        _transactionDepth--;
      }
    }
  }

  String _savepointId() =>
      'sp_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  /// Executes raw SQL with positional [bindings].
  @override
  Future<dynamic> rawQuery(String sql, List<dynamic> bindings) async {
    return _execute(sql, bindings);
  }

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
  ) {
    throw UnimplementedError('Stream query not supported for SQLite yet');
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
      stmt.dispose();
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
