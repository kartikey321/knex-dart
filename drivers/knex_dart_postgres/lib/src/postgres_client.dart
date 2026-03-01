import 'package:postgres/postgres.dart';
import 'package:knex_dart/src/query/query_builder.dart';

/// PostgreSQL database client.
///
/// Connects to PostgreSQL databases and executes queries compiled by QueryBuilder.
/// This is a simplified implementation for Phase 1, focusing on SELECT queries.
class PostgresClient {
  final Connection _connection;
  bool _isClosed = false;

  PostgresClient._(this._connection);

  /// Creates a new PostgreSQL client and connects to the database.
  static Future<PostgresClient> connect({
    required String host,
    int port = 5432,
    required String database,
    required String username,
    String? password,
    bool useSSL = false,
  }) async {
    final endpoint = Endpoint(
      host: host,
      port: port,
      database: database,
      username: username,
      password: password,
    );

    final connection = await Connection.open(
      endpoint,
      settings: ConnectionSettings(
        sslMode: useSSL ? SslMode.require : SslMode.disable,
      ),
    );

    return PostgresClient._(connection);
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
      throw StateError('Cannot execute query on closed connection');
    }

    final compiled = query.toSQL();

    // Debug: Print SQL and bindings
    print('SQL: ${compiled.sql}');
    print('Bindings: ${compiled.bindings}');

    final result = await _connection.execute(
      compiled.sql,
      parameters: compiled.bindings,
    );

    return _mapResults(result);
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

  /// Closes the database connection.
  Future<void> close() async {
    if (!_isClosed) {
      await _connection.close();
      _isClosed = true;
    }
  }

  /// Execute a raw SQL query directly and return results as a List of Maps.
  Future<List<Map<String, dynamic>>> rawSql(
    String sql, [
    List<dynamic>? bindings,
  ]) async {
    if (_isClosed) {
      throw StateError('Cannot execute query on closed connection');
    }
    print('SQL: $sql');
    print('Bindings: $bindings');
    final result = await _connection.execute(sql, parameters: bindings ?? []);
    return _mapResults(result);
  }

  /// Database dialect name.
  String get dialect => 'postgres';

  /// Whether the connection is closed.
  bool get isClosed => _isClosed;

  // ─── Transaction support ──────────────────────────────────────────────────

  /// Run [callback] inside a Postgres transaction.
  ///
  /// The callback receives a [PostgresTrxClient] backed by the active
  /// transaction session. All queries must go through that client so they
  /// are executed inside the transaction.
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
    if (_isClosed) throw StateError('Connection is closed');
    return _connection.runTx((session) async {
      return callback(PostgresTrxClient._(session));
    });
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

  Future<List<Map<String, dynamic>>> select(QueryBuilder query) => _run(query);
  Future<List<Map<String, dynamic>>> execute(QueryBuilder query) => _run(query);
  Future<List<Map<String, dynamic>>> insert(QueryBuilder query) => _run(query);
  Future<List<Map<String, dynamic>>> update(QueryBuilder query) => _run(query);
  Future<List<Map<String, dynamic>>> delete(QueryBuilder query) => _run(query);

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
}
