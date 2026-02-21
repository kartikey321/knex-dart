import 'package:test/test.dart';
import 'package:knex_dart/src/query/query_builder.dart';
import '../mocks/mock_client.dart';

void main() {
  late MockClient client;

  setUp(() {
    client = MockClient();
  });

  group('Analytic / Window Functions - Comparison with Knex.js', () {
    test('Test 1: rank() - string orderBy, string partitionBy', () {
      final query = QueryBuilder(
        client,
      ).table('users').select(['*']).rank('alias_name', 'email', 'firstName');
      final sql = query.toSQL();

      // JS: select *, rank() over (partition by "firstName" order by "email") as alias_name from "users"
      expect(
        sql.sql,
        'select *, rank() over (partition by "firstName" order by "email") as alias_name from "users"',
      );
      expect(sql.bindings, isEmpty);
    });

    test('Test 2: rank() - array orderBy, array partitionBy', () {
      final query = QueryBuilder(client)
          .table('users')
          .select(['*'])
          .rank('alias_name', ['email', 'address'], ['firstName', 'lastName']);
      final sql = query.toSQL();

      // JS: select *, rank() over (partition by "firstName", "lastName" order by "email", "address") as alias_name from "users"
      expect(
        sql.sql,
        'select *, rank() over (partition by "firstName", "lastName" order by "email", "address") as alias_name from "users"',
      );
      expect(sql.bindings, isEmpty);
    });

    test('Test 3: rank() - string orderBy only (no partitionBy)', () {
      final query = QueryBuilder(
        client,
      ).table('users').select(['*']).rank('alias_name', 'email');
      final sql = query.toSQL();

      // JS: select *, rank() over (order by "email") as alias_name from "users"
      expect(
        sql.sql,
        'select *, rank() over (order by "email") as alias_name from "users"',
      );
      expect(sql.bindings, isEmpty);
    });

    test('Test 4: denseRank() - string orderBy, string partitionBy', () {
      final query = QueryBuilder(client)
          .table('users')
          .select(['*'])
          .denseRank('alias_name', 'email', 'firstName');
      final sql = query.toSQL();

      // JS: select *, dense_rank() over (partition by "firstName" order by "email") as alias_name from "users"
      expect(
        sql.sql,
        'select *, dense_rank() over (partition by "firstName" order by "email") as alias_name from "users"',
      );
      expect(sql.bindings, isEmpty);
    });

    test('Test 5: denseRank() - array orderBy, array partitionBy', () {
      final query = QueryBuilder(client)
          .table('users')
          .select(['*'])
          .denseRank(
            'alias_name',
            ['email', 'address'],
            ['firstName', 'lastName'],
          );
      final sql = query.toSQL();

      // JS: select *, dense_rank() over (partition by "firstName", "lastName" order by "email", "address") as alias_name from "users"
      expect(
        sql.sql,
        'select *, dense_rank() over (partition by "firstName", "lastName" order by "email", "address") as alias_name from "users"',
      );
      expect(sql.bindings, isEmpty);
    });

    test('Test 6: rowNumber() - string orderBy, string partitionBy', () {
      final query = QueryBuilder(client)
          .table('users')
          .select(['*'])
          .rowNumber('alias_name', 'email', 'firstName');
      final sql = query.toSQL();

      // JS: select *, row_number() over (partition by "firstName" order by "email") as alias_name from "users"
      expect(
        sql.sql,
        'select *, row_number() over (partition by "firstName" order by "email") as alias_name from "users"',
      );
      expect(sql.bindings, isEmpty);
    });

    test('Test 7: rowNumber() - array orderBy, array partitionBy', () {
      final query = QueryBuilder(client)
          .table('users')
          .select(['*'])
          .rowNumber(
            'alias_name',
            ['email', 'address'],
            ['firstName', 'lastName'],
          );
      final sql = query.toSQL();

      // JS: select *, row_number() over (partition by "firstName", "lastName" order by "email", "address") as alias_name from "users"
      expect(
        sql.sql,
        'select *, row_number() over (partition by "firstName", "lastName" order by "email", "address") as alias_name from "users"',
      );
      expect(sql.bindings, isEmpty);
    });

    test('Test 8: rowNumber() - raw OVER clause', () {
      final query = QueryBuilder(client)
          .table('users')
          .select(['*'])
          .rowNumber('alias_name', client.raw('order by ?? desc', ['salary']));
      final sql = query.toSQL();

      // JS: select *, row_number() over (order by "salary" desc) as alias_name from "users"
      expect(
        sql.sql,
        'select *, row_number() over (order by "salary" desc) as alias_name from "users"',
      );
      expect(sql.bindings, isEmpty);
    });

    test('Test 9: rowNumber() - callback with orderBy + partitionBy', () {
      final query = QueryBuilder(client).table('users').select(['*']).rowNumber(
        'alias_name',
        (a) {
          a.orderBy('email').partitionBy('firstName');
        },
      );
      final sql = query.toSQL();

      // JS: select *, row_number() over (partition by "firstName" order by "email") as alias_name from "users"
      expect(
        sql.sql,
        'select *, row_number() over (partition by "firstName" order by "email") as alias_name from "users"',
      );
      expect(sql.bindings, isEmpty);
    });

    test('Test 10: rowNumber() - callback partitionBy with direction', () {
      final query = QueryBuilder(client).table('users').select(['*']).rowNumber(
        'alias_name',
        (a) {
          a.partitionBy('firstName', 'desc');
        },
      );
      final sql = query.toSQL();

      // JS: select *, row_number() over (partition by "firstName" desc order by ) as alias_name from "users"
      expect(
        sql.sql,
        'select *, row_number() over (partition by "firstName" desc order by ) as alias_name from "users"',
      );
      expect(sql.bindings, isEmpty);
    });

    test('Test 11: rowNumber() - callback partitionBy with multi-object', () {
      final query = QueryBuilder(client).table('users').select(['*']).rowNumber(
        'alias_name',
        (a) {
          a.partitionBy([
            {'column': 'firstName', 'order': 'asc'},
            {'column': 'lastName', 'order': 'desc'},
          ]);
        },
      );
      final sql = query.toSQL();

      // JS: select *, row_number() over (partition by "firstName" asc, "lastName" desc order by ) as alias_name from "users"
      expect(
        sql.sql,
        'select *, row_number() over (partition by "firstName" asc, "lastName" desc order by ) as alias_name from "users"',
      );
      expect(sql.bindings, isEmpty);
    });

    test('Test 12: rowNumber() - null alias', () {
      final query = QueryBuilder(
        client,
      ).table('users').select(['*']).rowNumber(null, 'email', 'firstName');
      final sql = query.toSQL();

      // JS: select *, row_number() over (partition by "firstName" order by "email") from "users"
      expect(
        sql.sql,
        'select *, row_number() over (partition by "firstName" order by "email") from "users"',
      );
      expect(sql.bindings, isEmpty);
    });

    test('Test 13: rowNumber() alongside regular columns', () {
      final query = QueryBuilder(client)
          .table('users')
          .select(['name', 'email'])
          .rowNumber('rn', 'salary', 'dept');
      final sql = query.toSQL();

      // JS: select "name", "email", row_number() over (partition by "dept" order by "salary") as rn from "users"
      expect(
        sql.sql,
        'select "name", "email", row_number() over (partition by "dept" order by "salary") as rn from "users"',
      );
      expect(sql.bindings, isEmpty);
    });

    test('Test 14: rank() with WHERE clause', () {
      final query = QueryBuilder(client)
          .table('users')
          .select(['*'])
          .rank('r', 'salary', 'dept')
          .where('active', true);
      final sql = query.toSQL();

      // JS: select *, rank() over (partition by "dept" order by "salary") as r from "users" where "active" = ?
      expect(
        sql.sql,
        'select *, rank() over (partition by "dept" order by "salary") as r from "users" where "active" = \$1',
      );
      expect(sql.bindings, [true]);
    });
  });
}
