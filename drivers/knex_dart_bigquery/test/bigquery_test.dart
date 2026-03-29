import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:knex_dart_bigquery/knex_dart_bigquery.dart';
import 'package:test/test.dart';

// ─── Response helpers ─────────────────────────────────────────────────────────

const _project = 'my-gcp-project';
const _token = 'ya29.test-token';

/// Returns a submitted-job response (POST /jobs).
http.Response jobSubmitResponse(String jobId) {
  return http.Response(
    jsonEncode({
      'kind': 'bigquery#job',
      'status': {'state': 'RUNNING'},
      'jobReference': {'projectId': _project, 'jobId': jobId, 'location': 'US'},
    }),
    200,
    headers: {'content-type': 'application/json'},
  );
}

/// Returns a DONE job-status response (GET /jobs/{id}).
http.Response jobDoneResponse(String jobId) {
  return http.Response(
    jsonEncode({
      'kind': 'bigquery#job',
      'status': {'state': 'DONE'},
      'jobReference': {'projectId': _project, 'jobId': jobId},
    }),
    200,
    headers: {'content-type': 'application/json'},
  );
}

/// Returns a query-results response (GET /queries/{id}).
http.Response queryResultsResponse({
  List<String> fields = const [],
  List<List<String?>> rows = const [],
}) {
  return http.Response(
    jsonEncode({
      'kind': 'bigquery#queryResponse',
      'jobComplete': true,
      'schema': {
        'fields': fields.map((f) => {'name': f, 'type': 'STRING'}).toList(),
      },
      'rows': rows
          .map(
            (row) => {
              'f': row.map((v) => {'v': v}).toList(),
            },
          )
          .toList(),
    }),
    200,
    headers: {'content-type': 'application/json'},
  );
}

/// Returns a BigQuery API error for the queries endpoint.
http.Response queryError(String message) {
  return http.Response(
    jsonEncode({
      'error': {'code': 404, 'message': message, 'status': 'NOT_FOUND'},
    }),
    404,
    headers: {'content-type': 'application/json'},
  );
}

// ─── Mock that sequences multiple responses ───────────────────────────────────

class _SequentialClient extends http.BaseClient {
  final List<http.Response Function(http.Request)> _handlers;
  int _index = 0;

  _SequentialClient(this._handlers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final req = request as http.Request;
    final handler = _handlers[_index % _handlers.length];
    _index++;
    final response = handler(req);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  group('BigQueryClient — wire format', () {
    test('sends Bearer Authorization header', () async {
      String? capturedAuth;
      // Sequence: submit → done → results
      final mock = _SequentialClient([
        (req) {
          capturedAuth = req.headers['Authorization'];
          return jobSubmitResponse('job-1');
        },
        (_) => jobDoneResponse('job-1'),
        (_) => queryResultsResponse(),
      ]);

      final client = BigQueryClient(
        projectId: _project,
        token: _token,
        httpClient: mock,
      );

      await client.raw('SELECT 1');
      expect(capturedAuth, 'Bearer $_token');
      client.close();
    });

    test('submits job to correct projects URL', () async {
      Uri? submitUri;
      final mock = _SequentialClient([
        (req) {
          submitUri = req.url;
          return jobSubmitResponse('job-2');
        },
        (_) => jobDoneResponse('job-2'),
        (_) => queryResultsResponse(),
      ]);

      final client = BigQueryClient(
        projectId: _project,
        token: _token,
        httpClient: mock,
      );

      await client.raw('SELECT 1');
      expect(submitUri.toString(), contains('/projects/$_project/jobs'));
      client.close();
    });

    test('sets useLegacySql: false', () async {
      Map<String, dynamic>? capturedConfig;
      final mock = _SequentialClient([
        (req) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          capturedConfig =
              (body['configuration'] as Map<String, dynamic>)['query']
                  as Map<String, dynamic>;
          return jobSubmitResponse('job-3');
        },
        (_) => jobDoneResponse('job-3'),
        (_) => queryResultsResponse(),
      ]);

      final client = BigQueryClient(
        projectId: _project,
        token: _token,
        httpClient: mock,
      );

      await client.raw('SELECT 1');
      expect(capturedConfig!['useLegacySql'], isFalse);
      client.close();
    });
  });

