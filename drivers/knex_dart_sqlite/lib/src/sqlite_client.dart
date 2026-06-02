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
    for (final stmt in _stmtCache.values) {
      stmt.dispose();
    }
    _stmtCache.clear();
    _db.dispose();
    _isClosed = true;
  }

  /// Whether the connection is closed.
  bool get isClosed => _isClosed;

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
      _db.execute('SAVEPOINT $sp');
      try {
        final result = await callback(this);
        _db.execute('RELEASE SAVEPOINT $sp');
        return result;
      } catch (e) {
        _db.execute('ROLLBACK TO SAVEPOINT $sp');
        rethrow;
      } finally {
        _transactionDepth--;
      }
    } else {
      _transactionDepth++;
      _db.execute('BEGIN');
      try {
        final result = await callback(this);
        _db.execute('COMMIT');
        return result;
      } catch (e) {
        _db.execute('ROLLBACK');
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
  ]) async {
    final params = bindings ?? [];
    final stmt = _stmtCache.putIfAbsent(sql, () => _db.prepare(sql));
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
