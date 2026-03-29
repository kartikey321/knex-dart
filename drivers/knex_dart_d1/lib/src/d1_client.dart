import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:knex_dart/knex_dart.dart';

/// Cloudflare D1 database client via the Cloudflare REST API.
///
/// D1 is Cloudflare's serverless SQLite database. Queries are sent to the
/// Cloudflare REST API at:
///   `https://api.cloudflare.com/client/v4/accounts/{accountId}/d1/database/{databaseId}/query`
///
/// D1 uses SQLite-compatible SQL: double-quote identifiers, `?` positional
/// parameters.
///
/// **Transaction note**: The D1 REST API executes each request as a single
/// auto-committed statement batch. True interactive transactions require the
/// Cloudflare Workers D1 binding API, not the REST API. The [trx] method
/// here simulates a transaction by sending statements in a single batch
/// request (which D1 executes atomically), but does NOT support mixing
/// arbitrary Dart logic between statements. For per-statement control, use
/// the Workers binding.
class D1Client {
  final String _accountId;
  final String _databaseId;
  final String _apiToken;
  final http.Client _http;
  bool _isClosed = false;

  static const String _baseUrl = 'https://api.cloudflare.com/client/v4';

  D1Client({
    required String accountId,
    required String databaseId,
    required String apiToken,
    http.Client? httpClient,
  })  : _accountId = accountId,
        _databaseId = databaseId,
        _apiToken = apiToken,
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
    if (_isClosed) throw StateError('D1Client is closed');
    final compiled = q.toSQL();
    return _execute(compiled.sql, compiled.bindings);
  }

  // ─── Batch / Transaction support ──────────────────────────────────────────

  /// Execute multiple SQL statements as an atomic batch.
  ///
  /// D1's REST API `/batch` endpoint runs all statements in a single
  /// transaction — either all succeed or all fail. This is the closest
  /// approximation to a transaction available over the REST API.
  ///
  /// The callback receives a [D1BatchBuilder] which collects statements.
  /// All statements are sent together in one HTTP request after the callback
  /// completes.
  Future<List<List<Map<String, dynamic>>>> batch(
    void Function(D1BatchBuilder batch) callback,
  ) async {
    if (_isClosed) throw StateError('D1Client is closed');
    final builder = D1BatchBuilder._();
    callback(builder);
    return _executeBatch(builder._statements);
  }

  /// Simulated transaction via batch API.
  ///
  /// Collects all operations from [callback] and sends them as an atomic
  /// D1 batch. The [D1TrxClient] records operations; they are sent together
  /// after the callback returns. **Dart code between statements is NOT
  /// executed transactionally** — only the SQL itself is atomic.
  Future<T> trx<T>(Future<T> Function(D1TrxClient trx) callback) async {
    if (_isClosed) throw StateError('D1Client is closed');
    final trxClient = D1TrxClient._();
    final result = await callback(trxClient);
    // Send all collected statements as a single atomic batch.
    if (trxClient._statements.isNotEmpty) {
      await _executeBatch(trxClient._statements);
    }
    return result;
  }

  void close() {
    _isClosed = true;
    _http.close();
  }

  // ─── HTTP transport ───────────────────────────────────────────────────────

  Uri get _queryUri => Uri.parse(
    '$_baseUrl/accounts/$_accountId/d1/database/$_databaseId/query',
  );

  Uri get _batchUri => Uri.parse(
    '$_baseUrl/accounts/$_accountId/d1/database/$_databaseId/batch',
  );

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $_apiToken',
  };

  Future<List<Map<String, dynamic>>> _execute(
    String sql,
    List<dynamic> bindings,
  ) async {
    if (_isClosed) throw StateError('D1Client is closed');

    final body = jsonEncode({
      'sql': sql,
      if (bindings.isNotEmpty) 'params': bindings.map(_toD1Param).toList(),
    });

    final response = await _http.post(_queryUri, headers: _headers, body: body);
    return _parseQueryResponse(response);
  }

  Future<List<List<Map<String, dynamic>>>> _executeBatch(
    List<_D1Statement> statements,
  ) async {
    final body = jsonEncode({
      'statements': statements.map((s) => {
        'sql': s.sql,
        if (s.params.isNotEmpty)
          'params': s.params.map(_toD1Param).toList(),
      }).toList(),
    });

    final response = await _http.post(_batchUri, headers: _headers, body: body);

    if (response.statusCode != 200) {
      throw StateError('D1 HTTP ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (decoded['success'] != true) {
      final errors = decoded['errors'] as List<dynamic>? ?? [];
      throw StateError('D1 batch error: $errors');
    }

    final results = decoded['result'] as List<dynamic>;
    return results.map((r) {
      final res = r as Map<String, dynamic>;
      if (res['success'] != true) {
        throw StateError('D1 statement error: ${res['error']}');
      }
      return _parseResultSet(res['results'] as List<dynamic>? ?? []);
    }).toList();
  }

  List<Map<String, dynamic>> _parseQueryResponse(http.Response response) {
    if (response.statusCode != 200) {
      throw StateError('D1 HTTP ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (decoded['success'] != true) {
      final errors = decoded['errors'] as List<dynamic>? ?? [];
      throw StateError('D1 error: $errors');
    }

    final results = decoded['result'] as List<dynamic>;
    if (results.isEmpty) return [];

    final first = results.first as Map<String, dynamic>;
    if (first['success'] != true) {
      throw StateError('D1 query error: ${first['error']}');
    }

    return _parseResultSet(first['results'] as List<dynamic>? ?? []);
  }

  List<Map<String, dynamic>> _parseResultSet(List<dynamic> rows) {
    return rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  /// D1 REST API accepts JSON-native types directly (no type wrappers needed).
  dynamic _toD1Param(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value ? 1 : 0;
    if (value is int || value is double || value is String) return value;
    return value.toString();
  }
}

/// Internal record of a single D1 batch statement.
class _D1Statement {
  final String sql;
  final List<dynamic> params;
  _D1Statement(this.sql, this.params);
}

/// Builder for D1 batch operations.
///
/// Collects statements; they are all sent in one atomic HTTP request.
class D1BatchBuilder {
  final List<_D1Statement> _statements = [];

  D1BatchBuilder._();

  void add(QueryBuilder q) {
    final compiled = q.toSQL();
    _statements.add(_D1Statement(compiled.sql, compiled.bindings));
  }

  void addRaw(String sql, [List<dynamic>? params]) {
    _statements.add(_D1Statement(sql, params ?? []));
  }
}

/// A transaction-scoped D1 client that collects statements for batch execution.
///
/// **Important**: statements are buffered and sent atomically after the
/// callback completes. Return values from individual operations within the
/// callback are empty lists — results are only available from the batch result.
class D1TrxClient {
  final List<_D1Statement> _statements = [];

  D1TrxClient._();

  Future<List<Map<String, dynamic>>> insert(QueryBuilder q) => _buffer(q);
  Future<List<Map<String, dynamic>>> update(QueryBuilder q) => _buffer(q);
  Future<List<Map<String, dynamic>>> delete(QueryBuilder q) => _buffer(q);
  Future<List<Map<String, dynamic>>> execute(QueryBuilder q) => _buffer(q);

  Future<List<Map<String, dynamic>>> raw(String sql, [List<dynamic>? params]) {
    _statements.add(_D1Statement(sql, params ?? []));
    return Future.value([]);
  }

  Future<List<Map<String, dynamic>>> _buffer(QueryBuilder q) {
    final compiled = q.toSQL();
    _statements.add(_D1Statement(compiled.sql, compiled.bindings));
    return Future.value([]);
  }
}
