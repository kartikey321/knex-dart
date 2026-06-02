import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:knex_dart/knex_dart.dart';

/// Snowflake database client via the Snowflake SQL API v2.
///
/// Snowflake uses a REST API for query execution. Queries are submitted to:
///   `https://{account}.snowflakecomputing.com/api/v2/statements`
///
/// Authentication is done via a Bearer token (OAuth token or JWT).
///
/// **SQL dialect**: Snowflake uses double-quoted identifiers (case-sensitive
/// when quoted). Parameters use `?` positional placeholders in the SQL API.
///
/// **Async execution**: The SQL API is asynchronous by default — Snowflake
/// may return a `statementHandle` that must be polled. This client uses
/// `async: false` to request synchronous execution (suitable for queries
/// that complete within the API gateway timeout of ~45 seconds).
///
/// For long-running queries, set [asyncExecution] to `true` on the client
/// and poll the result using [getAsyncResult].
class SnowflakeClient {
  final String _account;
  final String _token;
  final String? _database;
  final String? _schema;
  final String? _warehouse;
  final String? _role;
  final bool _asyncExecution;
  final http.Client _http;
  bool _isClosed = false;

  static const String _apiHost = 'snowflakecomputing.com';
  static const String _apiPath = '/api/v2/statements';

  SnowflakeClient({
    required String account,
    required String token,
    String? database,
    String? schema,
    String? warehouse,
    String? role,
    bool asyncExecution = false,
    http.Client? httpClient,
  })  : _account = account,
        _token = token,
        _database = database,
        _schema = schema,
        _warehouse = warehouse,
        _role = role,
        _asyncExecution = asyncExecution,
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
    if (_isClosed) throw StateError('SnowflakeClient is closed');
    final compiled = q.toSQL();
    return _execute(compiled.sql, compiled.bindings);
  }

  /// Poll for an async query result using its statement handle.
  ///
  /// Use this when [asyncExecution] is `true` and a query returns a handle
  /// instead of data.
  Future<List<Map<String, dynamic>>> getAsyncResult(
    String statementHandle,
  ) async {
    final uri = Uri.https(
      '$_account.$_apiHost',
      '$_apiPath/$statementHandle',
    );
    final response = await _http.get(uri, headers: _authHeaders);
    return _parseResponse(response);
  }

  void close() {
    _isClosed = true;
    _http.close();
  }

  // ─── HTTP transport ───────────────────────────────────────────────────────

  Uri get _statementsUri =>
      Uri.https('$_account.$_apiHost', _apiPath);

  Map<String, String> get _authHeaders => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'Authorization': 'Bearer $_token',
    'X-Snowflake-Authorization-Token-Type': 'OAUTH',
  };

  Future<List<Map<String, dynamic>>> _execute(
    String sql,
    List<dynamic> bindings,
  ) async {
    if (_isClosed) throw StateError('SnowflakeClient is closed');

    final body = <String, dynamic>{
      'statement': sql,
      'timeout': 60,
      'async': _asyncExecution,
      if (_database != null) 'database': _database,
      if (_schema != null) 'schema': _schema,
      if (_warehouse != null) 'warehouse': _warehouse,
      if (_role != null) 'role': _role,
      if (bindings.isNotEmpty)
        'bindings': _buildBindings(bindings),
    };

    final response = await _http.post(
      _statementsUri,
      headers: _authHeaders,
      body: jsonEncode(body),
    );

    return _parseResponse(response);
  }

  Map<String, Map<String, String>> _buildBindings(List<dynamic> bindings) {
    final result = <String, Map<String, String>>{};
    for (var i = 0; i < bindings.length; i++) {
      final key = '${i + 1}'; // 1-based
      result[key] = _toSnowflakeBinding(bindings[i]);
    }
    return result;
  }

  Map<String, String> _toSnowflakeBinding(dynamic value) {
    if (value == null) return {'type': 'TEXT', 'value': null};
    if (value is bool) return {'type': 'BOOLEAN', 'value': value.toString()};
    if (value is int) return {'type': 'FIXED', 'value': value.toString()};
    if (value is double) return {'type': 'REAL', 'value': value.toString()};
    return {'type': 'TEXT', 'value': value.toString()};
  }

  List<Map<String, dynamic>> _parseResponse(http.Response response) {
    if (response.statusCode == 202) {
      // Async query accepted — return empty (caller should poll)
      return [];
    }

    if (response.statusCode != 200) {
      throw StateError(
        'Snowflake HTTP ${response.statusCode}: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;

    // Check for query error
    final code = decoded['code'] as String?;
    if (code != null && code != '090001') {
      // 090001 = success
      final message = decoded['message'] as String? ?? 'Unknown error';
      throw StateError('Snowflake error [$code]: $message');
    }

    return _parseResultSet(decoded);
  }

  List<Map<String, dynamic>> _parseResultSet(Map<String, dynamic> decoded) {
    final resultSetMeta = decoded['resultSetMetaData'] as Map<String, dynamic>?;
    if (resultSetMeta == null) return [];

    final rowType = resultSetMeta['rowType'] as List<dynamic>? ?? [];
    final colNames = rowType
        .map((c) => (c as Map<String, dynamic>)['name'] as String)
        .toList();

    final data = decoded['data'] as List<dynamic>? ?? [];

    return data.map((row) {
      final cells = row as List<dynamic>;
      final map = <String, dynamic>{};
      for (var i = 0; i < colNames.length; i++) {
        map[colNames[i]] = cells[i]; // Snowflake returns strings for all types
      }
      return map;
    }).toList();
  }
}