  group('BigQueryClient — ? → @pN parameter rewriting', () {
    test('rewrites positional ? to @p1, @p2, ...', () async {
      String? capturedSql;
      List<dynamic>? capturedParams;

      final mock = _SequentialClient([
        (req) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          final q = (body['configuration'] as Map)['query'] as Map;
          capturedSql = q['query'] as String;
          capturedParams = q['queryParameters'] as List<dynamic>?;
          return jobSubmitResponse('job-4');
        },
        (_) => jobDoneResponse('job-4'),
        (_) => queryResultsResponse(),
      ]);

      final client = BigQueryClient(
        projectId: _project,
        token: _token,
        httpClient: mock,
      );

      await client.raw('SELECT * FROM t WHERE a = ? AND b = ?', ['foo', 42]);

      expect(capturedSql, contains('@p1'));
      expect(capturedSql, contains('@p2'));
      expect(capturedSql, isNot(contains('?')));

      final params = capturedParams!.cast<Map<String, dynamic>>();
      expect(params.first['name'], 'p1');
      expect(params.first['parameterValue']['value'], 'foo');
      expect(params.last['name'], 'p2');
      expect(params.last['parameterValue']['value'], '42');

      client.close();
    });

    test('int binding → INT64 type', () async {
      String? capturedType;

      final mock = _SequentialClient([
        (req) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          final q = (body['configuration'] as Map)['query'] as Map;
          final params = (q['queryParameters'] as List).cast<Map>();
          capturedType = params.first['parameterType']['type'] as String;
          return jobSubmitResponse('job-5');
        },
        (_) => jobDoneResponse('job-5'),
        (_) => queryResultsResponse(),
      ]);

      final client = BigQueryClient(
        projectId: _project,
        token: _token,
        httpClient: mock,
      );

      await client.raw('SELECT ?', [99]);
      expect(capturedType, 'INT64');
      client.close();
    });

