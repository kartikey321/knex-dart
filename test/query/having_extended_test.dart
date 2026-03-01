/// Dart parity tests for extended HAVING variants
///
/// JS Baseline: Run with Node.js to verify SQL
/// Run this test: cd knex-dart && dart test test/query/having_extended_test.dart
import 'package:knex_dart/src/query/query_builder.dart';
import 'package:test/test.dart';
import '../mocks/mock_client.dart';

void main() {
  late MockClient client;

  setUp(() {
    client = MockClient();
  });

  group('HAVING IN variants', () {
    test('havingIn basic', () {
      final sql = client
          .queryBuilder()
          .from('users')
          .groupBy('status')
          .havingIn('status', ['active', 'pending'])
          .toSQL();
      // JS pg: select * from "users" group by "status" having "status" in (?, ?)
      expect(
        sql.sql,
        'select * from "users" group by "status" having "status" in (\$1, \$2)',
      );
      expect(sql.bindings, ['active', 'pending']);
    });

    test('havingNotIn', () {
      final sql = client
          .queryBuilder()
          .from('users')
          .groupBy('status')
          .havingNotIn('status', ['active'])
          .toSQL();
      expect(
        sql.sql,
        'select * from "users" group by "status" having "status" not in (\$1)',
      );
      expect(sql.bindings, ['active']);
    });

    test('orHavingIn', () {
      final sql = client
          .queryBuilder()
          .from('users')
          .groupBy('status')
          .having('count', '>', 5)
          .orHavingIn('status', ['active'])
          .toSQL();
      // JS pg: ...having "count" > ? or "status" in (?)
      expect(
        sql.sql,
        'select * from "users" group by "status" having "count" > \$1 or "status" in (\$2)',
      );
      expect(sql.bindings, [5, 'active']);
    });

    test('orHavingNotIn', () {
      final sql = client
          .queryBuilder()
          .from('users')
          .groupBy('status')
          .having('count', '>', 5)
          .orHavingNotIn('status', ['banned'])
          .toSQL();
      expect(
        sql.sql,
        'select * from "users" group by "status" having "count" > \$1 or "status" not in (\$2)',
      );
      expect(sql.bindings, [5, 'banned']);
    });
  });

  group('HAVING BETWEEN variants', () {
    test('havingBetween', () {
      final sql = client
          .queryBuilder()
          .from('users')
          .groupBy('age')
          .havingBetween('age', [18, 65])
          .toSQL();
      // JS pg: ...having "age" between ? and ?
      expect(
        sql.sql,
        'select * from "users" group by "age" having "age" between \$1 and \$2',
      );
      expect(sql.bindings, [18, 65]);
    });

    test('havingNotBetween', () {
      final sql = client
          .queryBuilder()
          .from('users')
          .groupBy('age')
          .havingNotBetween('age', [18, 65])
          .toSQL();
      expect(
        sql.sql,
        'select * from "users" group by "age" having "age" not between \$1 and \$2',
      );
      expect(sql.bindings, [18, 65]);
    });

    test('orHavingBetween', () {
      final sql = client
          .queryBuilder()
          .from('orders')
          .groupBy('status')
          .having('total', '>', 100)
          .orHavingBetween('amount', [50, 150])
          .toSQL();
      expect(
        sql.sql,
        'select * from "orders" group by "status" having "total" > \$1 or "amount" between \$2 and \$3',
      );
      expect(sql.bindings, [100, 50, 150]);
    });
  });

  group('HAVING NULL variants', () {
    test('havingNull', () {
      final sql = client
          .queryBuilder()
          .from('users')
          .groupBy('email')
          .havingNull('email')
          .toSQL();
      // JS pg: ...having "email" is null
      expect(
        sql.sql,
        'select * from "users" group by "email" having "email" is null',
      );
      expect(sql.bindings, []);
    });

    test('havingNotNull', () {
      final sql = client
          .queryBuilder()
          .from('users')
          .groupBy('email')
          .havingNotNull('email')
          .toSQL();
      expect(
        sql.sql,
        'select * from "users" group by "email" having "email" is not null',
      );
    });

    test('orHavingNull', () {
      final sql = client
          .queryBuilder()
          .from('users')
          .groupBy('email')
          .having('count', '>', 5)
          .orHavingNull('email')
          .toSQL();
      expect(
        sql.sql,
        'select * from "users" group by "email" having "count" > \$1 or "email" is null',
      );
      expect(sql.bindings, [5]);
    });

    test('orHavingNotNull', () {
      final sql = client
          .queryBuilder()
          .from('users')
          .groupBy('email')
          .having('count', '>', 5)
          .orHavingNotNull('email')
          .toSQL();
      expect(
        sql.sql,
        'select * from "users" group by "email" having "count" > \$1 or "email" is not null',
      );
    });
  });

  group('orHaving and orHavingRaw', () {
    test('orHaving', () {
      final sql = client
          .queryBuilder()
          .from('orders')
          .groupBy('status')
          .having('total', '>', 100)
          .orHaving('count', '<', 5)
          .toSQL();
      // JS pg: ...having "total" > ? or "count" < ?
      expect(
        sql.sql,
        'select * from "orders" group by "status" having "total" > \$1 or "count" < \$2',
      );
      expect(sql.bindings, [100, 5]);
    });

    test('orHavingRaw', () {
      final sql = client
          .queryBuilder()
          .from('orders')
          .groupBy('status')
          .havingRaw('count(*) > ?', [5])
          .orHavingRaw('sum(total) > ?', [1000])
          .toSQL();
      // JS pg: ...having count(*) > ? or sum(total) > ?
      expect(
        sql.sql,
        'select * from "orders" group by "status" having count(*) > \$1 or sum(total) > \$2',
      );
      expect(sql.bindings, [5, 1000]);
    });

    test('combined havingIn and havingBetween', () {
      final sql = client
          .queryBuilder()
          .from('products')
          .groupBy('category')
          .havingIn('category', ['electronics', 'clothing'])
          .havingBetween('price', [10, 500])
          .toSQL();
      expect(
        sql.sql,
        'select * from "products" group by "category" having "category" in (\$1, \$2) and "price" between \$3 and \$4',
      );
      expect(sql.bindings, ['electronics', 'clothing', 10, 500]);
    });
  });
}
