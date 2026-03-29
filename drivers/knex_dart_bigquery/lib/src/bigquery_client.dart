import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:knex_dart/knex_dart.dart';

/// Google BigQuery database client via the BigQuery REST API.
///
/// Queries are submitted to the BigQuery Jobs API:
///   `POST https://bigquery.googleapis.com/bigquery/v2/projects/{project}/jobs`
///
/// Authentication via a Google OAuth2 Bearer token. For service accounts,
/// use the `google_auth` package to obtain tokens automatically.
///
/// **SQL dialect**: BigQuery uses GoogleSQL (formerly Standard SQL):
/// - Backtick-quoted identifiers: `` `project.dataset.table` ``
/// - `@param_name` named parameters (this client uses positional `?` style
///   internally via indexed named params `@p1`, `@p2`, etc.)
/// - `INFORMATION_SCHEMA` for metadata
///
/// **Limitations of REST API**:
/// - No interactive transactions (DDL auto-commits; DML runs in implicit txn)
/// - Each query is a separate job; large results require pagination
/// - Multi-statement transactions require `beginTransaction` API (not yet
///   implemented here)
class BigQueryClient {
  final String _projectId;
  final String _token;
  final String? _defaultDataset;
  final String? _location;
  final http.Client _http;
  final String _apiBase;
  bool _isClosed = false;

  static const String _cloudApiBase =
      'https://bigquery.googleapis.com/bigquery/v2';

  BigQueryClient({
    required String projectId,
    required String token,
    String? defaultDataset,
    String? location,
    http.Client? httpClient,
    /// Point at a local BigQuery emulator, e.g. `http://localhost:9050`.
    /// When set, the `Authorization` header is still sent but typically
    /// ignored by the emulator.
    String? emulatorHost,
  })  : _projectId = projectId,
        _token = token,
        _defaultDataset = defaultDataset,
        _location = location,
        _http = httpClient ?? http.Client(),
        _apiBase = emulatorHost != null
            ? '${emulatorHost.trimRight()}/bigquery/v2'
            : _cloudApiBase;

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
    if (_isClosed) throw StateError('BigQueryClient is closed');
    final compiled = q.toSQL();
    return _execute(compiled.sql, compiled.bindings);
  }

  void close() {
    _isClosed = true;
    _http.close();
  }

  // ─── HTTP transport ───────────────────────────────────────────────────────

  Uri get _jobsUri =>
      Uri.parse('$_apiBase/projects/$_projectId/jobs');

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $_token',
  };

  Future<List<Map<String, dynamic>>> _execute(
    String sql,
    List<dynamic> bindings,
  ) async {
    if (_isClosed) throw StateError('BigQueryClient is closed');

    // Build query parameters — convert positional ? to @p1, @p2 ...
    final (resolvedSql, queryParams) = _buildQueryParams(sql, bindings);

    final jobConfig = <String, dynamic>{
      'configuration': {
        'query': {
          'query': resolvedSql,
          'useLegacySql': false,
          if (queryParams.isNotEmpty) 'queryParameters': queryParams,
          if (_defaultDataset != null)
            'defaultDataset': {
              'projectId': _projectId,
              'datasetId': _defaultDataset,
            },
        },
      },
      if (_location != null) 'jobReference': {'location': _location},
    };

    // Submit job
    final submitResponse = await _http.post(
      _jobsUri,
      headers: _headers,
      body: jsonEncode(jobConfig),
    );

    if (submitResponse.statusCode != 200) {
      throw StateError(
        'BigQuery HTTP ${submitResponse.statusCode}: ${submitResponse.body}',
      );
    }

    final job = jsonDecode(submitResponse.body) as Map<String, dynamic>;
    final jobRef = job['jobReference'] as Map<String, dynamic>;
    final jobId = jobRef['jobId'] as String;

    // Poll until done
    return _pollJobResults(jobId);
  }

  Future<List<Map<String, dynamic>>> _pollJobResults(String jobId) async {
    // Wait for completion
    while (true) {
      final statusUri = Uri.parse(
        '$_apiBase/projects/$_projectId/jobs/$jobId',
      );
      final response = await _http.get(statusUri, headers: _headers);

      if (response.statusCode != 200) {
        throw StateError(
          'BigQuery job status ${response.statusCode}: ${response.body}',
        );
      }

      final job = jsonDecode(response.body) as Map<String, dynamic>;
      final status = job['status'] as Map<String, dynamic>;
      final state = status['state'] as String;

      if (state == 'DONE') {
        final errorResult = status['errorResult'] as Map<String, dynamic>?;
        if (errorResult != null) {
          throw StateError(
            'BigQuery error: ${errorResult['message']}',
          );
        }
        break;
      }

      // Poll every 500ms
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // Fetch results
    final resultUri = Uri.parse(
      '$_apiBase/projects/$_projectId/queries/$jobId',
    );
    final response = await _http.get(resultUri, headers: _headers);

    if (response.statusCode != 200) {
      throw StateError(
        'BigQuery results ${response.statusCode}: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return _parseQueryResponse(decoded);
  }

  List<Map<String, dynamic>> _parseQueryResponse(
    Map<String, dynamic> decoded,
  ) {
    final schema = decoded['schema'] as Map<String, dynamic>?;
    if (schema == null) return [];

    final fields = (schema['fields'] as List<dynamic>? ?? [])
        .map((f) => (f as Map<String, dynamic>)['name'] as String)
        .toList();

    final rows = decoded['rows'] as List<dynamic>? ?? [];

    return rows.map((row) {
      final r = row as Map<String, dynamic>;
      final cells = r['f'] as List<dynamic>;
      final map = <String, dynamic>{};
      for (var i = 0; i < fields.length; i++) {
        final cell = cells[i] as Map<String, dynamic>;
        map[fields[i]] = cell['v'];
      }
      return map;
    }).toList();
  }

  /// Convert positional `?` bindings to BigQuery `@p1`, `@p2` named params.
  (String, List<Map<String, dynamic>>) _buildQueryParams(
    String sql,
    List<dynamic> bindings,
  ) {
    if (bindings.isEmpty) return (sql, []);

    var paramIndex = 0;
    final resolvedSql = sql.replaceAllMapped(
      RegExp(r'\?'),
      (_) => '@p${++paramIndex}',
    );

    final params = <Map<String, dynamic>>[];
    for (var i = 0; i < bindings.length; i++) {
      params.add({
        'name': 'p${i + 1}',
        'parameterType': {'type': _bqType(bindings[i])},
        'parameterValue': {'value': bindings[i]?.toString()},
      });
    }

    return (resolvedSql, params);
  }

  String _bqType(dynamic value) {
    if (value == null) return 'STRING';
    if (value is bool) return 'BOOL';
    if (value is int) return 'INT64';
    if (value is double) return 'FLOAT64';
    return 'STRING';
  }
}
