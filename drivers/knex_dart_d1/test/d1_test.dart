import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:knex_dart_d1/knex_dart_d1.dart';
import 'package:test/test.dart';

// ─── Response helpers ─────────────────────────────────────────────────────────

http.Response queryOk(List<Map<String, dynamic>> rows) {
  return http.Response(
    jsonEncode({
      'success': true,
      'errors': [],
      'result': [
        {'success': true, 'results': rows, 'meta': {}},
      ],
    }),
    200,
    headers: {'content-type': 'application/json'},
  );
}

http.Response batchOk(List<List<Map<String, dynamic>>> resultSets) {
  return http.Response(
    jsonEncode({
      'success': true,
      'errors': [],
      'result': resultSets
          .map((rows) => {'success': true, 'results': rows, 'meta': {}})
          .toList(),
    }),
    200,
    headers: {'content-type': 'application/json'},
  );
}

http.Response apiError(String message) {
  return http.Response(
    jsonEncode({
      'success': false,
      'errors': [
        {'code': 7500, 'message': message},
      ],
      'result': null,
    }),
    200,
    headers: {'content-type': 'application/json'},
  );
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  const accountId = 'test-account';
  const databaseId = 'test-db';
  const apiToken = 'test-token';

  group('D1Client — wire format', () {
    test('sends correct Authorization header', () async {
      String? capturedAuth;

      final client = D1Client(
        accountId: accountId,
        databaseId: databaseId,
        apiToken: apiToken,
        httpClient: MockClient((request) async {
          capturedAuth = request.headers['Authorization'];
          return queryOk([]);
        }),
      );

      await client.raw('SELECT 1');
      expect(capturedAuth, 'Bearer test-token');
      client.close();
    });

    test('sends SQL and params to correct URL', () async {
      Uri? capturedUri;
      Map<String, dynamic>? capturedBody;

      final client = D1Client(
        accountId: accountId,
        databaseId: databaseId,
        apiToken: apiToken,
        httpClient: MockClient((request) async {
          capturedUri = request.url;
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return queryOk([]);
        }),
      );

      await client.raw('SELECT * FROM users WHERE id = ?', [42]);

      expect(
        capturedUri.toString(),
        contains('/accounts/test-account/d1/database/test-db/query'),
      );
      expect(capturedBody!['sql'], 'SELECT * FROM users WHERE id = ?');
      expect(capturedBody!['params'], [42]);
      client.close();
    });

    test('omits params key when no bindings', () async {
      Map<String, dynamic>? capturedBody;

      final client = D1Client(
        accountId: accountId,
        databaseId: databaseId,
        apiToken: apiToken,
        httpClient: MockClient((request) async {
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return queryOk([]);
        }),
      );

      await client.raw('SELECT 1');
      expect(capturedBody!.containsKey('params'), isFalse);
      client.close();
    });

    test('bool binding coerced to 0/1', () async {
      List<dynamic>? capturedParams;

      final client = D1Client(
        accountId: accountId,
        databaseId: databaseId,
        apiToken: apiToken,
        httpClient: MockClient((request) async {
          capturedParams =
              (jsonDecode(request.body) as Map<String, dynamic>)['params']
                  as List<dynamic>;
          return queryOk([]);
        }),
      );

      await client.raw('SELECT ?', [true]);
      expect(capturedParams!.first, 1);
      client.close();
    });
  });

  group('D1Client — response parsing', () {
    test('parses result rows correctly', () async {
      final client = D1Client(
        accountId: accountId,
        databaseId: databaseId,
        apiToken: apiToken,
        httpClient: MockClient(
          (_) async => queryOk([
            {'id': 1, 'name': 'Alice', 'active': true},
            {'id': 2, 'name': 'Bob', 'active': false},
          ]),
        ),
      );

      final rows = await client.raw('SELECT * FROM users');
      expect(rows, hasLength(2));
      expect(rows.first['name'], 'Alice');
      expect(rows.last['id'], 2);
      client.close();
    });

    test('returns empty list for zero rows', () async {
      final client = D1Client(
        accountId: accountId,
        databaseId: databaseId,
        apiToken: apiToken,
        httpClient: MockClient((_) async => queryOk([])),
      );

      final rows = await client.raw('DELETE FROM users');
      expect(rows, isEmpty);
      client.close();
    });
  });

  group('D1Client — batch API', () {
    test('sends all statements to /batch endpoint', () async {
      Uri? capturedUri;
      Map<String, dynamic>? capturedBody;

      final client = D1Client(
        accountId: accountId,
        databaseId: databaseId,
        apiToken: apiToken,
        httpClient: MockClient((request) async {
          capturedUri = request.url;
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return batchOk([[], []]);
        }),
      );

      await client.batch((b) {
        b.addRaw('INSERT INTO users (id, name) VALUES (1, ?)', ['Alice']);
        b.addRaw('INSERT INTO logs (event) VALUES (?)', ['created']);
      });

      expect(capturedUri.toString(), contains('/batch'));
      final stmts = capturedBody!['statements'] as List<dynamic>;
      expect(stmts, hasLength(2));
      expect(stmts.first['sql'], contains('INSERT INTO users'));
      expect(stmts.last['sql'], contains('INSERT INTO logs'));
      client.close();
    });

    test('batch returns result set per statement', () async {
      final client = D1Client(
        accountId: accountId,
        databaseId: databaseId,
        apiToken: apiToken,
        httpClient: MockClient(
          (_) async => batchOk([
            [
              {'count': 3},
            ],
            [
              {'count': 7},
            ],
          ]),
        ),
      );

      final results = await client.batch((b) {
        b.addRaw('SELECT COUNT(*) as count FROM users');
        b.addRaw('SELECT COUNT(*) as count FROM orders');
      });

      expect(results, hasLength(2));
      expect(results.first.first['count'], 3);
      expect(results.last.first['count'], 7);
      client.close();
    });
  });

  group('D1Client — error handling', () {
    test('throws on non-200 HTTP status', () async {
      final client = D1Client(
        accountId: accountId,
        databaseId: databaseId,
        apiToken: apiToken,
        httpClient: MockClient((_) async => http.Response('Unauthorized', 401)),
      );

      expect(() => client.raw('SELECT 1'), throwsA(isA<StateError>()));
      client.close();
    });

    test('throws on D1 API error', () async {
      final client = D1Client(
        accountId: accountId,
        databaseId: databaseId,
        apiToken: apiToken,
        httpClient: MockClient((_) async => apiError('no such table: users')),
      );

      expect(
        () => client.raw('SELECT * FROM users'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('D1 error'),
          ),
        ),
      );
      client.close();
    });

    test('throws on closed client', () {
      final client = D1Client(
        accountId: accountId,
        databaseId: databaseId,
        apiToken: apiToken,
        httpClient: MockClient((_) async => queryOk([])),
      );
      client.close();
      expect(() => client.raw('SELECT 1'), throwsStateError);
    });
  });

  group('D1Client — QueryBuilder integration', () {
    test(
      'queryBuilder produces D1-compatible SQL (double-quote, ? params)',
      () async {
        String? capturedSql;

        final client = D1Client(
          accountId: accountId,
          databaseId: databaseId,
          apiToken: apiToken,
          httpClient: MockClient((request) async {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            capturedSql = body['sql'] as String;
            return queryOk([]);
          }),
        );

        final db = KnexD1(
          accountId: accountId,
          databaseId: databaseId,
          apiToken: apiToken,
        );

        final compiled = db
            .queryBuilder()
            .from('users')
            .where('active', '=', 1)
            .select(['id', 'email'])
            .toSQL();

        await client.raw(compiled.sql, compiled.bindings);

        expect(capturedSql, contains('"users"'));
        expect(capturedSql, contains('"id"'));
        expect(capturedSql, contains('?'));
        client.close();
        db.close();
      },
    );
  });

  group('D1Client — binding types', () {
    Future<List<dynamic>> captureParams(List<dynamic> bindings) async {
      late List<dynamic> captured;
      final client = D1Client(
        accountId: accountId,
        databaseId: databaseId,
        apiToken: apiToken,
        httpClient: MockClient((request) async {
          captured =
              (jsonDecode(request.body) as Map<String, dynamic>)['params']
                  as List<dynamic>;
          return queryOk([]);
        }),
      );
      await client.raw('SELECT ?', bindings);
      client.close();
      return captured;
    }

    test('int passes through as-is', () async {
      expect((await captureParams([42])).first, 42);
    });

    test('double passes through as-is', () async {
      expect(
        ((await captureParams([3.14])).first as num).toDouble(),
        closeTo(3.14, 0.001),
      );
    });

    test('String passes through as-is', () async {
      expect((await captureParams(['hello'])).first, 'hello');
    });

    test('bool true → 1', () async {
      expect((await captureParams([true])).first, 1);
    });

    test('bool false → 0', () async {
      expect((await captureParams([false])).first, 0);
    });

    test('null passes through as null', () async {
      expect((await captureParams([null])).first, isNull);
    });

    test('multiple bindings of different types', () async {
      final params = await captureParams([1, 'name', true, null, 3.14]);
      expect(params[0], 1);
      expect(params[1], 'name');
      expect(params[2], 1); // true → 1
      expect(params[3], isNull);
      expect((params[4] as num).toDouble(), closeTo(3.14, 0.001));
    });
  });

  group('D1Client — batch with params', () {
    test('batch statements include their params', () async {
      Map<String, dynamic>? capturedBody;
      final client = D1Client(
        accountId: accountId,
        databaseId: databaseId,
        apiToken: apiToken,
        httpClient: MockClient((request) async {
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return batchOk([[], []]);
        }),
      );
      await client.batch((b) {
        b.addRaw('INSERT INTO users (id, name) VALUES (?, ?)', [1, 'Alice']);
        b.addRaw('INSERT INTO users (id, name) VALUES (?, ?)', [2, 'Bob']);
      });
      final stmts = capturedBody!['statements'] as List<dynamic>;
      expect((stmts.first as Map)['params'], [1, 'Alice']);
      expect((stmts.last as Map)['params'], [2, 'Bob']);
      client.close();
    });

    test('batch statement without params omits params key', () async {
      Map<String, dynamic>? capturedBody;
      final client = D1Client(
        accountId: accountId,
        databaseId: databaseId,
        apiToken: apiToken,
        httpClient: MockClient((request) async {
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return batchOk([[]]);
        }),
      );
      await client.batch((b) {
        b.addRaw('SELECT 1');
      });
      final stmt = (capturedBody!['statements'] as List).first as Map;
      expect(stmt.containsKey('params'), isFalse);
      client.close();
    });
  });

  group('D1Client — error handling extended', () {
    test('throws on 403 Forbidden', () async {
      final client = D1Client(
        accountId: accountId,
        databaseId: databaseId,
        apiToken: apiToken,
        httpClient: MockClient((_) async => http.Response('Forbidden', 403)),
      );
      expect(() => client.raw('SELECT 1'), throwsA(isA<StateError>()));
      client.close();
    });

    test('throws on 429 Too Many Requests', () async {
      final client = D1Client(
        accountId: accountId,
        databaseId: databaseId,
        apiToken: apiToken,
        httpClient: MockClient(
          (_) async => http.Response('Too Many Requests', 429),
        ),
      );
      expect(() => client.raw('SELECT 1'), throwsA(isA<StateError>()));
      client.close();
    });

    test('error message contains D1 error details', () async {
      final client = D1Client(
        accountId: accountId,
        databaseId: databaseId,
        apiToken: apiToken,
        httpClient: MockClient(
          (_) async => apiError('SQLITE_CONSTRAINT: UNIQUE constraint failed'),
        ),
      );
      expect(
        () => client.raw('INSERT INTO users VALUES (1)'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('UNIQUE constraint'),
          ),
        ),
      );
      client.close();
    });
  });

  group('D1Client — INSERT / UPDATE via QueryBuilder', () {
    test('INSERT generates correct SQL shape', () async {
      String? capturedSql;
      final client = D1Client(
        accountId: accountId,
        databaseId: databaseId,
        apiToken: apiToken,
        httpClient: MockClient((request) async {
          capturedSql =
              (jsonDecode(request.body) as Map<String, dynamic>)['sql']
                  as String;
          return queryOk([]);
        }),
      );
      final db = KnexD1(
        accountId: accountId,
        databaseId: databaseId,
        apiToken: apiToken,
      );
      final compiled = db.queryBuilder().table('users').insert({
        'name': 'Alice',
        'score': 9.5,
      }).toSQL();
      await client.raw(compiled.sql, compiled.bindings);
      expect(capturedSql, contains('insert into'));
      expect(capturedSql, contains('"users"'));
      client.close();
      db.close();
    });

    test('UPDATE generates correct SQL shape with params', () async {
      String? capturedSql;
      List<dynamic>? capturedParams;
      final client = D1Client(
        accountId: accountId,
        databaseId: databaseId,
        apiToken: apiToken,
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          capturedSql = body['sql'] as String;
          capturedParams = body['params'] as List<dynamic>?;
          return queryOk([]);
        }),
      );
      final db = KnexD1(
        accountId: accountId,
        databaseId: databaseId,
        apiToken: apiToken,
      );
      final compiled = db
          .queryBuilder()
          .table('users')
          .where('id', '=', 1)
          .update({'score': 10.0})
          .toSQL();
      await client.raw(compiled.sql, compiled.bindings);
      expect(capturedSql, contains('update'));
      expect(capturedSql, contains('"users"'));
      expect(capturedParams, isNotNull);
      client.close();
      db.close();
    });
  });

  group('D1Client — QueryBuilder joins', () {
    test('INNER JOIN SQL shape', () async {
      String? capturedSql;

      final client = D1Client(
        accountId: accountId,
        databaseId: databaseId,
        apiToken: apiToken,
        httpClient: MockClient((request) async {
          capturedSql =
              (jsonDecode(request.body) as Map<String, dynamic>)['sql']
                  as String;
          return queryOk([]);
        }),
      );
      final db = KnexD1(
        accountId: accountId,
        databaseId: databaseId,
        apiToken: apiToken,
      );

      final compiled = db
          .queryBuilder()
          .from('users')
          .join('accounts', 'users.id', 'accounts.user_id')
          .select(['users.id', 'accounts.balance'])
          .toSQL();

      await client.raw(compiled.sql, compiled.bindings);

      final sql = capturedSql!.toLowerCase();
      expect(sql, contains('from "users"'));
      expect(sql, contains('join "accounts"'));
      expect(sql, contains('"users"."id"'));
      expect(sql, contains('"accounts"."user_id"'));
      client.close();
      db.close();
    });

    test('LEFT JOIN SQL shape', () async {
      String? capturedSql;

      final client = D1Client(
        accountId: accountId,
        databaseId: databaseId,
        apiToken: apiToken,
        httpClient: MockClient((request) async {
          capturedSql =
              (jsonDecode(request.body) as Map<String, dynamic>)['sql']
                  as String;
          return queryOk([]);
        }),
      );
      final db = KnexD1(
        accountId: accountId,
        databaseId: databaseId,
        apiToken: apiToken,
      );

      final compiled = db
          .queryBuilder()
          .from('users')
          .leftJoin('accounts', 'users.id', 'accounts.user_id')
          .select(['users.id', 'accounts.balance'])
          .toSQL();

      await client.raw(compiled.sql, compiled.bindings);

      final sql = capturedSql!.toLowerCase();
      expect(sql, contains('left join "accounts"'));
      expect(sql, contains('"users"."id"'));
      expect(sql, contains('"accounts"."user_id"'));
      client.close();
      db.close();
    });
  });

  group('D1Client — QueryBuilder ordering and pagination', () {
    test('orderBy + limit + offset SQL shape', () async {
      String? capturedSql;

      final client = D1Client(
        accountId: accountId,
        databaseId: databaseId,
        apiToken: apiToken,
        httpClient: MockClient((request) async {
          capturedSql =
              (jsonDecode(request.body) as Map<String, dynamic>)['sql']
                  as String;
          return queryOk([]);
        }),
      );
      final db = KnexD1(
        accountId: accountId,
        databaseId: databaseId,
        apiToken: apiToken,
      );

      final compiled = db
          .queryBuilder()
          .from('users')
          .select(['id'])
          .orderBy('id', 'desc')
          .limit(5)
          .offset(10)
          .toSQL();

      await client.raw(compiled.sql, compiled.bindings);

      final sql = capturedSql!.toLowerCase();
      expect(sql, contains('order by "id" desc'));
      expect(sql, contains('limit ?'));
      expect(sql, contains('offset ?'));
      expect(compiled.bindings, containsAll([5, 10]));
      client.close();
      db.close();
    });
  });

  group('D1Client — QueryBuilder delete', () {
    test('delete SQL shape', () async {
      String? capturedSql;
      List<dynamic>? capturedParams;

      final client = D1Client(
        accountId: accountId,
        databaseId: databaseId,
        apiToken: apiToken,
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          capturedSql = body['sql'] as String;
          capturedParams = body['params'] as List<dynamic>?;
          return queryOk([]);
        }),
      );
      final db = KnexD1(
        accountId: accountId,
        databaseId: databaseId,
        apiToken: apiToken,
      );

      final compiled = db
          .queryBuilder()
          .table('users')
          .where('id', '=', 7)
          .delete()
          .toSQL();

      await client.raw(compiled.sql, compiled.bindings);

      final sql = capturedSql!.toLowerCase();
      expect(sql, contains('delete from "users"'));
      expect(sql, contains('where "id" = ?'));
      expect(capturedParams, [7]);
      client.close();
      db.close();
    });
  });

  group('D1Client — QueryBuilder groupBy and having', () {
    test('groupBy + havingRaw SQL shape', () async {
      String? capturedSql;
      List<dynamic>? capturedParams;

      final client = D1Client(
        accountId: accountId,
        databaseId: databaseId,
        apiToken: apiToken,
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          capturedSql = body['sql'] as String;
          capturedParams = body['params'] as List<dynamic>?;
          return queryOk([]);
        }),
      );
      final db = KnexD1(
        accountId: accountId,
        databaseId: databaseId,
        apiToken: apiToken,
      );

      final compiled = db
          .queryBuilder()
          .from('accounts')
          .select(['user_id'])
          .groupBy('user_id')
          .havingRaw('count(*) > ?', [1])
          .toSQL();

      await client.raw(compiled.sql, compiled.bindings);

      final sql = capturedSql!.toLowerCase();
      expect(sql, contains('group by "user_id"'));
      expect(sql, contains('having count(*) > ?'));
      expect(capturedParams, [1]);
      client.close();
      db.close();
    });
  });

  group('D1Client — QueryBuilder distinct', () {
    test('distinct SQL shape', () async {
      String? capturedSql;

      final client = D1Client(
        accountId: accountId,
        databaseId: databaseId,
        apiToken: apiToken,
        httpClient: MockClient((request) async {
          capturedSql =
              (jsonDecode(request.body) as Map<String, dynamic>)['sql']
                  as String;
          return queryOk([]);
        }),
      );
      final db = KnexD1(
        accountId: accountId,
        databaseId: databaseId,
        apiToken: apiToken,
      );

      final compiled = db.queryBuilder().from('users').distinct([
        'first_name',
      ]).toSQL();

      await client.raw(compiled.sql, compiled.bindings);

      final sql = capturedSql!.toLowerCase();
      expect(sql, contains('select distinct'));
      expect(sql, contains('"first_name"'));
      expect(sql, contains('from "users"'));
      client.close();
      db.close();
    });
  });

  group('D1Client — QueryBuilder whereNotIn', () {
    test('whereNotIn SQL shape', () async {
      String? capturedSql;
      List<dynamic>? capturedParams;

      final client = D1Client(
        accountId: accountId,
        databaseId: databaseId,
        apiToken: apiToken,
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          capturedSql = body['sql'] as String;
          capturedParams = body['params'] as List<dynamic>?;
          return queryOk([]);
        }),
      );
      final db = KnexD1(
        accountId: accountId,
        databaseId: databaseId,
        apiToken: apiToken,
      );

      final compiled = db.queryBuilder().from('users').whereNotIn(
        'first_name',
        ['Alice', 'Bob'],
      ).toSQL();

      await client.raw(compiled.sql, compiled.bindings);

      final sql = capturedSql!.toLowerCase();
      expect(sql, contains('"first_name" not in (?, ?)'));
      expect(capturedParams, ['Alice', 'Bob']);
      client.close();
      db.close();
    });
  });

  group('D1Client — D1BatchBuilder add(QueryBuilder)', () {
    test('batch add(QueryBuilder insert) sends compiled SQL', () async {
      Map<String, dynamic>? capturedBody;

      final client = D1Client(
        accountId: accountId,
        databaseId: databaseId,
        apiToken: apiToken,
        httpClient: MockClient((request) async {
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return batchOk([[]]);
        }),
      );
      final db = KnexD1(
        accountId: accountId,
        databaseId: databaseId,
        apiToken: apiToken,
      );

      await client.batch((b) {
        b.add(
          db.queryBuilder().table('users').insert({
            'id': 1,
            'first_name': 'Alice',
          }),
        );
      });

      final stmts = capturedBody!['statements'] as List<dynamic>;
      final stmt = stmts.first as Map<String, dynamic>;
      final sql = (stmt['sql'] as String).toLowerCase();
      expect(stmts, hasLength(1));
      expect(sql, contains('insert into "users"'));
      expect(stmt['params'], containsAll([1, 'Alice']));
      client.close();
      db.close();
    });
  });
}
