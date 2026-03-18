import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:knex_dart_turso/knex_dart_turso.dart';
import 'package:test/test.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

/// Build a canonical libSQL pipeline response for a single execute + close.
http.Response pipelineOk({
  List<Map<String, String>> cols = const [],
  List<List<Map<String, dynamic>>> rows = const [],
}) {
  return http.Response(
    jsonEncode({
      'results': [
        {
          'type': 'ok',
          'response': {
            'type': 'execute',
            'result': {
              'cols': cols.map((c) => {'name': c['name']}).toList(),
              'rows': rows,
              'affected_rows': rows.length,
            },
          },
        },
        {'type': 'ok', 'response': {'type': 'close'}},
      ],
    }),
    200,
    headers: {'content-type': 'application/json'},
  );
}

http.Response pipelineError(String message) {
  return http.Response(
    jsonEncode({
      'results': [
        {
          'type': 'error',
          'error': {'message': message, 'code': 'SQLITE_ERROR'},
        },
      ],
    }),
    200,
    headers: {'content-type': 'application/json'},
  );
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  group('TursoClient — wire format', () {
    test('sends correct pipeline body for a simple SELECT', () async {
      Map<String, dynamic>? capturedBody;

      final client = TursoClient(
        url: 'https://test-org.turso.io',
        authToken: 'test-token',
        httpClient: MockClient((request) async {
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return pipelineOk(
            cols: [{'name': 'id'}, {'name': 'name'}],
            rows: [
              [
                {'type': 'integer', 'value': '1'},
                {'type': 'text', 'value': 'Alice'},
              ],
            ],
          );
        }),
      );

      await client.raw('SELECT * FROM users WHERE id = ?', [1]);

      expect(capturedBody, isNotNull);
      final requests = capturedBody!['requests'] as List<dynamic>;
      expect(requests, hasLength(2));

      final exec = requests.first as Map<String, dynamic>;
      expect(exec['type'], 'execute');
      expect(exec['stmt']['sql'], 'SELECT * FROM users WHERE id = ?');

      final args = exec['stmt']['args'] as List<dynamic>;
      expect(args, hasLength(1));
      expect(args.first, {'type': 'integer', 'value': '1'});

      expect((requests.last as Map<String, dynamic>)['type'], 'close');

      client.close();
    });

    test('sends Authorization header with Bearer token', () async {
      String? capturedAuth;

      final client = TursoClient(
        url: 'https://test-org.turso.io',
        authToken: 'my-secret-token',
        httpClient: MockClient((request) async {
          capturedAuth = request.headers['Authorization'];
          return pipelineOk();
        }),
      );

      await client.raw('SELECT 1');
      expect(capturedAuth, 'Bearer my-secret-token');
      client.close();
    });

    test('omits args field when no bindings', () async {
      Map<String, dynamic>? capturedBody;

      final client = TursoClient(
        url: 'https://test-org.turso.io',
        httpClient: MockClient((request) async {
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return pipelineOk();
        }),
      );

      await client.raw('SELECT 1');
      final stmt = (capturedBody!['requests'] as List).first;
      expect(
        (stmt as Map<String, dynamic>)['stmt'].containsKey('args'),
        isFalse,
        reason: 'args key must be absent when no bindings',
      );
      client.close();
    });

    test('strips trailing slash from URL', () async {
      final uris = <Uri>[];

      final client = TursoClient(
        url: 'https://test-org.turso.io/',
        httpClient: MockClient((request) async {
          uris.add(request.url);
          return pipelineOk();
        }),
      );

      await client.raw('SELECT 1');
      expect(uris.first.path, '/v2/pipeline'); // no double-slash in path
      client.close();
    });
  });

  group('TursoClient — libSQL value type serialization', () {
    Future<Map<String, dynamic>> captureArgs(dynamic value) async {
      late Map<String, dynamic> capturedArg;

      final client = TursoClient(
        url: 'https://example.turso.io',
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final args = (body['requests'] as List).first['stmt']['args'] as List;
          capturedArg = args.first as Map<String, dynamic>;
          return pipelineOk();
        }),
      );

      await client.raw('SELECT ?', [value]);
      client.close();
      return capturedArg;
    }

    test('int → integer type', () async {
      final arg = await captureArgs(42);
      expect(arg, {'type': 'integer', 'value': '42'});
    });

    test('double → float type', () async {
      final arg = await captureArgs(3.14);
      expect(arg, {'type': 'float', 'value': 3.14});
    });

    test('bool true → integer 1', () async {
      final arg = await captureArgs(true);
      expect(arg, {'type': 'integer', 'value': '1'});
    });

    test('bool false → integer 0', () async {
      final arg = await captureArgs(false);
      expect(arg, {'type': 'integer', 'value': '0'});
    });

    test('String → text type', () async {
      final arg = await captureArgs('hello');
      expect(arg, {'type': 'text', 'value': 'hello'});
    });

    test('null → null type', () async {
      final arg = await captureArgs(null);
      expect(arg['type'], 'null');
    });

    test('List<int> → blob type with base64', () async {
      final arg = await captureArgs([104, 101, 108, 108, 111]); // 'hello'
      expect(arg['type'], 'blob');
      expect(arg['base64'], isNotNull);
    });
  });

  group('TursoClient — response parsing', () {
    test('parses integer, float, text, null columns', () async {
      final client = TursoClient(
        url: 'https://example.turso.io',
        httpClient: MockClient((_) async => pipelineOk(
          cols: [
            {'name': 'id'},
            {'name': 'score'},
            {'name': 'label'},
            {'name': 'deleted_at'},
          ],
          rows: [
            [
              {'type': 'integer', 'value': '7'},
              {'type': 'float', 'value': '9.5'},
              {'type': 'text', 'value': 'alpha'},
              {'type': 'null', 'value': null},
            ],
          ],
        )),
      );

      final rows = await client.raw('SELECT 1');
      expect(rows.first['id'], 7);
      expect(rows.first['score'], closeTo(9.5, 0.001));
      expect(rows.first['label'], 'alpha');
      expect(rows.first['deleted_at'], isNull);
      client.close();
    });

    test('parses blob column via base64', () async {
      final client = TursoClient(
        url: 'https://example.turso.io',
        httpClient: MockClient((_) async => pipelineOk(
          cols: [{'name': 'data'}],
          rows: [
            [
              {'type': 'blob', 'base64': 'aGVsbG8='}, // 'hello'
            ],
          ],
        )),
      );

      final rows = await client.raw('SELECT 1');
      final data = rows.first['data'] as List<int>;
      expect(String.fromCharCodes(data), 'hello');
      client.close();
    });

    test('returns empty list for empty result set', () async {
      final client = TursoClient(
        url: 'https://example.turso.io',
        httpClient: MockClient((_) async => pipelineOk()),
      );

      final rows = await client.raw('DELETE FROM users');
      expect(rows, isEmpty);
      client.close();
    });
  });

  group('TursoClient — error handling', () {
    test('throws StateError on non-200 HTTP status', () async {
      final client = TursoClient(
        url: 'https://example.turso.io',
        httpClient: MockClient(
          (_) async => http.Response('Internal Server Error', 500),
        ),
      );

      expect(() => client.raw('SELECT 1'), throwsA(isA<StateError>()));
      client.close();
    });

    test('throws StateError on Turso API error response', () async {
      final client = TursoClient(
        url: 'https://example.turso.io',
        httpClient: MockClient(
          (_) async => pipelineError('no such table: users'),
        ),
      );

      expect(
        () => client.raw('SELECT * FROM users'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('no such table'),
          ),
        ),
      );
      client.close();
    });

    test('throws on closed client', () async {
      final client = TursoClient(
        url: 'https://example.turso.io',
        httpClient: MockClient((_) async => pipelineOk()),
      );
      client.close();
      expect(() => client.raw('SELECT 1'), throwsStateError);
    });
  });

  group('TursoClient — transaction flow', () {
    test('BEGIN / COMMIT sent on success', () async {
      final sqlsSent = <String>[];

      final client = TursoClient(
        url: 'https://example.turso.io',
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final stmt = (body['requests'] as List).first['stmt'];
          if (stmt != null) sqlsSent.add(stmt['sql'] as String);
          return pipelineOk();
        }),
      );

      await client.trx((trx) async {
        await trx.raw('INSERT INTO users VALUES (1, "Alice")');
      });

      expect(sqlsSent, containsAllInOrder(['BEGIN', 'INSERT INTO users VALUES (1, "Alice")', 'COMMIT']));
      client.close();
    });

    test('BEGIN / ROLLBACK sent on error', () async {
      final sqlsSent = <String>[];

      final client = TursoClient(
        url: 'https://example.turso.io',
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final stmt = (body['requests'] as List).first['stmt'];
          if (stmt != null) sqlsSent.add(stmt['sql'] as String);
          return pipelineOk();
        }),
      );

      await expectLater(
        client.trx((trx) async => throw Exception('boom')),
        throwsException,
      );

      expect(sqlsSent.first, 'BEGIN');
      expect(sqlsSent.last, 'ROLLBACK');
      client.close();
    });

    test('nested trx uses SAVEPOINT', () async {
      final sqlsSent = <String>[];

      final client = TursoClient(
        url: 'https://example.turso.io',
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final stmt = (body['requests'] as List).first['stmt'];
          if (stmt != null) sqlsSent.add(stmt['sql'] as String);
          return pipelineOk();
        }),
      );

      await client.trx((outer) async {
        await outer.trx((inner) async {
          await inner.raw('SELECT 1');
        });
      });

      expect(sqlsSent, contains(startsWith('SAVEPOINT sp_')));
      expect(sqlsSent, contains(startsWith('RELEASE SAVEPOINT sp_')));
      client.close();
    });
  });

  group('TursoClient — QueryBuilder integration', () {
    test('select query generates correct SQL and bindings', () async {
      String? capturedSql;
      List<dynamic>? capturedArgs;

      final client = TursoClient(
        url: 'https://example.turso.io',
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final stmt = (body['requests'] as List).first['stmt'];
          capturedSql = stmt['sql'] as String;
          capturedArgs = stmt['args'] as List<dynamic>?;
          return pipelineOk();
        }),
      );

      final knex = KnexTurso(url: 'https://example.turso.io');

      // We need to get at the internal client — use the raw client instead
      final qb = knex.queryBuilder().from('users').where('active', '=', 1).limit(10);
      final compiled = qb.toSQL();

      await client.raw(compiled.sql, compiled.bindings);

      expect(capturedSql, contains('"users"'));
      expect(capturedSql, contains('?'));
      expect(capturedArgs, isNotNull);
      expect(capturedArgs!.first['value'], '1');
      client.close();
      knex.close();
    });
  });

  group('TursoClient — Content-Type header', () {
    test('sends application/json Content-Type', () async {
      String? capturedContentType;
      final client = TursoClient(
        url: 'https://example.turso.io',
        httpClient: MockClient((request) async {
          capturedContentType = request.headers['content-type'];
          return pipelineOk();
        }),
      );
      await client.raw('SELECT 1');
      expect(capturedContentType, contains('application/json'));
      client.close();
    });
  });

  group('TursoClient — multiple bindings', () {
    test('mixed types serialized correctly in one call', () async {
      late List<dynamic> capturedArgs;
      final client = TursoClient(
        url: 'https://example.turso.io',
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          capturedArgs =
              (body['requests'] as List).first['stmt']['args'] as List<dynamic>;
          return pipelineOk();
        }),
      );
      await client.raw('SELECT ?, ?, ?, ?', [42, 3.14, 'hello', null]);
      expect((capturedArgs[0] as Map)['type'], 'integer');
      expect((capturedArgs[1] as Map)['type'], 'float');
      expect((capturedArgs[2] as Map)['type'], 'text');
      expect((capturedArgs[3] as Map)['type'], 'null');
      client.close();
    });

    test('blob binding encoded as base64', () async {
      late Map<String, dynamic> capturedArg;
      final client = TursoClient(
        url: 'https://example.turso.io',
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          capturedArg = ((body['requests'] as List).first['stmt']['args'] as List)
              .first as Map<String, dynamic>;
          return pipelineOk();
        }),
      );
      await client.raw('SELECT ?', [[72, 101, 108, 108, 111]]);
      expect(capturedArg['type'], 'blob');
      expect(capturedArg['base64'], isNotNull);
      client.close();
    });
  });

  group('TursoClient — multi-row response', () {
    test('parses multiple rows and columns', () async {
      final client = TursoClient(
        url: 'https://example.turso.io',
        httpClient: MockClient((_) async => pipelineOk(
          cols: [{'name': 'id'}, {'name': 'name'}, {'name': 'score'}],
          rows: [
            [
              {'type': 'integer', 'value': '1'},
              {'type': 'text', 'value': 'Alice'},
              {'type': 'float', 'value': '9.5'},
            ],
            [
              {'type': 'integer', 'value': '2'},
              {'type': 'text', 'value': 'Bob'},
              {'type': 'null', 'value': null},
            ],
          ],
        )),
      );
      final rows = await client.raw('SELECT id, name, score FROM users');
      expect(rows, hasLength(2));
      expect(rows.first['id'], 1);
      expect(rows.first['score'], closeTo(9.5, 0.001));
      expect(rows.last['score'], isNull);
      client.close();
    });
  });

  group('TursoClient — INSERT / UPDATE / DELETE SQL shape', () {
    test('INSERT query structure', () async {
      String? capturedSql;
      final client = TursoClient(
        url: 'https://example.turso.io',
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          capturedSql = (body['requests'] as List).first['stmt']['sql'] as String;
          return pipelineOk();
        }),
      );
      final db = KnexTurso(url: 'https://example.turso.io');
      final compiled = db.queryBuilder().table('users')
          .insert({'name': 'Alice', 'score': 9.5}).toSQL();
      await client.raw(compiled.sql, compiled.bindings);
      expect(capturedSql, contains('insert into'));
      expect(capturedSql, contains('"users"'));
      client.close();
      db.close();
    });

    test('UPDATE query structure', () async {
      String? capturedSql;
      final client = TursoClient(
        url: 'https://example.turso.io',
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          capturedSql = (body['requests'] as List).first['stmt']['sql'] as String;
          return pipelineOk();
        }),
      );
      final db = KnexTurso(url: 'https://example.turso.io');
      final compiled = db.queryBuilder().table('users')
          .where('id', '=', 1).update({'score': 10.0}).toSQL();
      await client.raw(compiled.sql, compiled.bindings);
      expect(capturedSql, contains('update'));
      expect(capturedSql, contains('"users"'));
      expect(capturedSql, contains('set'));
      client.close();
      db.close();
    });

    test('DELETE query structure', () async {
      String? capturedSql;
      final client = TursoClient(
        url: 'https://example.turso.io',
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          capturedSql = (body['requests'] as List).first['stmt']['sql'] as String;
          return pipelineOk();
        }),
      );
      final db = KnexTurso(url: 'https://example.turso.io');
      final compiled = db.queryBuilder().table('users')
          .where('id', '=', 1).delete().toSQL();
      await client.raw(compiled.sql, compiled.bindings);
      expect(capturedSql, contains('delete from'));
      expect(capturedSql, contains('"users"'));
      client.close();
      db.close();
    });
  });

  group('TursoClient — transaction SQL sequence detail', () {
    test('inner error → ROLLBACK TO SAVEPOINT, outer still COMMITs', () async {
      final sqlsSent = <String>[];
      final client = TursoClient(
        url: 'https://example.turso.io',
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final stmt2 = (body['requests'] as List).first['stmt'];
          if (stmt2 != null) sqlsSent.add(stmt2['sql'] as String);
          return pipelineOk();
        }),
      );
      await client.trx((outer) async {
        try {
          await outer.trx((inner) async {
            await inner.raw('SELECT 1');
            throw Exception('inner boom');
          });
        } catch (_) {}
      });
      expect(sqlsSent.first, 'BEGIN');
      expect(sqlsSent.last, 'COMMIT');
      expect(sqlsSent.any((s) => s.startsWith('SAVEPOINT sp_')), isTrue);
      expect(sqlsSent.any((s) => s.startsWith('ROLLBACK TO SAVEPOINT sp_')), isTrue);
      client.close();
    });

    test('inner success → RELEASE SAVEPOINT sent', () async {
      final sqlsSent = <String>[];
      final client = TursoClient(
        url: 'https://example.turso.io',
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final stmt2 = (body['requests'] as List).first['stmt'];
          if (stmt2 != null) sqlsSent.add(stmt2['sql'] as String);
          return pipelineOk();
        }),
      );
      await client.trx((outer) async {
        await outer.trx((inner) async {
          await inner.raw('SELECT 1');
        });
      });
      expect(sqlsSent.any((s) => s.startsWith('RELEASE SAVEPOINT sp_')), isTrue);
      client.close();
    });
  });
}
