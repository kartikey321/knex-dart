import 'package:mysql_client/mysql_client.dart';
import '../query/query_builder.dart';

/// MySQL database client (using mysql_client).
///
/// Connects to MySQL databases and executes queries compiled by QueryBuilder.
/// Uses the `mysql_client` package for modern MySQL 8.0 support.
class MySQLClient {
  final MySQLConnection _connection;
  bool _isClosed = false;

  MySQLClient._(this._connection);

  /// Creates a new MySQL client and connects to the database.
  static Future<MySQLClient> connect({
    required String host,
    int port = 3306,
    required String user,
    String? password,
    required String database,
    bool useSSL = false,
  }) async {
    // specific options for auth might be needed but defaults are usually good
    final connection = await MySQLConnection.createConnection(
      host: host,
      port: port,
      userName: user,
      password: password ?? '',
      databaseName: database,
      secure: useSSL,
    );

    await connection.connect();

    return MySQLClient._(connection);
  }

  final Map<String, PreparedStmt> _stmtCache = {};

  /// Executes a query (SELECT, INSERT, UPDATE, DELETE) and returns results.
  Future<List<Map<String, dynamic>>> query(QueryBuilder queryBuilder) async {
    if (_isClosed) {
      throw StateError('Cannot execute query on closed connection');
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
      throw StateError('Cannot execute query on closed connection');
    }

    return _execute(sql, bindings);
  }

  Future<List<Map<String, dynamic>>> _execute(
    String sql, [
    List<dynamic>? bindings,
  ]) async {
    // If no bindings, execution is simple and stateless
    if (bindings == null || bindings.isEmpty) {
      final IResultSet result = await _connection.execute(sql);
      return _mapResults(result);
    }

    // Check cache for existing statement
    PreparedStmt? stmt = _stmtCache[sql];

    if (stmt == null) {
      // Create and cache new statement
      stmt = await _connection.prepare(sql);
      _stmtCache[sql] = stmt;
    }

    // Execute cached statement
    final IResultSet result = await stmt.execute(bindings);
    return _mapResults(result);
  }

  /// Alias for query() to match PostgresClient API
  Future<List<Map<String, dynamic>>> select(QueryBuilder queryBuilder) =>
      query(queryBuilder);

  /// Execute any QueryBuilder query (SELECT, INSERT, UPDATE, DELETE)
  Future<List<Map<String, dynamic>>> execute(QueryBuilder queryBuilder) =>
      query(queryBuilder);

  /// Execute an INSERT query.
  /// Returns inserted rows if a RETURNING clause is present (MySQL 8.0+),
  /// otherwise an empty list.
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

  /// Closes the database connection.
  Future<void> close() async {
    if (!_isClosed) {
      // Deallocate all cached statements
      for (final stmt in _stmtCache.values) {
        await stmt.deallocate();
      }
      _stmtCache.clear();

      await _connection.close();
      _isClosed = true;
    }
  }

  /// Database dialect name.
  String get dialect => 'mysql';

  /// Whether the connection is closed.
  bool get isClosed => _isClosed;

  // ─── Transaction support ──────────────────────────────────────────────────

  /// Run [callback] inside a MySQL transaction.
  ///
  /// The callback receives a [MySQLTrxClient] that shares the same underlying
  /// connection and executes all queries within the active transaction.
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
    if (_isClosed) throw StateError('Connection is closed');
    await _connection.execute('START TRANSACTION');
    try {
      final result = await callback(MySQLTrxClient._(_connection));
      await _connection.execute('COMMIT');
      return result;
    } catch (e) {
      await _connection.execute('ROLLBACK');
      rethrow;
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
}
