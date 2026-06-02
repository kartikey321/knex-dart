import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:knex_dart/knex_dart.dart';

/// Turso (libSQL) database client over the libSQL HTTP pipeline API.
///
/// Turso speaks a SQLite-compatible SQL dialect (double-quote identifiers,
/// `?` positional parameters). Transactions are implemented by sending
/// BEGIN / COMMIT / ROLLBACK as SQL statements; each statement is an
/// independent HTTP call to the `/v2/pipeline` endpoint.
///
/// **Transaction note**: HTTP-based transactions are not immune to
/// network-layer failures between statements. For strict ACID guarantees
/// in production, use Turso's native SDK which supports interactive
/// WebSocket sessions. The `trx()` API here is suitable for most
/// application-level workloads.
class TursoClient {
  final String _url;
  final String? _authToken;
  final http.Client _http;
  bool _isClosed = false;

  TursoClient({
    required String url,
    String? authToken,
    http.Client? httpClient,
  })  : _url = url.endsWith('/') ? url.substring(0, url.length - 1) : url,
        _authToken = authToken,
        _http = httpClient ?? http.Client();

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
    if (_isClosed) throw StateError('TursoClient is closed');
    final compiled = q.toSQL();
    return _execute(compiled.sql, compiled.bindings);
  }

  // ─── Transaction support ──────────────────────────────────────────────────

  /// Run [callback] inside a transaction.
  ///
  /// Sends `BEGIN` before the callback and `COMMIT` on success, or
  /// `ROLLBACK` on any error. Each statement is a separate HTTP call.
  Future<T> trx<T>(Future<T> Function(TursoTrxClient trx) callback) async {
    if (_isClosed) throw StateError('TursoClient is closed');
    final session = _TursoSession(this);
    try {
      await session.execute('BEGIN', []);
      final result = await callback(TursoTrxClient._(session));
      await session.execute('COMMIT', []);
      return result;
    } catch (e) {
      try {
        await session.execute('ROLLBACK', []);
      } catch (_) {}
      rethrow;
    } finally {
      await session.close();
    }
  }

  void close() {
    _isClosed = true;
    _http.close();
  }

  String get dialect => 'turso';

  // ─── HTTP transport ───────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _execute(
    String sql,
    List<dynamic> bindings,
  ) async {
    if (_isClosed) throw StateError('TursoClient is closed');
    final decoded = await _postPipeline({
      'requests': [
        {
          'type': 'execute',
          'stmt': {
            'sql': sql,
            if (bindings.isNotEmpty)
              'args': bindings.map(TursoClient._toLibSqlValue).toList(),
          },
        },
        {'type': 'close'},
      ],
    });
    final results = decoded['results'] as List<dynamic>;
    final first = results.first as Map<String, dynamic>;

    if (first['type'] == 'error') {
      final err = first['error'] as Map<String, dynamic>;
      throw StateError('Turso error: ${err['message']}');
    }

    final result = first['response'] as Map<String, dynamic>;
    final execResult = result['result'] as Map<String, dynamic>;

    return TursoClient._parseRows(execResult);
  }

  Future<Map<String, dynamic>> _postPipeline(Map<String, dynamic> body) async {
    if (_isClosed) throw StateError('TursoClient is closed');
    final uri = Uri.parse('$_url/v2/pipeline');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (_authToken != null) 'Authorization': 'Bearer $_authToken',
    };
    final response = await _http.post(
      uri,
      headers: headers,
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw StateError(
        'Turso HTTP ${response.statusCode}: ${response.body}',
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  // ─── libSQL value typing ──────────────────────────────────────────────────

  /// Convert a Dart value to a libSQL typed argument object.
  static Map<String, dynamic> _toLibSqlValue(dynamic value) {
    if (value == null) return {'type': 'null', 'value': null};
    if (value is int) return {'type': 'integer', 'value': value.toString()};
    if (value is double) return {'type': 'float', 'value': value};
    if (value is bool) {
      return {'type': 'integer', 'value': value ? '1' : '0'};
    }
    if (value is List<int>) {
      // BLOB — base64 encode
      return {'type': 'blob', 'base64': base64.encode(value)};
    }
    return {'type': 'text', 'value': value.toString()};
  }

  // ─── Response parsing ─────────────────────────────────────────────────────

  static List<Map<String, dynamic>> _parseRows(Map<String, dynamic> result) {
    final cols = (result['cols'] as List<dynamic>)
        .map((c) => (c as Map<String, dynamic>)['name'] as String)
        .toList();
    final rawRows = result['rows'] as List<dynamic>;

    return rawRows.map((row) {
      final cells = row as List<dynamic>;
      final map = <String, dynamic>{};
      for (var i = 0; i < cols.length; i++) {
        map[cols[i]] = _fromLibSqlValue(cells[i] as Map<String, dynamic>);
      }
      return map;
    }).toList();
  }

  /// Convert a libSQL typed value back to a Dart value.
  static dynamic _fromLibSqlValue(Map<String, dynamic> cell) {
    final type = cell['type'] as String;
    final value = cell['value'];
    switch (type) {
      case 'null':
        return null;
      case 'integer':
        if (value is num) return value.toInt();
        return int.parse(value as String);
      case 'float':
        if (value is num) return value.toDouble();
        return double.parse(value as String);
      case 'blob':
        return base64.decode(cell['base64'] as String);
      case 'text':
      default:
        return value as String?;
    }
  }
}

class _TursoSession {
  final TursoClient _client;
  String? baton;
  bool _isClosed = false;

  _TursoSession(this._client);

  Future<List<Map<String, dynamic>>> execute(
    String sql,
    List<dynamic> bindings,
  ) async {
    if (_isClosed) throw StateError('TursoSession is closed');
    final decoded = await _client._postPipeline({
      if (baton != null) 'baton': baton,
      'requests': [
        {
          'type': 'execute',
          'stmt': {
            'sql': sql,
            if (bindings.isNotEmpty)
              'args': bindings.map(TursoClient._toLibSqlValue).toList(),
          },
        },
      ],
    });
    baton = decoded['baton'] as String?;

    final results = decoded['results'] as List<dynamic>;
    final first = results.first as Map<String, dynamic>;
    if (first['type'] == 'error') {
      final err = first['error'] as Map<String, dynamic>;
      throw StateError('Turso error: ${err['message']}');
    }
    final result = first['response'] as Map<String, dynamic>;
    final execResult = result['result'] as Map<String, dynamic>;
    return TursoClient._parseRows(execResult);
  }

  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    final decoded = await _client._postPipeline({
      if (baton != null) 'baton': baton,
      'requests': [
        {'type': 'close'},
      ],
    });
    baton = decoded['baton'] as String?;
    final results = decoded['results'] as List<dynamic>;
    final first = results.first as Map<String, dynamic>;
    if (first['type'] == 'error') {
      final err = first['error'] as Map<String, dynamic>;
      throw StateError('Turso close error: ${err['message']}');
    }
  }
}

