import 'package:dart_duckdb/dart_duckdb.dart' as ddb;
import 'package:knex_dart/knex_dart.dart';

import 'platform/configure_stub.dart'
    if (dart.library.io) 'platform/configure_io.dart';

/// DuckDB database client via the dart_duckdb FFI package.
///
/// DuckDB is an in-process OLAP SQL database. It supports most standard SQL
/// including window functions, CTEs, FULL OUTER JOIN, LATERAL joins, and
/// INTERSECT/EXCEPT. DuckDB uses double-quoted identifiers and `$1` positional
/// parameters (PostgreSQL-compatible parameter syntax).
///
/// **Database modes**:
/// - `:memory:` — fully in-memory, no persistence (default)
/// - File path — persisted to disk
///
/// **System dependency**: Requires DuckDB to be installed as a shared library:
///   - macOS:  `brew install duckdb`
///   - Linux:  download from https://duckdb.org/docs/installation
///
/// **Thread safety**: [DuckDBClient] is NOT thread-safe. Create one instance
/// per isolate. For concurrent access, open multiple connections to the same
/// file-backed database.
class DuckDBClient {
  final ddb.Database _db;
  final ddb.Connection _conn;
  bool _isClosed = false;

  DuckDBClient._(this._db, this._conn);

  /// Open a DuckDB database.
  ///
  /// [path] defaults to `:memory:` for a fully in-memory database.
  ///
  /// On native platforms (macOS/Linux), automatically detects the
  /// system-installed DuckDB shared library from common locations
  /// (e.g. `/opt/homebrew/lib` on Apple Silicon). On web, DuckDB loads
  /// via WASM automatically with no setup required.
  static Future<DuckDBClient> open([String path = ':memory:']) async {
    _configure();
    final db = await ddb.duckdb.open(path);
    final conn = await ddb.duckdb.connect(db);
    return DuckDBClient._(db, conn);
  }

  static bool _configured = false;

  static void _configure() {
    if (_configured) return;
    _configured = true;
    configureNativeLibrary(); // platform/configure_io.dart or configure_stub.dart
  }

  // ─── Public query API ─────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> select(QueryBuilder q) => _run(q);
  Future<List<Map<String, dynamic>>> execute(QueryBuilder q) => _run(q);
  Future<List<Map<String, dynamic>>> insert(QueryBuilder q) => _run(q);
  Future<List<Map<String, dynamic>>> update(QueryBuilder q) => _run(q);
  Future<List<Map<String, dynamic>>> delete(QueryBuilder q) => _run(q);

  /// Execute a raw SQL string.
  Future<List<Map<String, dynamic>>> raw(
    String sql, [
    List<dynamic>? bindings,
  ]) => _execute(sql, bindings ?? []);

  Future<List<Map<String, dynamic>>> _run(QueryBuilder q) {
    if (_isClosed) throw StateError('DuckDBClient is closed');
    final compiled = q.toSQL();
    return _execute(compiled.sql, compiled.bindings);
  }

  // ─── Transaction support ──────────────────────────────────────────────────

