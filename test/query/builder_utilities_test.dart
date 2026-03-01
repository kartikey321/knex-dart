/// Dart parity tests for Builder Utilities
///
/// These tests verify that knex-dart produces IDENTICAL SQL output to knex.js
/// for all builder utility methods.
///
/// JS Baseline: knex-js/test/js_comparison/querycompiler_step20_builder_utilities.js
/// Run baseline:  cd knex-js && node test/js_comparison/querycompiler_step20_builder_utilities.js
/// Run this test: cd knex-dart && dart test test/query/builder_utilities_test.dart
import 'package:test/test.dart';
import 'package:knex_dart/knex_dart.dart';
import '../mocks/mock_client.dart';

void main() {
  late MockClient client;

  setUp(() {
    client = MockClient();
  });

  group('JS Parity: Builder Utilities (Step 20)', () {
    // Test 1: clone() produces independent copy
    test('Test 1: clone() produces independent copy', () {
      final base = client.queryBuilder().table('users').select(['id', 'name']);
      final cloned = base.clone().where('active', true);

      // JS: select "id", "name" from "users"
      expect(base.toSQL().sql, 'select "id", "name" from "users"');
      expect(base.toSQL().bindings, []);

      // JS: select "id", "name" from "users" where "active" = ?
      expect(
        cloned.toSQL().sql,
        'select "id", "name" from "users" where "active" = \$1',
      );
      expect(cloned.toSQL().bindings, [true]);
    });

    // Test 2: clearSelect()
    test('Test 2: clearSelect() removes column selection', () {
      final sql = client
          .queryBuilder()
          .table('users')
          .select(['id', 'name'])
          .clearSelect()
          .toSQL();
      // JS: select * from "users"
      expect(sql.sql, 'select * from "users"');
      expect(sql.bindings, []);
    });

    // Test 3: clearWhere()
    test('Test 3: clearWhere() removes where clauses', () {
      final sql = client
          .queryBuilder()
          .table('users')
          .where('active', true)
          .clearWhere()
          .toSQL();
      // JS: select * from "users"
      expect(sql.sql, 'select * from "users"');
      expect(sql.bindings, []);
    });

    // Test 4: clearOrder()
    test('Test 4: clearOrder() removes order by', () {
      final sql = client
          .queryBuilder()
          .table('users')
          .orderBy('name', 'asc')
          .clearOrder()
          .toSQL();
      // JS: select * from "users"
      expect(sql.sql, 'select * from "users"');
      expect(sql.bindings, []);
    });

    // Test 5: truncate()
    test('Test 5: truncate()', () {
      final sql = client.queryBuilder().table('users').truncate().toSQL();
      // JS (pg): truncate "users" restart identity
      expect(sql.sql, 'truncate "users" restart identity');
      expect(sql.bindings, []);
    });

    // Test 6: forUpdate()
    test('Test 6: forUpdate()', () {
      final sql = client
          .queryBuilder()
          .table('users')
          .select(['*'])
          .forUpdate()
          .toSQL();
      // JS: select * from "users" for update
      expect(sql.sql, 'select * from "users" for update');
      expect(sql.bindings, []);
    });

    // Test 7: forShare()
    test('Test 7: forShare()', () {
      final sql = client
          .queryBuilder()
          .table('users')
          .select(['*'])
          .forShare()
          .toSQL();
      // JS: select * from "users" for share
      expect(sql.sql, 'select * from "users" for share');
      expect(sql.bindings, []);
    });

    // Test 8: forUpdate().skipLocked()
    test('Test 8: forUpdate().skipLocked()', () {
      final sql = client
          .queryBuilder()
          .table('users')
          .select(['*'])
          .forUpdate()
          .skipLocked()
          .toSQL();
      // JS: select * from "users" for update skip locked
      expect(sql.sql, 'select * from "users" for update skip locked');
      expect(sql.bindings, []);
    });

    // Test 9: forUpdate().noWait()
    test('Test 9: forUpdate().noWait()', () {
      final sql = client
          .queryBuilder()
          .table('users')
          .select(['*'])
          .forUpdate()
          .noWait()
          .toSQL();
      // JS: select * from "users" for update nowait
      expect(sql.sql, 'select * from "users" for update nowait');
      expect(sql.bindings, []);
    });

    // Test 10: joinRaw()
    test('Test 10: joinRaw()', () {
      final sql = client
          .queryBuilder()
          .table('users')
          .joinRaw('natural join orders')
          .toSQL();
      // JS: select * from "users" natural join orders
      expect(sql.sql, 'select * from "users" natural join orders');
      expect(sql.bindings, []);
    });

    // Test 11: groupByRaw()
    test('Test 11: groupByRaw()', () {
      final sql = client
          .queryBuilder()
          .table('orders')
          .select([client.raw('count(*)')])
          .groupByRaw("date_trunc('year', \"created_at\")")
          .toSQL();
      // JS: select count(*) from "orders" group by date_trunc('year', "created_at")
      expect(
        sql.sql,
        "select count(*) from \"orders\" group by date_trunc('year', \"created_at\")",
      );
      expect(sql.bindings, []);
    });

    // Test 12: orderByRaw()
    test('Test 12: orderByRaw()', () {
      final sql = client.queryBuilder().table('users').orderByRaw(
        'FIELD(status, ?)',
        ['active'],
      ).toSQL();
      // JS: select * from "users" order by FIELD(status, ?)
      // Note: Dart uses $1 parameter style
      expect(sql.sql, 'select * from "users" order by FIELD(status, \$1)');
      expect(sql.bindings, ['active']);
    });

    // Test 13: fromRaw()
    test('Test 13: fromRaw()', () {
      final sql = client
          .queryBuilder()
          .select(['*'])
          .fromRaw(
            client.raw('(select * from ?? where active = ?) as active_users', [
              'users',
              true,
            ]),
          )
          .toSQL();
      // JS: select * from (select * from "users" where active = ?) as active_users
      expect(
        sql.sql,
        'select * from (select * from "users" where active = \$1) as active_users',
      );
      expect(sql.bindings, [true]);
    });

    // Test 14: modify()
    test('Test 14: modify()', () {
      addActive(QueryBuilder qb) {
        qb.where('active', true);
      }

      final sql = client
          .queryBuilder()
          .table('users')
          .modify(addActive)
          .toSQL();
      // JS: select * from "users" where "active" = ?
      expect(sql.sql, 'select * from "users" where "active" = \$1');
      expect(sql.bindings, [true]);
    });

    // Test 15: forNoKeyUpdate() (Postgres-specific)
    test('Test 15: forNoKeyUpdate()', () {
      final sql = client
          .queryBuilder()
          .table('users')
          .select(['*'])
          .forNoKeyUpdate()
          .toSQL();
      // JS: select * from "users" for no key update
      expect(sql.sql, 'select * from "users" for no key update');
      expect(sql.bindings, []);
    });

    // Test 16: forKeyShare() (Postgres-specific)
    test('Test 16: forKeyShare()', () {
      final sql = client
          .queryBuilder()
          .table('users')
          .select(['*'])
          .forKeyShare()
          .toSQL();
      // JS: select * from "users" for key share
      expect(sql.sql, 'select * from "users" for key share');
      expect(sql.bindings, []);
    });

    // Test 17: clone with multiple modifiers
    test('Test 17: clone with multiple modifiers', () {
      final baseQ = client
          .queryBuilder()
          .table('products')
          .select(['*'])
          .where('category', 'electronics');
      final sql = baseQ.clone().orderBy('price', 'desc').limit(10).toSQL();
      // JS: select * from "products" where "category" = ? order by "price" desc limit ?
      expect(
        sql.sql,
        'select * from "products" where "category" = \$1 order by "price" desc limit \$2',
      );
      expect(sql.bindings, ['electronics', 10]);
    });

    // Test 18: clearHaving()
    test('Test 18: clearHaving() removes having clause', () {
      final sql = client
          .queryBuilder()
          .table('orders')
          .groupBy('user_id')
          .havingRaw('count(*) > ?', [5])
          .clearHaving()
          .toSQL();
      // JS: select * from "orders" group by "user_id"
      expect(sql.sql, 'select * from "orders" group by "user_id"');
      expect(sql.bindings, []);
    });
  });
}
