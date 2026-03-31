import 'package:test/test.dart';
import 'package:knex_dart/src/query/query_builder.dart';
import '../mocks/mock_client.dart';

void main() {
  late MockClient client;

  setUp(() {
    client = MockClient();
  });

  group('SELECT Subqueries - Comparison with Knex.js', () {
    test('Simple SELECT subquery', () {
      final subquery = QueryBuilder(client)
          .table('orders')
          .count('*')
          .where(client.raw('orders.user_id = users.id'))
          .as('order_count');

      final query = QueryBuilder(
        client,
      ).table('users').select(['name', subquery]);

      final sql = query.toSQL();

      // JS: select "name", (select count(*) from "orders" where orders.user_id = users.id) as "order_count" from "users"
      expect(
        sql.sql,
        'select "name", (select count(*) from "orders" where orders.user_id = users.id) as "order_count" from "users"',
      );
      expect(sql.bindings, isEmpty);
    });

    test('Multiple SELECT subqueries', () {
      final ordersSubquery = QueryBuilder(client)
          .table('orders')
          .count('*')
          .where(client.raw('orders.user_id = users.id'))
          .as('total_orders');

      final amountSubquery = QueryBuilder(client)
          .table('orders')
          .sum('amount')
          .where(client.raw('orders.user_id = users.id'))
          .as('total_spent');

      final query = QueryBuilder(
        client,
      ).table('users').select(['id', 'name', ordersSubquery, amountSubquery]);

      final sql = query.toSQL();

      // JS: select "id", "name", (select count(*) from "orders" where orders.user_id = users.id) as "total_orders", (select sum("amount") from "orders" where orders.user_id = users.id) as "total_spent" from "users"
      expect(
        sql.sql,
        'select "id", "name", (select count(*) from "orders" where orders.user_id = users.id) as "total_orders", (select sum("amount") from "orders" where orders.user_id = users.id) as "total_spent" from "users"',
      );
      expect(sql.bindings, isEmpty);
    });

    test('SELECT subquery with WHERE clause', () {
      final subquery = QueryBuilder(client)
          .table('orders')
          .count('*')
          .where('status', '=', 'completed')
          .where(client.raw('orders.user_id = users.id'))
          .as('completed_orders');

      final query = QueryBuilder(
        client,
      ).table('users').select(['name', subquery]).where('active', '=', true);

      final sql = query.toSQL();

      // JS: select "name", (select count(*) from "orders" where "status" = 'completed' and orders.user_id = users.id) as "completed_orders" from "users" where "active" = true
      expect(
        sql.sql,
        'select "name", (select count(*) from "orders" where "status" = \$1 and orders.user_id = users.id) as "completed_orders" from "users" where "active" = \$2',
      );
      expect(sql.bindings, ['completed', true]);
    });

    test('Mixed regular columns and subqueries', () {
      final subquery = QueryBuilder(client)
          .table('posts')
          .count('*')
          .where(client.raw('posts.user_id = users.id'))
          .as('post_count');

      final query = QueryBuilder(client).table('users').select([
        'users.id',
        'users.name',
        'users.email',
        subquery,
      ]);

      final sql = query.toSQL();

      // JS: select "users"."id", "users"."name", "users"."email", (select count(*) from "posts" where posts.user_id = users.id) as "post_count" from "users"
      expect(
        sql.sql,
        'select "users"."id", "users"."name", "users"."email", (select count(*) from "posts" where posts.user_id = users.id) as "post_count" from "users"',
      );
      expect(sql.bindings, isEmpty);
    });
  });
}