  /// Run [callback] inside a DuckDB transaction.
  ///
  /// DuckDB supports full ACID transactions. Nested calls use SAVEPOINTs.
  Future<T> trx<T>(
    Future<T> Function(DuckDBTrxClient trx) callback,
  ) async {
    if (_isClosed) throw StateError('DuckDBClient is closed');
    await _conn.execute('BEGIN');
    try {
      final result = await callback(DuckDBTrxClient._(this));
      await _conn.execute('COMMIT');
      return result;
    } catch (e) {
      try {
        await _conn.execute('ROLLBACK');
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    await _conn.dispose();
    await _db.dispose();
  }

  // ─── Internal execution ───────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _execute(
    String sql,
    List<dynamic> bindings,
  ) async {
    if (_isClosed) throw StateError('DuckDBClient is closed');

    if (bindings.isEmpty) {
      final result = await _conn.query(sql);
      return _parseResult(result);
    }

    // dart_duckdb's web PreparedStatement only supports ≤10 parameters.
    // For larger binding lists, inline values as SQL literals.
    if (bindings.length > 10) {
      final result = await _conn.query(_inlineBindings(sql, bindings));
      return _parseResult(result);
    }

    final stmt = await _conn.prepare(sql);
    try {
      for (var i = 0; i < bindings.length; i++) {
        stmt.bind(bindings[i], i + 1); // 1-based indexing
      }
      final result = await stmt.execute();
      return _parseResult(result);
    } finally {
      await stmt.dispose();
    }
  }

  /// Stream query results row by row, memory-efficient for large result sets.
  Stream<Map<String, dynamic>> stream(QueryBuilder q) {
    final compiled = q.toSQL();
    return _streamExecute(compiled.sql, compiled.bindings);
  }

  Stream<Map<String, dynamic>> _streamExecute(
    String sql,
    List<dynamic> bindings,
  ) async* {
    if (_isClosed) throw StateError('DuckDBClient is closed');

    ddb.ResultSet result;
    ddb.PreparedStatement? stmt;

    if (bindings.isEmpty) {
      result = await _conn.query(sql);
    } else if (bindings.length > 10) {
      result = await _conn.query(_inlineBindings(sql, bindings));
    } else {
      stmt = await _conn.prepare(sql);
      for (var i = 0; i < bindings.length; i++) {
        stmt.bind(bindings[i], i + 1);
      }
      result = await stmt.execute();
    }

    try {
      final columnNames = result.columnNames;
      await for (final row in result.fetchAllStream()) {
        final map = <String, dynamic>{};
        for (var i = 0; i < columnNames.length; i++) {
          map[columnNames[i]] = row[i];
        }
        yield map;
      }
    } finally {
      await result.dispose();
      await stmt?.dispose();
    }
  }

  /// Substitute `$N` placeholders with literal SQL values.
  ///
  /// Used as a fallback when [bindings] exceeds dart_duckdb's web
  /// PreparedStatement limit of 10 parameters.
  static String _inlineBindings(String sql, List<dynamic> bindings) {
    var result = sql;
    // Replace from highest index to lowest so that `$1` doesn't match inside
    // `$10`, `$11`, etc. The `(?!\d)` negative lookahead ensures we only match
    // exact `$N` placeholders, not prefixes of larger numbers.
    for (var i = bindings.length; i >= 1; i--) {
      result = result.replaceAll(
        RegExp('\\\$$i(?!\\d)'),
        _formatLiteral(bindings[i - 1]),
      );
    }
    return result;
  }

  static String _formatLiteral(dynamic value) {
    if (value == null) return 'NULL';
    if (value is bool) return value ? 'TRUE' : 'FALSE';
    if (value is int) return '$value';
    if (value is double) return '$value';
    if (value is String) return "'${value.replaceAll("'", "''")}'";
    return "'${value.toString().replaceAll("'", "''")}'";
  }

  List<Map<String, dynamic>> _parseResult(ddb.ResultSet result) {
    final columnNames = result.columnNames;
    final rows = result.fetchAll(); // List<List<Object?>>

    return rows.map((row) {
      final map = <String, dynamic>{};
      for (var i = 0; i < columnNames.length; i++) {
        map[columnNames[i]] = row[i];
      }
      return map;
    }).toList();
  }
}

/// A transaction-scoped DuckDB client.
///
/// All methods delegate to the parent [DuckDBClient]. Nested calls use
/// SAVEPOINTs.
class DuckDBTrxClient {
  final DuckDBClient _client;

  DuckDBTrxClient._(this._client);

  Future<List<Map<String, dynamic>>> select(QueryBuilder q) => _run(q);
  Future<List<Map<String, dynamic>>> execute(QueryBuilder q) => _run(q);
  Future<List<Map<String, dynamic>>> insert(QueryBuilder q) => _run(q);
  Future<List<Map<String, dynamic>>> update(QueryBuilder q) => _run(q);
  Future<List<Map<String, dynamic>>> delete(QueryBuilder q) => _run(q);

  Future<List<Map<String, dynamic>>> raw(
    String sql, [
    List<dynamic>? bindings,
  ]) => _client._execute(sql, bindings ?? []);

  /// Stream query results row by row within this transaction.
  Stream<Map<String, dynamic>> stream(QueryBuilder q) {
    final compiled = q.toSQL();
    return _client._streamExecute(compiled.sql, compiled.bindings);
  }

  Future<List<Map<String, dynamic>>> _run(QueryBuilder q) {
    final compiled = q.toSQL();
    return _client._execute(compiled.sql, compiled.bindings);
  }

  /// Run [callback] inside a savepoint on this already-open transaction.
  Future<T> trx<T>(
    Future<T> Function(DuckDBTrxClient trx) callback,
  ) async {
    final sp = _savepointId();
    await raw('SAVEPOINT $sp');
    try {
      final result = await callback(this);
      await raw('RELEASE SAVEPOINT $sp');
      return result;
    } catch (e) {
      await raw('ROLLBACK TO SAVEPOINT $sp');
      rethrow;
    }
  }

  String _savepointId() =>
      'sp_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
}
