import 'package:test/test.dart';
import 'package:knex_dart/src/query/query_builder.dart';
import '../mocks/mock_client.dart';

void main() {
  late MockClient client;

  setUp(() {
    client = MockClient();
  });

  group('Subquery Support - Comparison with Knex.js', () {
    test('whereIn with subquery', () {
      final subquery = QueryBuilder(client).table('orders').select(['user_id']);
      final query = QueryBuilder(client).table('users').whereIn('id', subquery);

      final sql = query.toSQL();

      // JS: select * from "users" where "id" in (select "user_id" from "orders")
      expect(
        sql.sql,
        'select * from "users" where "id" in (select "user_id" from "orders")',
      );
      expect(sql.bindings, isEmpty);
    });

    test('whereNotIn with subquery', () {
      final subquery = QueryBuilder(client).table('banned').select(['user_id']);
      final query = QueryBuilder(
        client,
      ).table('users').whereNotIn('id', subquery);

      final sql = query.toSQL();

      // JS: select * from "users" where "id" not in (select "user_id" from "banned")
      expect(
        sql.sql,
        'select * from "users" where "id" not in (select "user_id" from "banned")',
      );
      expect(sql.bindings, isEmpty);
    });

    test('FROM with subquery and alias', () {
      final subquery = QueryBuilder(
        client,
      ).table('orders').groupBy('user_id').as('grouped');
      final query = QueryBuilder(client).from(subquery).select(['*']);

      final sql = query.toSQL();

      // JS: select * from (select * from "orders" group by "user_id") as "grouped"
      expect(
        sql.sql,
        'select * from (select * from "orders" group by "user_id") as "grouped"',
      );
      expect(sql.bindings, isEmpty);
    });

    test('Nested whereIn subqueries', () {
      final innerSubquery = QueryBuilder(
        client,
      ).table('products').select(['id']).where('active', '=', true);

      final outerSubquery = QueryBuilder(client)
          .table('orders')
          .select(['user_id'])
          .whereIn('product_id', innerSubquery);

      final query = QueryBuilder(
        client,
      ).table('users').whereIn('id', outerSubquery);

      final sql = query.toSQL();

      // JS: select * from "users" where "id" in (select "user_id" from "orders" where "product_id" in (select "id" from "products" where "active" = true))
      expect(
        sql.sql,
        'select * from "users" where "id" in (select "user_id" from "orders" where "product_id" in (select "id" from "products" where "active" = \$1))',
      );
      expect(sql.bindings, [true]);
    });

    test('Multiple conditions with subquery', () {
      final subquery = QueryBuilder(
        client,
      ).table('orders').select(['user_id']).where('status', '=', 'completed');

      final query = QueryBuilder(
        client,
      ).table('users').where('active', '=', true).whereIn('id', subquery);

      final sql = query.toSQL();

      // JS: select * from "users" where "active" = true and "id" in (select "user_id" from "orders" where "status" = 'completed')
      expect(
        sql.sql,
        'select * from "users" where "active" = \$1 and "id" in (select "user_id" from "orders" where "status" = \$2)',
      );
      expect(sql.bindings, [true, 'completed']);
    });
  });
}