/// A transaction-scoped Turso client.
///
/// All methods delegate to the parent [TursoClient] which already has
/// an open transaction (BEGIN issued). Nested calls use SAVEPOINTs.
class TursoTrxClient {
  final _TursoSession _session;

  TursoTrxClient._(this._session);

  /// Callable shorthand for `queryBuilder().table(name)` within the Turso dialect.
  QueryBuilder call([String? tableName]) {
    final builder = KnexQuery.forClient('turso').queryBuilder();
    return tableName != null ? builder.table(tableName) : builder;
  }

  Future<List<Map<String, dynamic>>> select(QueryBuilder q) => _run(q);
  Future<List<Map<String, dynamic>>> execute(QueryBuilder q) => _run(q);
  Future<List<Map<String, dynamic>>> insert(QueryBuilder q) => _run(q);
  Future<List<Map<String, dynamic>>> update(QueryBuilder q) => _run(q);
  Future<List<Map<String, dynamic>>> delete(QueryBuilder q) => _run(q);

  Future<List<Map<String, dynamic>>> raw(
    String sql, [
    List<dynamic>? bindings,
  ]) => _session.execute(sql, bindings ?? []);

  Future<List<Map<String, dynamic>>> _run(QueryBuilder q) {
    final compiled = q.toSQL();
    return _session.execute(compiled.sql, compiled.bindings);
  }

  /// Run [callback] inside a savepoint on this already-open transaction.
  Future<T> trx<T>(Future<T> Function(TursoTrxClient trx) callback) async {
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

  static var _spCount = 0;
  String _savepointId() => 'sp_${(++_spCount).toRadixString(36)}';
}