    test('omits queryParameters when no bindings', () async {
      bool? hasParams;

      final mock = _SequentialClient([
        (req) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          final q = (body['configuration'] as Map)['query'] as Map;
          hasParams = q.containsKey('queryParameters');
          return jobSubmitResponse('job-6');
        },
        (_) => jobDoneResponse('job-6'),
        (_) => queryResultsResponse(),
      ]);

      final client = BigQueryClient(
        projectId: _project,
        token: _token,
        httpClient: mock,
      );

      await client.raw('SELECT 1');
      expect(hasParams, isFalse);
      client.close();
    });
  });

  group('BigQueryClient — response parsing', () {
    test('maps schema fields to row values', () async {
      final mock = _SequentialClient([
        (_) => jobSubmitResponse('job-7'),
        (_) => jobDoneResponse('job-7'),
        (_) => queryResultsResponse(
          fields: ['id', 'name', 'score'],
          rows: [
            ['1', 'Alice', '9.5'],
            ['2', 'Bob', null],
          ],
        ),
      ]);

      final client = BigQueryClient(
        projectId: _project,
        token: _token,
        httpClient: mock,
      );

      final rows = await client.raw('SELECT id, name, score FROM users');
      expect(rows, hasLength(2));
      expect(rows.first['name'], 'Alice');
      expect(rows.first['id'], '1');
      expect(rows.last['score'], isNull);
      client.close();
    });

    test('returns empty list for no rows', () async {
      final mock = _SequentialClient([
        (_) => jobSubmitResponse('job-8'),
        (_) => jobDoneResponse('job-8'),
        (_) => queryResultsResponse(fields: ['count'], rows: []),
      ]);

      final client = BigQueryClient(
        projectId: _project,
        token: _token,
        httpClient: mock,
      );

      final rows = await client.raw('SELECT COUNT(*) FROM users WHERE 1 = 0');
      expect(rows, isEmpty);
      client.close();
    });
  });

  group('BigQueryClient — error handling', () {
    test('throws on job submission failure (non-200)', () async {
      final client = BigQueryClient(
        projectId: _project,
        token: _token,
        httpClient: MockClient((_) async => http.Response('Forbidden', 403)),
      );

      expect(() => client.raw('SELECT 1'), throwsA(isA<StateError>()));
      client.close();
    });

    test('throws when job has errorResult', () async {
      final mock = _SequentialClient([
        (_) => jobSubmitResponse('job-err'),
        (_) => http.Response(
          jsonEncode({
            'status': {
              'state': 'DONE',
              'errorResult': {
                'reason': 'notFound',
                'message': 'Table not found',
              },
            },
            'jobReference': {'projectId': _project, 'jobId': 'job-err'},
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ]);

      final client = BigQueryClient(
        projectId: _project,
        token: _token,
        httpClient: mock,
      );

      expect(
        () => client.raw('SELECT * FROM missing_table'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Table not found'),
          ),
        ),
      );
      client.close();
    });

    test('throws on closed client', () {
      final client = BigQueryClient(
        projectId: _project,
        token: _token,
        httpClient: MockClient((_) async => jobSubmitResponse('x')),
      );
      client.close();
      expect(() => client.raw('SELECT 1'), throwsStateError);
    });
  });

  group('BigQueryClient — QueryBuilder integration', () {
    test('queryBuilder uses backtick identifiers', () {
      final db = KnexBigQuery(projectId: _project, token: _token);
      final compiled = db
          .queryBuilder()
          .from('events')
          .where('date', '=', '2024-01-01')
          .select(['user_id', 'event_name'])
          .toSQL();

      expect(compiled.sql, contains('`events`'));
      expect(compiled.sql, contains('`user_id`'));
      expect(compiled.sql, contains('?'));
      db.close();
    });
  });

  group('BigQueryClient — parameter types', () {
    Future<Map<String, dynamic>> captureFirstParam(dynamic value) async {
      late Map<String, dynamic> capturedParam;
      final mock = _SequentialClient([
        (req) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          final q = (body['configuration'] as Map)['query'] as Map;
          capturedParam = (q['queryParameters'] as List)
              .cast<Map<String, dynamic>>()
              .first;
          return jobSubmitResponse('pt-job');
        },
        (_) => jobDoneResponse('pt-job'),
        (_) => queryResultsResponse(),
      ]);
      final client = BigQueryClient(
        projectId: _project,
        token: _token,
        httpClient: mock,
      );
      await client.raw('SELECT ?', [value]);
      client.close();
      return capturedParam;
    }

    test('String binding → STRING type', () async {
      final p = await captureFirstParam('hello');
      expect(p['parameterType']['type'], 'STRING');
      expect(p['parameterValue']['value'], 'hello');
    });

    test('double binding → FLOAT64 type', () async {
      final p = await captureFirstParam(3.14);
      expect(p['parameterType']['type'], 'FLOAT64');
    });

    test('bool binding → BOOL type', () async {
      final p = await captureFirstParam(true);
      expect(p['parameterType']['type'], 'BOOL');
    });

    test('int binding → INT64 type', () async {
      final p = await captureFirstParam(99);
      expect(p['parameterType']['type'], 'INT64');
      expect(p['parameterValue']['value'], '99');
    });

    test('multiple bindings have sequential @p names', () async {
      String? capturedSql;
      List<dynamic>? capturedParams;
      final mock = _SequentialClient([
        (req) {
          final q =
              ((jsonDecode(req.body) as Map)['configuration'] as Map)['query']
                  as Map;
          capturedSql = q['query'] as String;
          capturedParams = q['queryParameters'] as List?;
          return jobSubmitResponse('mp-job');
        },
        (_) => jobDoneResponse('mp-job'),
        (_) => queryResultsResponse(),
      ]);
      final client = BigQueryClient(
        projectId: _project,
        token: _token,
        httpClient: mock,
      );
      await client.raw('SELECT ?, ?, ?', ['a', 1, true]);
      final params = capturedParams!.cast<Map<String, dynamic>>();
      expect(params.map((p) => p['name']).toList(), ['p1', 'p2', 'p3']);
      expect(capturedSql, contains('@p1'));
      expect(capturedSql, contains('@p3'));
      client.close();
    });
  });

  group('BigQueryClient — job polling', () {
    test('polls until DONE when first status is RUNNING', () async {
      int pollCount = 0;
      final mock = _SequentialClient([
        (_) => jobSubmitResponse('poll-job'),
        (_) {
          pollCount++;
          return http.Response(
            jsonEncode({
              'status': {'state': 'RUNNING'},
              'jobReference': {'projectId': _project, 'jobId': 'poll-job'},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        },
        (_) {
          pollCount++;
          return jobDoneResponse('poll-job');
        },
        (_) => queryResultsResponse(
          fields: ['n'],
          rows: [
            ['42'],
          ],
        ),
      ]);
      final client = BigQueryClient(
        projectId: _project,
        token: _token,
        httpClient: mock,
      );
      final rows = await client.raw('SELECT 42 AS n');
      expect(pollCount, 2);
      expect(rows.first['n'], '42');
      client.close();
    });
  });

  group('BigQueryClient — response parsing extended', () {
    test('parses multiple rows with mixed null values', () async {
      final mock = _SequentialClient([
        (_) => jobSubmitResponse('multi-job'),
        (_) => jobDoneResponse('multi-job'),
        (_) => queryResultsResponse(
          fields: ['id', 'name', 'score'],
          rows: [
            ['1', 'Alice', '9.5'],
            ['2', 'Bob', null],
            ['3', 'Carol', '7.0'],
          ],
        ),
      ]);
      final client = BigQueryClient(
        projectId: _project,
        token: _token,
        httpClient: mock,
      );
      final rows = await client.raw('SELECT id, name, score FROM users');
      expect(rows, hasLength(3));
      expect(rows[1]['score'], isNull);
      expect(rows[2]['id'], '3');
      client.close();
    });
  });

  group('BigQueryClient — error handling extended', () {
    test('throws on 401 Unauthorized', () async {
      final client = BigQueryClient(
        projectId: _project,
        token: _token,
        httpClient: MockClient((_) async => http.Response('Unauthorized', 401)),
      );
      expect(() => client.raw('SELECT 1'), throwsA(isA<StateError>()));
      client.close();
    });

    test('errorResult message is in exception', () async {
      final mock = _SequentialClient([
        (_) => jobSubmitResponse('err-job'),
        (_) => http.Response(
          jsonEncode({
            'status': {
              'state': 'DONE',
              'errorResult': {
                'reason': 'invalidQuery',
                'message': 'Syntax error: Unexpected',
              },
            },
            'jobReference': {'projectId': _project, 'jobId': 'err-job'},
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ]);
      final client = BigQueryClient(
        projectId: _project,
        token: _token,
        httpClient: mock,
      );
      expect(
        () => client.raw('SELECT FROM'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Syntax error'),
          ),
        ),
      );
      client.close();
    });
  });

  group('BigQueryClient — QueryBuilder extended', () {
    test('INSERT uses backtick identifiers', () {
      final db = KnexBigQuery(projectId: _project, token: _token);
      final compiled = db.queryBuilder().table('events').insert({
        'user_id': 1,
        'event_name': 'click',
      }).toSQL();
      expect(compiled.sql, contains('insert into'));
      expect(compiled.sql, contains('`events`'));
      expect(compiled.bindings, containsAll([1, 'click']));
      db.close();
    });

    test('WHERE + ORDER BY + LIMIT compiles correctly', () {
      final db = KnexBigQuery(projectId: _project, token: _token);
      final compiled = db
          .queryBuilder()
          .from('events')
          .where('user_id', '=', 42)
          .orderBy('created_at', 'desc')
          .limit(10)
          .toSQL();
      expect(compiled.sql, contains('`events`'));
      expect(compiled.sql, contains('order by'));
      expect(compiled.sql, contains('limit'));
      expect(compiled.bindings, contains(42));
      db.close();
    });
  });

  MockClient mockQueryFlow({
    required String jobId,
    required void Function(http.Request request) onSubmit,
  }) {
    var callCount = 0;
    return MockClient((request) async {
      callCount++;
      if (callCount == 1) {
        onSubmit(request);
        return jobSubmitResponse(jobId);
      }
      if (callCount == 2) {
        return jobDoneResponse(jobId);
      }
      return queryResultsResponse();
    });
  }

  group('BigQueryClient — QueryBuilder joins', () {
    test('INNER JOIN SQL shape with backticks', () async {
      String? capturedSql;

      final mock = mockQueryFlow(
        jobId: 'join-job-1',
        onSubmit: (req) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          final q =
              (body['configuration'] as Map<String, dynamic>)['query']
                  as Map<String, dynamic>;
          capturedSql = q['query'] as String;
        },
      );

      final client = BigQueryClient(
        projectId: _project,
        token: _token,
        httpClient: mock,
      );
      final db = KnexBigQuery(projectId: _project, token: _token);

      final compiled = db
          .queryBuilder()
          .from('users')
          .join('accounts', 'users.id', 'accounts.user_id')
          .select(['users.id', 'accounts.balance'])
          .toSQL();
      await client.raw(compiled.sql, compiled.bindings);

      final sql = capturedSql!.toLowerCase();
      expect(sql, contains('from `users`'));
      expect(sql, contains('join `accounts`'));
      expect(sql, contains('`users`.`id`'));
      expect(sql, contains('`accounts`.`user_id`'));
      client.close();
      db.close();
    });

    test('LEFT JOIN SQL shape with backticks', () async {
      String? capturedSql;

      final mock = mockQueryFlow(
        jobId: 'join-job-2',
        onSubmit: (req) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          final q =
              (body['configuration'] as Map<String, dynamic>)['query']
                  as Map<String, dynamic>;
          capturedSql = q['query'] as String;
        },
      );

      final client = BigQueryClient(
        projectId: _project,
        token: _token,
        httpClient: mock,
      );
      final db = KnexBigQuery(projectId: _project, token: _token);

      final compiled = db
          .queryBuilder()
          .from('users')
          .leftJoin('accounts', 'users.id', 'accounts.user_id')
          .select(['users.id', 'accounts.balance'])
          .toSQL();
      await client.raw(compiled.sql, compiled.bindings);

      final sql = capturedSql!.toLowerCase();
      expect(sql, contains('left join `accounts`'));
      expect(sql, contains('`users`.`id`'));
      expect(sql, contains('`accounts`.`user_id`'));
      client.close();
      db.close();
    });
  });

  group('BigQueryClient — QueryBuilder ordering and pagination', () {
    test('orderBy + limit + offset SQL shape', () async {
      String? capturedSql;

      final mock = mockQueryFlow(
        jobId: 'order-job',
        onSubmit: (req) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          final q =
              (body['configuration'] as Map<String, dynamic>)['query']
                  as Map<String, dynamic>;
          capturedSql = q['query'] as String;
        },
      );

      final client = BigQueryClient(
        projectId: _project,
        token: _token,
        httpClient: mock,
      );
      final db = KnexBigQuery(projectId: _project, token: _token);

      final compiled = db
          .queryBuilder()
          .from('events')
          .select(['id'])
          .orderBy('created_at', 'desc')
          .limit(10)
          .offset(5)
          .toSQL();
      await client.raw(compiled.sql, compiled.bindings);

      final sql = capturedSql!.toLowerCase();
      expect(sql, contains('order by `created_at` desc'));
      expect(sql, contains('limit'));
      expect(sql, contains('offset'));
      client.close();
      db.close();
    });
  });

  group('BigQueryClient — QueryBuilder delete', () {
    test('delete SQL shape', () async {
      String? capturedSql;

      final mock = mockQueryFlow(
        jobId: 'delete-job',
        onSubmit: (req) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          final q =
              (body['configuration'] as Map<String, dynamic>)['query']
                  as Map<String, dynamic>;
          capturedSql = q['query'] as String;
        },
      );

      final client = BigQueryClient(
        projectId: _project,
        token: _token,
        httpClient: mock,
      );
      final db = KnexBigQuery(projectId: _project, token: _token);

      final compiled = db
          .queryBuilder()
          .table('events')
          .where('id', '=', 7)
          .delete()
          .toSQL();
      await client.raw(compiled.sql, compiled.bindings);

      final sql = capturedSql!.toLowerCase();
      expect(sql, contains('delete from `events`'));
      expect(sql, contains('where `id` ='));
      client.close();
      db.close();
    });
  });

  group('BigQueryClient — QueryBuilder update', () {
    test('update SQL shape', () async {
      String? capturedSql;

      final mock = mockQueryFlow(
        jobId: 'update-job',
        onSubmit: (req) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          final q =
              (body['configuration'] as Map<String, dynamic>)['query']
                  as Map<String, dynamic>;
          capturedSql = q['query'] as String;
        },
      );

      final client = BigQueryClient(
        projectId: _project,
        token: _token,
        httpClient: mock,
      );
      final db = KnexBigQuery(projectId: _project, token: _token);

      final compiled = db
          .queryBuilder()
          .table('events')
          .where('id', '=', 7)
          .update({'event_name': 'clicked'})
          .toSQL();
      await client.raw(compiled.sql, compiled.bindings);

      final sql = capturedSql!.toLowerCase();
      expect(sql, contains('update `events`'));
      expect(sql, contains('set `event_name` ='));
      expect(sql, contains('where `id` ='));
      client.close();
      db.close();
    });
  });

  group('BigQueryClient — QueryBuilder groupBy and having', () {
    test('groupBy + havingRaw SQL shape', () async {
      String? capturedSql;

      final mock = mockQueryFlow(
        jobId: 'group-job',
        onSubmit: (req) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          final q =
              (body['configuration'] as Map<String, dynamic>)['query']
                  as Map<String, dynamic>;
          capturedSql = q['query'] as String;
        },
      );

      final client = BigQueryClient(
        projectId: _project,
        token: _token,
        httpClient: mock,
      );
      final db = KnexBigQuery(projectId: _project, token: _token);

      final compiled = db
          .queryBuilder()
          .from('events')
          .select(['user_id'])
          .groupBy('user_id')
          .havingRaw('count(*) > ?', [1])
          .toSQL();
      await client.raw(compiled.sql, compiled.bindings);

      final sql = capturedSql!.toLowerCase();
      expect(sql, contains('group by `user_id`'));
      expect(sql, contains('having count(*) >'));
      client.close();
      db.close();
    });
  });

  group('BigQueryClient — QueryBuilder distinct', () {
    test('distinct SQL shape', () async {
      String? capturedSql;

      final mock = mockQueryFlow(
        jobId: 'distinct-job',
        onSubmit: (req) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          final q =
              (body['configuration'] as Map<String, dynamic>)['query']
                  as Map<String, dynamic>;
          capturedSql = q['query'] as String;
        },
      );

      final client = BigQueryClient(
        projectId: _project,
        token: _token,
        httpClient: mock,
      );
      final db = KnexBigQuery(projectId: _project, token: _token);

      final compiled = db.queryBuilder().from('events').distinct([
        'user_id',
      ]).toSQL();
      await client.raw(compiled.sql, compiled.bindings);

      final sql = capturedSql!.toLowerCase();
      expect(sql, contains('select distinct'));
      expect(sql, contains('`user_id`'));
      expect(sql, contains('from `events`'));
      client.close();
      db.close();
    });
  });

  group('BigQueryClient — QueryBuilder whereNotIn / whereNull / orWhere', () {
    test('whereNotIn SQL shape', () async {
      String? capturedSql;

      final mock = mockQueryFlow(
        jobId: 'filter-job-1',
        onSubmit: (req) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          final q =
              (body['configuration'] as Map<String, dynamic>)['query']
                  as Map<String, dynamic>;
          capturedSql = q['query'] as String;
        },
      );

      final client = BigQueryClient(
        projectId: _project,
        token: _token,
        httpClient: mock,
      );
      final db = KnexBigQuery(projectId: _project, token: _token);

      final compiled = db.queryBuilder().from('events').whereNotIn(
        'event_name',
        ['click', 'view'],
      ).toSQL();
      await client.raw(compiled.sql, compiled.bindings);

      final sql = capturedSql!.toLowerCase();
      expect(sql, contains('`event_name` not in'));
      client.close();
      db.close();
    });

    test('whereNull SQL shape', () async {
      String? capturedSql;

      final mock = mockQueryFlow(
        jobId: 'filter-job-2',
        onSubmit: (req) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          final q =
              (body['configuration'] as Map<String, dynamic>)['query']
                  as Map<String, dynamic>;
          capturedSql = q['query'] as String;
        },
      );

      final client = BigQueryClient(
        projectId: _project,
        token: _token,
        httpClient: mock,
      );
      final db = KnexBigQuery(projectId: _project, token: _token);

      final compiled = db
          .queryBuilder()
          .from('events')
          .whereNull('deleted_at')
          .toSQL();
      await client.raw(compiled.sql, compiled.bindings);

      final sql = capturedSql!.toLowerCase();
      expect(sql, contains('`deleted_at` is null'));
      client.close();
      db.close();
    });

    test('orWhere SQL shape', () async {
      String? capturedSql;

      final mock = mockQueryFlow(
        jobId: 'filter-job-3',
        onSubmit: (req) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          final q =
              (body['configuration'] as Map<String, dynamic>)['query']
                  as Map<String, dynamic>;
          capturedSql = q['query'] as String;
        },
      );

      final client = BigQueryClient(
        projectId: _project,
        token: _token,
        httpClient: mock,
      );
      final db = KnexBigQuery(projectId: _project, token: _token);

      final compiled = db
          .queryBuilder()
          .from('events')
          .where('event_name', '=', 'click')
          .orWhere('event_name', '=', 'view')
          .toSQL();
      await client.raw(compiled.sql, compiled.bindings);

      final sql = capturedSql!.toLowerCase();
      expect(sql, contains('`event_name` ='));
      expect(sql, contains('or `event_name` ='));
      client.close();
      db.close();
    });
  });
}
