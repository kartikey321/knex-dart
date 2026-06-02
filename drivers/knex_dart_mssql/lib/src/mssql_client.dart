import 'dart:async';
import 'dart:convert';

import 'package:knex_dart/knex_dart.dart';
import 'package:mssql_connection/mssql_connection.dart';

/// SQL Server database client via the mssql_connection FFI package (FreeTDS).
///
/// **System dependency**: Requires FreeTDS to be installed:
///   - macOS:  `brew install freetds`
///   - Ubuntu: `sudo apt-get install -y freetds-dev libct4`
///   - Windows: install FreeTDS from https://www.freetds.org
///
/// **Singleton**: The underlying [MssqlConnection] uses a single shared
/// connection. All calls are serialized through that connection. Use a
/// single [MssqlClient] instance per process; for concurrent workloads
/// queue operations or use multiple processes.
///
/// **SQL dialect**: SQL Server uses square-bracket identifiers (`[col]`),
/// `@p1`-style positional parameters, and `TOP n` instead of `LIMIT n`.
/// The knex_dart query builder emits bracketed identifiers for this driver.
class MssqlClient {
  final MssqlConnection _conn;
  bool _isClosed = false;

  MssqlClient._(this._conn);

  /// Connect to a SQL Server instance.
  ///
  /// [host] is the server hostname or IP address.
  /// [port] defaults to `1433`.
  /// [database] is the initial catalog to connect to.
  static Future<MssqlClient> connect({
    required String host,
    String port = '1433',
    required String database,
    required String username,
    required String password,
    int timeoutSeconds = 15,
  }) async {
    final conn = MssqlConnection.getInstance();
    final ok = await conn.connect(
      ip: host,
      port: port,
      databaseName: database,
      username: username,
      password: password,
      timeoutInSeconds: timeoutSeconds,
    );
    if (!ok) {
      throw StateError('Failed to connect to SQL Server at $host:$port');
    }
    return MssqlClient._(conn);
  }

  // ─── Public query API ─────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> select(QueryBuilder q) => _run(q);
  Future<List<Map<String, dynamic>>> execute(QueryBuilder q) => _run(q);
  Future<List<Map<String, dynamic>>> insert(QueryBuilder q) => _run(q);
  Future<List<Map<String, dynamic>>> update(QueryBuilder q) => _run(q);
  Future<List<Map<String, dynamic>>> delete(QueryBuilder q) => _run(q);

  /// Execute a raw SQL string with optional positional [bindings].
  ///
  /// Positional `?` placeholders are rewritten to `@p1`, `@p2`, … before
  /// sending to SQL Server.
  Future<List<Map<String, dynamic>>> raw(
    String sql, [
    List<dynamic>? bindings,
  ]) => _execute(sql, bindings ?? []);

  Future<List<Map<String, dynamic>>> _run(QueryBuilder q) {
    if (_isClosed) throw StateError('MssqlClient is closed');
    final compiled = q.toSQL();
    return _execute(compiled.sql, compiled.bindings);
  }

  // ─── Transaction support ──────────────────────────────────────────────────

  /// Run [callback] inside a SQL Server transaction.
  ///
  /// Commits on success; rolls back on any exception. Nested calls use
  /// SAVEPOINTs.
  Future<T> trx<T>(
    Future<T> Function(MssqlTrxClient trx) callback,
  ) async {
    if (_isClosed) throw StateError('MssqlClient is closed');
    await _conn.beginTransaction();
    try {
      final result = await callback(MssqlTrxClient._(this));
      await _conn.commit();
      return result;
    } catch (e) {
      try {
        await _conn.rollback();
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    await _conn.disconnect();
  }

  // ─── Internal execution ───────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _execute(
    String sql,
    List<dynamic> bindings,
  ) async {
    if (_isClosed) throw StateError('MssqlClient is closed');

    if (bindings.isEmpty) {
      final json = await _conn.getData(sql);
      return _parseJson(json);
    }

    final (rewritten, params) = _rewriteParams(sql, bindings);
    final json = await _conn.getDataWithParams(rewritten, params);
    return _parseJson(json);
  }

  (String sql, Map<String, dynamic> params) _rewriteParams(
    String sql,
    List<dynamic> bindings,
  ) {
    final params = <String, dynamic>{};
    var index = 0;
    var paramId = 0;
    final rewritten = sql.replaceAllMapped(RegExp(r'\?'), (_) {
      final value = bindings[index++];
      if (value == null) {
        return 'NULL';
      }
      paramId++;
      final key = 'p$paramId';
      params[key] = value;
      return '@$key';
    });
    return (rewritten, params);
  }

  List<Map<String, dynamic>> _parseJson(String json) {
    if (json.isEmpty) return [];
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final rows = decoded['rows'] as List<dynamic>? ?? [];
    return rows.cast<Map<String, dynamic>>();
  }
}

/// A transaction-scoped SQL Server client.
///
/// All operations run inside the already-open transaction on the parent
/// [MssqlClient]. Nested [trx] calls use SAVEPOINTs.
class MssqlTrxClient {
  final MssqlClient _client;

  MssqlTrxClient._(this._client);

  Future<List<Map<String, dynamic>>> select(QueryBuilder q) => _run(q);
  Future<List<Map<String, dynamic>>> execute(QueryBuilder q) => _run(q);
  Future<List<Map<String, dynamic>>> insert(QueryBuilder q) => _run(q);
  Future<List<Map<String, dynamic>>> update(QueryBuilder q) => _run(q);
  Future<List<Map<String, dynamic>>> delete(QueryBuilder q) => _run(q);

  Future<List<Map<String, dynamic>>> raw(
    String sql, [
    List<dynamic>? bindings,
  ]) => _client._execute(sql, bindings ?? []);

  Future<List<Map<String, dynamic>>> _run(QueryBuilder q) {
    final compiled = q.toSQL();
    return _client._execute(compiled.sql, compiled.bindings);
  }

  /// Run [callback] inside a savepoint on this already-open transaction.
  Future<T> trx<T>(
    Future<T> Function(MssqlTrxClient trx) callback,
  ) async {
    final sp = _savepointId();
    await raw('SAVE TRANSACTION $sp');
    try {
      final result = await callback(this);
      // SQL Server uses COMMIT TRANSACTION for outer only; savepoints
      // are released implicitly on outer COMMIT. No explicit release needed.
      return result;
    } catch (e, st) {
      try {
        await raw('ROLLBACK TRANSACTION $sp');
      } catch (_) {}
      Error.throwWithStackTrace(e, st);
    }
  }

  static var _spCount = 0;
  String _savepointId() => 'sp${(++_spCount).toRadixString(36)}';
}
