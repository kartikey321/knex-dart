import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:knex_dart_snowflake/knex_dart_snowflake.dart';
import 'package:test/test.dart';

// ─── Response helpers ─────────────────────────────────────────────────────────

http.Response snowflakeOk({
  List<Map<String, dynamic>> rowType = const [],
  List<List<String?>> data = const [],
}) {
  return http.Response(
    jsonEncode({
      'code': '090001',
      'statementHandle': 'test-handle-1234',
      'resultSetMetaData': {'numRows': data.length, 'rowType': rowType},
      'data': data,
    }),
    200,
    headers: {'content-type': 'application/json'},
  );
}

http.Response snowflakeError(String code, String message) {
  return http.Response(
    jsonEncode({'code': code, 'message': message, 'sqlState': '42S02'}),
    200,
    headers: {'content-type': 'application/json'},
  );
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  const account = 'myorg-myaccount';
  const token = 'test-oauth-token';

  group('SnowflakeClient — wire format', () {
    test('sends Bearer Authorization header', () async {
      String? capturedAuth;

      final client = SnowflakeClient(
        account: account,
        token: token,
        httpClient: MockClient((request) async {
          capturedAuth = request.headers['Authorization'];
          return snowflakeOk();
        }),
      );

      await client.raw('SELECT 1');
      expect(capturedAuth, 'Bearer test-oauth-token');
      client.close();
    });

    test('sends SQL in request body', () async {
      Map<String, dynamic>? capturedBody;

      final client = SnowflakeClient(
        account: account,
        token: token,
        httpClient: MockClient((request) async {
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return snowflakeOk();
        }),
      );

      await client.raw('SELECT * FROM ORDERS WHERE STATUS = ?', ['open']);
      expect(
        capturedBody!['statement'],
        'SELECT * FROM ORDERS WHERE STATUS = ?',
      );
      client.close();
    });

    test('sets async: false by default', () async {
      Map<String, dynamic>? capturedBody;

      final client = SnowflakeClient(
        account: account,
        token: token,
        httpClient: MockClient((request) async {
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return snowflakeOk();
        }),
      );

      await client.raw('SELECT 1');
      expect(capturedBody!['async'], isFalse);
      client.close();
    });

    test('includes database/schema/warehouse/role when provided', () async {
      Map<String, dynamic>? capturedBody;

      final client = SnowflakeClient(
        account: account,
        token: token,
        database: 'MY_DB',
        schema: 'PUBLIC',
        warehouse: 'COMPUTE_WH',
        role: 'ANALYST',
        httpClient: MockClient((request) async {
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return snowflakeOk();
        }),
      );

      await client.raw('SELECT 1');
      expect(capturedBody!['database'], 'MY_DB');
      expect(capturedBody!['schema'], 'PUBLIC');
      expect(capturedBody!['warehouse'], 'COMPUTE_WH');
      expect(capturedBody!['role'], 'ANALYST');
      client.close();
    });
  });

  group('SnowflakeClient — binding serialization', () {
    Future<Map<String, dynamic>> captureBindings(dynamic value) async {
      late Map<String, dynamic> capturedBindings;

      final client = SnowflakeClient(
        account: account,
        token: token,
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          capturedBindings =
              (body['bindings'] as Map<String, dynamic>)['1']
                  as Map<String, dynamic>;
          return snowflakeOk();
        }),
      );

      await client.raw('SELECT ?', [value]);
      client.close();
      return capturedBindings;
    }

    test('int → FIXED type', () async {
      final binding = await captureBindings(42);
      expect(binding['type'], 'FIXED');
      expect(binding['value'], '42');
    });

    test('double → REAL type', () async {
      final binding = await captureBindings(3.14);
      expect(binding['type'], 'REAL');
      expect(binding['value'], '3.14');
    });

    test('bool → BOOLEAN type', () async {
      final binding = await captureBindings(true);
      expect(binding['type'], 'BOOLEAN');
      expect(binding['value'], 'true');
    });

    test('String → TEXT type', () async {
      final binding = await captureBindings('hello');
      expect(binding['type'], 'TEXT');
      expect(binding['value'], 'hello');
    });

    test('uses 1-based keys for multiple bindings', () async {
      Map<String, dynamic>? capturedBindings;

      final client = SnowflakeClient(
        account: account,
        token: token,
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          capturedBindings = body['bindings'] as Map<String, dynamic>;
          return snowflakeOk();
        }),
      );

      await client.raw('SELECT ?, ?', ['a', 'b']);
      expect(capturedBindings!.keys.toList(), containsAll(['1', '2']));
      client.close();
    });
  });

  group('SnowflakeClient — response parsing', () {
    test('parses rowType + data into row maps', () async {
      final client = SnowflakeClient(
        account: account,
        token: token,
        httpClient: MockClient(
          (_) async => snowflakeOk(
            rowType: [
              {'name': 'ID', 'type': 'fixed'},
              {'name': 'NAME', 'type': 'text'},
              {'name': 'SCORE', 'type': 'real'},
            ],
            data: [
              ['1', 'Alice', '9.5'],
              ['2', 'Bob', '7.0'],
            ],
          ),
        ),
      );

      final rows = await client.raw('SELECT * FROM USERS');
      expect(rows, hasLength(2));
      expect(rows.first['NAME'], 'Alice');
      expect(rows.first['ID'], '1'); // Snowflake returns all as strings
      expect(rows.last['SCORE'], '7.0');
      client.close();
    });

    test('returns empty list when data is null/absent', () async {
      final client = SnowflakeClient(
        account: account,
        token: token,
        httpClient: MockClient((_) async => snowflakeOk()),
      );

      final rows = await client.raw('INSERT INTO users VALUES (1)');
      expect(rows, isEmpty);
      client.close();
    });
  });

  group('SnowflakeClient — error handling', () {
    test('throws on non-200 HTTP status', () async {
      final client = SnowflakeClient(
        account: account,
        token: token,
        httpClient: MockClient(
          (_) async => http.Response('Service Unavailable', 503),
        ),
      );

      expect(() => client.raw('SELECT 1'), throwsA(isA<StateError>()));
      client.close();
    });

    test('throws on Snowflake API error code', () async {
      final client = SnowflakeClient(
        account: account,
        token: token,
        httpClient: MockClient(
          (_) async => snowflakeError('002003', 'SQL compilation error'),
        ),
      );

      expect(
        () => client.raw('SELECT * FROM nonexistent'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('002003'),
          ),
        ),
      );
      client.close();
    });

    test('returns 202 as empty (async accepted)', () async {
      final client = SnowflakeClient(
        account: account,
        token: token,
        asyncExecution: true,
        httpClient: MockClient(
          (_) async =>
              http.Response(jsonEncode({'statementHandle': 'handle-xyz'}), 202),
        ),
      );

      final rows = await client.raw('SELECT * FROM LARGE_TABLE');
      expect(rows, isEmpty); // caller should poll getAsyncResult
      client.close();
    });

    test('throws on closed client', () {
      final client = SnowflakeClient(
        account: account,
        token: token,
        httpClient: MockClient((_) async => snowflakeOk()),
      );
      client.close();
      expect(() => client.raw('SELECT 1'), throwsStateError);
    });
  });

  group('SnowflakeClient — QueryBuilder integration', () {
    test('queryBuilder produces Snowflake-compatible SQL', () {
      final db = KnexSnowflake(account: account, token: token);
      final compiled = db
          .queryBuilder()
          .from('SALES')
          .where('REGION', '=', 'EMEA')
          .select(['ORDER_ID', 'AMOUNT'])
          .toSQL();

      expect(compiled.sql, contains('"SALES"'));
      expect(compiled.sql, contains('"ORDER_ID"'));
      expect(compiled.sql, contains('?'));
      expect(compiled.bindings, ['EMEA']);
      db.close();
    });
  });

  group('SnowflakeClient — binding types extended', () {
    test(
      'multiple bindings have sequential 1-based keys with correct types',
      () async {
        Map<String, dynamic>? capturedBindings;
        final client = SnowflakeClient(
          account: account,
          token: token,
          httpClient: MockClient((request) async {
            capturedBindings =
                (jsonDecode(request.body) as Map<String, dynamic>)['bindings']
                    as Map<String, dynamic>;
            return snowflakeOk();
          }),
        );
        await client.raw('SELECT ?, ?, ?', [10, 'hello', true]);
        expect(capturedBindings!.keys.toSet(), {'1', '2', '3'});
        expect(capturedBindings!['1']['type'], 'FIXED');
        expect(capturedBindings!['2']['type'], 'TEXT');
        expect(capturedBindings!['3']['type'], 'BOOLEAN');
        client.close();
      },
    );

    test('omits bindings key when no bindings provided', () async {
      Map<String, dynamic>? capturedBody;
      final client = SnowflakeClient(
        account: account,
        token: token,
        httpClient: MockClient((request) async {
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return snowflakeOk();
        }),
      );
      await client.raw('SELECT 1');
      expect(capturedBody!.containsKey('bindings'), isFalse);
      client.close();
    });
  });

  group('SnowflakeClient — response parsing extended', () {
    test('parses multiple rows correctly', () async {
      final client = SnowflakeClient(
        account: account,
        token: token,
        httpClient: MockClient(
          (_) async => snowflakeOk(
            rowType: [
              {'name': 'ID', 'type': 'fixed'},
              {'name': 'NAME', 'type': 'text'},
            ],
            data: [
              ['1', 'Alice'],
              ['2', 'Bob'],
              ['3', 'Carol'],
            ],
          ),
        ),
      );
      final rows = await client.raw('SELECT ID, NAME FROM USERS');
      expect(rows, hasLength(3));
      expect(rows.map((r) => r['NAME']).toList(), ['Alice', 'Bob', 'Carol']);
      client.close();
    });

    test('null cell in data returns null in Dart', () async {
      final client = SnowflakeClient(
        account: account,
        token: token,
        httpClient: MockClient(
          (_) async => snowflakeOk(
            rowType: [
              {'name': 'ID', 'type': 'fixed'},
              {'name': 'SCORE', 'type': 'real'},
            ],
            data: [
              ['1', null],
            ],
          ),
        ),
      );
      final rows = await client.raw('SELECT ID, SCORE FROM USERS');
      expect(rows.first['SCORE'], isNull);
      client.close();
    });
  });

  group('SnowflakeClient — error handling extended', () {
    test('throws on 401 Unauthorized', () async {
      final client = SnowflakeClient(
        account: account,
        token: token,
        httpClient: MockClient((_) async => http.Response('Unauthorized', 401)),
      );
      expect(() => client.raw('SELECT 1'), throwsA(isA<StateError>()));
      client.close();
    });

    test('error message includes Snowflake error code', () async {
      final client = SnowflakeClient(
        account: account,
        token: token,
        httpClient: MockClient(
          (_) async => snowflakeError('000904', 'invalid identifier'),
        ),
      );
      expect(
        () => client.raw('SELECT NOSUCHCOL FROM T'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('000904'),
          ),
        ),
      );
      client.close();
    });
  });

  group('SnowflakeClient — QueryBuilder extended', () {
    test('INSERT query structure', () {
      final db = KnexSnowflake(account: account, token: token);
      final compiled = db.queryBuilder().table('ORDERS').insert({
        'PRODUCT': 'Widget',
        'AMOUNT': 9.99,
      }).toSQL();
      expect(compiled.sql, contains('insert into'));
      expect(compiled.sql, contains('"ORDERS"'));
      expect(compiled.bindings, containsAll(['Widget', 9.99]));
      db.close();
    });

    test('UPDATE query structure', () {
      final db = KnexSnowflake(account: account, token: token);
      final compiled = db
          .queryBuilder()
          .table('ORDERS')
          .where('ID', '=', 1)
          .update({'STATUS': 'shipped'})
          .toSQL();
      expect(compiled.sql, contains('update'));
      expect(compiled.sql, contains('set'));
      expect(compiled.bindings, containsAll(['shipped', 1]));
      db.close();
    });

    test('WHERE with multiple conditions generates AND', () {
      final db = KnexSnowflake(account: account, token: token);
      final compiled = db
          .queryBuilder()
          .from('SALES')
          .where('REGION', 'EMEA')
          .where('YEAR', '=', 2024)
          .toSQL();
      expect(compiled.sql, contains('and'));
      expect(compiled.bindings, containsAll(['EMEA', 2024]));
      db.close();
    });
  });

  group('SnowflakeClient — QueryBuilder joins', () {
    test('INNER JOIN SQL shape', () async {
      String? capturedStatement;

      final client = SnowflakeClient(
        account: account,
        token: token,
        httpClient: MockClient((request) async {
          capturedStatement =
              (jsonDecode(request.body) as Map<String, dynamic>)['statement']
                  as String;
          return snowflakeOk();
        }),
      );
      final db = KnexSnowflake(account: account, token: token);

      final compiled = db
          .queryBuilder()
          .from('ORDERS')
          .join('USERS', 'ORDERS.USER_ID', 'USERS.ID')
          .select(['ORDERS.ID', 'USERS.NAME'])
          .toSQL();
      await client.raw(compiled.sql, compiled.bindings);

      final sql = capturedStatement!.toLowerCase();
      expect(sql, contains('from "orders"'));
      expect(sql, contains('join "users"'));
      expect(sql, contains('"orders"."user_id"'));
      expect(sql, contains('"users"."id"'));
      client.close();
      db.close();
    });

    test('LEFT JOIN SQL shape', () async {
      String? capturedStatement;

      final client = SnowflakeClient(
        account: account,
        token: token,
        httpClient: MockClient((request) async {
          capturedStatement =
              (jsonDecode(request.body) as Map<String, dynamic>)['statement']
                  as String;
          return snowflakeOk();
        }),
      );
      final db = KnexSnowflake(account: account, token: token);

      final compiled = db
          .queryBuilder()
          .from('USERS')
          .leftJoin('ORDERS', 'USERS.ID', 'ORDERS.USER_ID')
          .select(['USERS.NAME', 'ORDERS.AMOUNT'])
          .toSQL();
      await client.raw(compiled.sql, compiled.bindings);

      final sql = capturedStatement!.toLowerCase();
      expect(sql, contains('left join "orders"'));
      expect(sql, contains('"users"."id"'));
      expect(sql, contains('"orders"."user_id"'));
      client.close();
      db.close();
    });
  });

  group('SnowflakeClient — QueryBuilder ordering and pagination', () {
    test('orderBy + limit + offset SQL shape', () async {
      String? capturedStatement;

      final client = SnowflakeClient(
        account: account,
        token: token,
        httpClient: MockClient((request) async {
          capturedStatement =
              (jsonDecode(request.body) as Map<String, dynamic>)['statement']
                  as String;
          return snowflakeOk();
        }),
      );
      final db = KnexSnowflake(account: account, token: token);

      final compiled = db
          .queryBuilder()
          .from('ORDERS')
          .select(['ID'])
          .orderBy('CREATED_AT', 'desc')
          .limit(10)
          .offset(5)
          .toSQL();
      await client.raw(compiled.sql, compiled.bindings);

      final sql = capturedStatement!.toLowerCase();
      expect(sql, contains('order by "created_at" desc'));
      expect(sql, contains('limit ?'));
      expect(sql, contains('offset ?'));
      expect(compiled.bindings, containsAll([10, 5]));
      client.close();
      db.close();
    });
  });

  group('SnowflakeClient — QueryBuilder delete', () {
    test('delete SQL shape', () async {
      String? capturedStatement;
      Map<String, dynamic>? capturedBindings;

      final client = SnowflakeClient(
        account: account,
        token: token,
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          capturedStatement = body['statement'] as String;
          capturedBindings = body['bindings'] as Map<String, dynamic>?;
          return snowflakeOk();
        }),
      );
      final db = KnexSnowflake(account: account, token: token);

      final compiled = db
          .queryBuilder()
          .table('ORDERS')
          .where('ID', '=', 7)
          .delete()
          .toSQL();
      await client.raw(compiled.sql, compiled.bindings);

      final sql = capturedStatement!.toLowerCase();
      expect(sql, contains('delete from "orders"'));
      expect(sql, contains('where "id" = ?'));
      expect(capturedBindings!['1']['value'], '7');
      client.close();
      db.close();
    });
  });

  group('SnowflakeClient — QueryBuilder groupBy and having', () {
    test('groupBy + havingRaw SQL shape', () async {
      String? capturedStatement;
      Map<String, dynamic>? capturedBindings;

      final client = SnowflakeClient(
        account: account,
        token: token,
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          capturedStatement = body['statement'] as String;
          capturedBindings = body['bindings'] as Map<String, dynamic>?;
          return snowflakeOk();
        }),
      );
      final db = KnexSnowflake(account: account, token: token);

      final compiled = db
          .queryBuilder()
          .from('ORDERS')
          .select(['USER_ID'])
          .groupBy('USER_ID')
          .havingRaw('count(*) > ?', [1])
          .toSQL();
      await client.raw(compiled.sql, compiled.bindings);

      final sql = capturedStatement!.toLowerCase();
      expect(sql, contains('group by "user_id"'));
      expect(sql, contains('having count(*) > ?'));
      expect(capturedBindings!['1']['value'], '1');
      client.close();
      db.close();
    });
  });

  group('SnowflakeClient — QueryBuilder distinct', () {
    test('distinct SQL shape', () async {
      String? capturedStatement;

      final client = SnowflakeClient(
        account: account,
        token: token,
        httpClient: MockClient((request) async {
          capturedStatement =
              (jsonDecode(request.body) as Map<String, dynamic>)['statement']
                  as String;
          return snowflakeOk();
        }),
      );
      final db = KnexSnowflake(account: account, token: token);

      final compiled = db.queryBuilder().from('ORDERS').distinct([
        'USER_ID',
      ]).toSQL();
      await client.raw(compiled.sql, compiled.bindings);

      final sql = capturedStatement!.toLowerCase();
      expect(sql, contains('select distinct'));
      expect(sql, contains('"user_id"'));
      expect(sql, contains('from "orders"'));
      client.close();
      db.close();
    });
  });

  group('SnowflakeClient — QueryBuilder whereNotIn', () {
    test('whereNotIn SQL shape', () async {
      String? capturedStatement;
      Map<String, dynamic>? capturedBindings;

      final client = SnowflakeClient(
        account: account,
        token: token,
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          capturedStatement = body['statement'] as String;
          capturedBindings = body['bindings'] as Map<String, dynamic>?;
          return snowflakeOk();
        }),
      );
      final db = KnexSnowflake(account: account, token: token);

      final compiled = db.queryBuilder().from('USERS').whereNotIn('NAME', [
        'Alice',
        'Bob',
      ]).toSQL();
      await client.raw(compiled.sql, compiled.bindings);

      final sql = capturedStatement!.toLowerCase();
      expect(sql, contains('"name" not in (?, ?)'));
      expect(capturedBindings!['1']['value'], 'Alice');
      expect(capturedBindings!['2']['value'], 'Bob');
      client.close();
      db.close();
    });
  });

  group('SnowflakeClient — async execution', () {
    test('asyncExecution:true sends async:true in body', () async {
      Map<String, dynamic>? capturedBody;

      final client = SnowflakeClient(
        account: account,
        token: token,
        asyncExecution: true,
        httpClient: MockClient((request) async {
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return snowflakeOk();
        }),
      );

      await client.raw('SELECT 1');
      expect(capturedBody!['async'], isTrue);
      client.close();
    });

    test('202 Accepted returns empty list', () async {
      final client = SnowflakeClient(
        account: account,
        token: token,
        asyncExecution: true,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({'statementHandle': 'async-handle-1'}),
            202,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );

      final rows = await client.raw('SELECT * FROM LARGE_TABLE');
      expect(rows, isEmpty);
      client.close();
    });
  });
}
