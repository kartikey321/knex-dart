import 'package:knex_dart/knex_dart.dart';
import 'package:mssql/mssql.dart' as tds;

/// SQL Server database client via the pure-Dart `mssql` package (TDS 7.4/8.0).
///
/// **No native dependencies**: unlike the previous FreeTDS/FFI-based driver,
/// this talks TDS directly over a plain [Socket]/[SecureSocket] — no system
/// library to install, no shared native singleton, no blocking FFI calls that
/// could freeze the isolate.
///
/// **One connection per instance**: this client owns a single
/// [tds.MssqlConnection] and serializes calls through it, matching the
/// previous driver's semantics. For concurrent workloads, create multiple
/// [MssqlClient] instances (or see [tds.MssqlPool] for a pooled alternative
/// upstream — not yet wired into this driver).
///
/// **SQL dialect**: SQL Server uses square-bracket identifiers (`[col]`),
/// `@name`-style named parameters, and `TOP n` instead of `LIMIT n`. The
/// knex_dart query builder emits bracketed identifiers and `?` positional
/// placeholders for this driver; [_rewriteParams] converts those to the
/// `@pN` named-parameter form the underlying driver expects.
class MssqlClient {
  final tds.MssqlConnection _conn;
  bool _isClosed = false;

  MssqlClient._(this._conn);

  /// Connect to a SQL Server instance.
  ///
  /// [host] is the server hostname or IP address.
  /// [port] defaults to `1433`.
  /// [database] is the initial catalog to connect to.
  ///
  /// [encrypt] and [trustServerCertificate] control TLS. The underlying
  /// `mssql` package defaults to `encrypt: true, trustServerCertificate:
  /// false` — mandatory TLS with real certificate validation, which the
  /// previous FFI driver (`mssql_connection`) did not enforce by default.
  /// [trustServerCertificate] defaults to `true` here to match that prior
  /// behavior and because most local/on-prem/CI SQL Server instances (the
  /// ones this docker-compose setup and CI both use) present a self-signed
  /// certificate. Set it to `false` for a server with a certificate from a
  /// trusted CA.
  static Future<MssqlClient> connect({
    required String host,
    String port = '1433',
    required String database,
    required String username,
    required String password,
    int timeoutSeconds = 15,
    bool encrypt = true,
    bool trustServerCertificate = true,
  }) async {
    final conn = await tds.MssqlConnection.connect(
      host: host,
      port: int.parse(port),
      database: database,
      user: username,
      password: password,
      encrypt: encrypt,
      trustServerCertificate: trustServerCertificate,
      timeout: Duration(seconds: timeoutSeconds),
    );
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
  /// sending to SQL Server. (This differs from [_run]'s compiled path,
  /// where the query compiler already emits `@p0`/`@p1`/… directly — see
  /// [_executeCompiled].)
  Future<List<Map<String, dynamic>>> raw(
    String sql, [
    List<dynamic>? bindings,
  ]) => _executeRaw(sql, bindings ?? []);

  Future<List<Map<String, dynamic>>> _run(QueryBuilder q) {
    if (_isClosed) throw StateError('MssqlClient is closed');
    final compiled = q.toSQL();
    return _executeCompiled(compiled.sql, compiled.bindings);
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
      await _conn.commitTransaction();
      return result;
    } catch (e) {
      try {
        await _conn.rollbackTransaction();
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    await _conn.close();
  }

  // ─── Internal execution ───────────────────────────────────────────────────

  /// Executes SQL compiled by the query builder, which already contains
  /// `@p0`/`@p1`/… placeholders (see `Client.parameterPlaceholder` for
  /// [KnexDialect.mssql]) — [bindings] map onto them positionally, no
  /// rewriting needed.
  Future<List<Map<String, dynamic>>> _executeCompiled(
    String sql,
    List<dynamic> bindings,
  ) {
    if (_isClosed) throw StateError('MssqlClient is closed');
    final params = <String, Object?>{
      for (var i = 0; i < bindings.length; i++) 'p$i': bindings[i],
    };
    return _runQuery(sql, params);
  }

  /// Executes user-supplied raw SQL using knex.js's universal `?` binding
  /// convention — rewritten to `@p1`/`@p2`/… before sending to SQL Server.
  Future<List<Map<String, dynamic>>> _executeRaw(
    String sql,
    List<dynamic> bindings,
  ) {
    if (_isClosed) throw StateError('MssqlClient is closed');

    // With no bindings, send the SQL unchanged. Rewriting unconditionally
    // would treat a literal `?` in the SQL text itself (e.g. inside a
    // string literal) as a placeholder and crash with a RangeError trying
    // to read a binding that doesn't exist.
    final (rewritten, params) = bindings.isEmpty
        ? (sql, const <String, Object?>{})
        : _rewriteParams(sql, bindings);
    return _runQuery(rewritten, params);
  }

  Future<List<Map<String, dynamic>>> _runQuery(
    String sql,
    Map<String, Object?> params,
  ) async {
    final result = await _conn.query(sql, params);
    return [
      for (final row in result.rows)
        {
          for (var i = 0; i < row.columnNames.length; i++)
            row.columnNames[i]: row.valueAt(i),
        },
    ];
  }

  (String sql, Map<String, Object?> params) _rewriteParams(
    String sql,
    List<dynamic> bindings,
  ) {
    final params = <String, Object?>{};
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
  ]) => _client._executeRaw(sql, bindings ?? []);

  Future<List<Map<String, dynamic>>> _run(QueryBuilder q) {
    final compiled = q.toSQL();
    return _client._executeCompiled(compiled.sql, compiled.bindings);
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
