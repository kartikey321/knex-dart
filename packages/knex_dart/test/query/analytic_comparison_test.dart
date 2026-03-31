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

  group('Value Window Functions (lead/lag/firstValue/lastValue/nthValue)', () {
    test('Test V1: lead() with string orderBy and partitionBy', () {
      final query = QueryBuilder(client)
          .table('employees')
          .select(['name', 'salary'])
          .lead('next_sal', 'salary', 'salary', 'dept');
      final sql = query.toSQL();

      expect(
        sql.sql,
        'select "name", "salary", lead("salary") over (partition by "dept" order by "salary") as next_sal from "employees"',
      );
      expect(sql.bindings, isEmpty);
    });

    test('Test V2: lead() with explicit offset and defaultVal — defaultVal is bound', () {
      final query = QueryBuilder(client)
          .table('employees')
          .select(['name', 'salary'])
          .lead('next_sal', 'salary', 'salary', 'dept', 1, 0);
      final sql = query.toSQL();

      // defaultVal 0 is emitted as a bound parameter (not interpolated)
      expect(
        sql.sql,
        'select "name", "salary", lead("salary", 1, \$1) over (partition by "dept" order by "salary") as next_sal from "employees"',
      );
      expect(sql.bindings, [0]);
    });

    test('Test V2b: lead() with string defaultVal — quotes/injection safe', () {
      final query = QueryBuilder(client)
          .table('employees')
          .select(['name'])
          .lead('next_name', 'name', 'created_at', null, 1, "O'Brien");
      final sql = query.toSQL();

      // String default is bound, never concatenated
      expect(sql.sql, contains("lead(\"name\", 1, \$1)"));
      expect(sql.bindings, ["O'Brien"]);
    });

    test('Test V3: lag() with no offset (string orderBy only)', () {
      final query = QueryBuilder(client)
          .table('employees')
          .select(['name'])
          .lag('prev_sal', 'salary', 'created_at');
      final sql = query.toSQL();

      expect(
        sql.sql,
        'select "name", lag("salary") over (order by "created_at") as prev_sal from "employees"',
      );
      expect(sql.bindings, isEmpty);
    });

    test('Test V4: lag() with explicit offset', () {
      final query = QueryBuilder(client)
          .table('employees')
          .select(['name'])
          .lag('prev2', 'salary', 'created_at', null, 2);
      final sql = query.toSQL();

      expect(
        sql.sql,
        'select "name", lag("salary", 2) over (order by "created_at") as prev2 from "employees"',
      );
      expect(sql.bindings, isEmpty);
    });

    test('Test V5: firstValue() with partition + orderBy', () {
      final query = QueryBuilder(client)
          .table('employees')
          .select(['name', 'salary'])
          .firstValue('first_sal', 'salary', 'salary', 'dept');
      final sql = query.toSQL();

      expect(
        sql.sql,
        'select "name", "salary", first_value("salary") over (partition by "dept" order by "salary") as first_sal from "employees"',
      );
      expect(sql.bindings, isEmpty);
    });

    test('Test V6: lastValue() with WindowSpec and frame clause', () {
      final win = WindowSpec()
          .partitionBy(['dept'])
          .orderBy('salary')
          .rowsBetween(
            WindowSpec.unboundedPreceding,
            WindowSpec.unboundedFollowing,
          );
      final query = QueryBuilder(client)
          .table('employees')
          .select(['name'])
          .lastValue('last_sal', 'salary', win);
      final sql = query.toSQL();

      expect(
        sql.sql,
        'select "name", last_value("salary") over (partition by "dept" order by "salary" asc rows between unbounded preceding and unbounded following) as last_sal from "employees"',
      );
      expect(sql.bindings, isEmpty);
    });

    test('Test V7: nthValue() with n=2 and partition + order', () {
      final query = QueryBuilder(client)
          .table('employees')
          .select(['name'])
          .nthValue('second_sal', 'salary', 2, 'salary', 'dept');
      final sql = query.toSQL();

      expect(
        sql.sql,
        'select "name", nth_value("salary", 2) over (partition by "dept" order by "salary") as second_sal from "employees"',
      );
      expect(sql.bindings, isEmpty);
    });

    test('Test V8: rowsBetween frame on firstValue via WindowSpec', () {
      final win = WindowSpec()
          .orderBy('salary')
          .rowsBetween(WindowSpec.unboundedPreceding, WindowSpec.currentRow);
      final query = QueryBuilder(client)
          .table('employees')
          .select(['salary'])
          .firstValue('running_first', 'salary', win);
      final sql = query.toSQL();

      expect(
        sql.sql,
        'select "salary", first_value("salary") over (order by "salary" asc rows between unbounded preceding and current row) as running_first from "employees"',
      );
      expect(sql.bindings, isEmpty);
    });

    test('Test V9: rangeBetween frame on WindowSpec', () {
      final win = WindowSpec()
          .partitionBy(['dept'])
          .orderBy('salary', 'desc')
          .rangeBetween(
            WindowSpec.unboundedPreceding,
            WindowSpec.currentRow,
          );
      final query = QueryBuilder(client)
          .table('employees')
          .select(['name'])
          .lastValue('last_in_range', 'salary', win);
      final sql = query.toSQL();

      expect(
        sql.sql,
        'select "name", last_value("salary") over (partition by "dept" order by "salary" desc range between unbounded preceding and current row) as last_in_range from "employees"',
      );
      expect(sql.bindings, isEmpty);
    });

    test('Test V10: lead() with callback OVER clause', () {
      final query = QueryBuilder(client)
          .table('employees')
          .select(['name'])
          .lead('next_sal', 'salary', (a) {
            a.orderBy('salary').partitionBy('dept');
          });
      final sql = query.toSQL();

      expect(
        sql.sql,
        'select "name", lead("salary") over (partition by "dept" order by "salary") as next_sal from "employees"',
      );
      expect(sql.bindings, isEmpty);
    });

    test('Test V11: WindowSpec frameToken - n preceding and n following', () {
      // -3 = "3 preceding", 2 = "2 following" — no collision with sentinels
      final win = WindowSpec().orderBy('salary').rowsBetween(-3, 2);
      final query = QueryBuilder(client)
          .table('employees')
          .select(['salary'])
          .firstValue('f', 'salary', win);
      final sql = query.toSQL();

      expect(
        sql.sql,
        'select "salary", first_value("salary") over (order by "salary" asc rows between 3 preceding and 2 following) as f from "employees"',
      );
      expect(sql.bindings, isEmpty);
    });
  });
}
