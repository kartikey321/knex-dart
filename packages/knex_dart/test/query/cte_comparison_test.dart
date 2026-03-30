import 'package:test/test.dart';
import 'package:knex_dart/src/query/query_builder.dart';
import '../mocks/mock_client.dart';

void main() {
  late MockClient client;

  setUp(() {
    client = MockClient();
  });

  group('CTE Operations - Comparison with Knex.js', () {
    test('Basic CTE with Raw', () {
      final query = QueryBuilder(client)
          .withQuery('sales', client.raw('select * from orders'))
          .select(['*'])
          .from('sales');
      final sql = query.toSQL();

      // JS: with "sales" as (select * from orders) select * from "sales"
      expect(
        sql.sql,
        'with "sales" as (select * from orders) select * from "sales"',
      );
      expect(sql.bindings, []);
    });

    test('CTE with QueryBuilder', () {
      final cte = QueryBuilder(client)
          .table('orders')
          .select(['region'])
          .sum('amount as total')
          .groupBy('region');

      final query = QueryBuilder(
        client,
      ).withQuery('regional_sales', cte).select(['*']).from('regional_sales');
      final sql = query.toSQL();

      // JS: with "regional_sales" as (select "region", sum("amount") as "total" from "orders" group by "region") select * from "regional_sales"
      expect(
        sql.sql,
        'with "regional_sales" as (select "region", sum("amount") as "total" from "orders" group by "region") select * from "regional_sales"',
      );
      expect(sql.bindings, []);
    });

    test('Multiple CTEs', () {
      final sales = QueryBuilder(
        client,
      ).table('orders').select(['*']).where('status', '=', 'completed');
      final returns = QueryBuilder(client).table('refunds').select(['*']);

      final query = QueryBuilder(client)
          .withQuery('sales', sales)
          .withQuery('returns', returns)
          .select(['*'])
          .from('sales')
          .join('returns', 'sales.id', 'returns.order_id');
      final sql = query.toSQL();

      // JS: with "sales" as (select * from "orders" where "status" = 'completed'), "returns" as (select * from "refunds") select * from "sales" inner join "returns" on "sales"."id" = "returns"."order_id"
      expect(
        sql.sql,
        'with "sales" as (select * from "orders" where "status" = \$1), "returns" as (select * from "refunds") select * from "sales" inner join "returns" on "sales"."id" = "returns"."order_id"',
      );
      expect(sql.bindings, ['completed']);
    });

    test('Recursive CTE', () {
      final recursive = QueryBuilder(client)
          .table('nodes')
          .select(['*'])
          .where('parent_id', '=', null)
          .union([
            QueryBuilder(client)
                .table('nodes as n')
                .select(['n.*'])
                .join('tree as t', 'n.parent_id', 't.id'),
          ]);

      final query = QueryBuilder(
        client,
      ).withRecursive('tree', recursive).select(['*']).from('tree');
      final sql = query.toSQL();

      // JS: with recursive "tree" as (select * from "nodes" where "parent_id" is null union select "n".* from "nodes" as "n" inner join "tree" as "t" on "n"."parent_id" = "t"."id") select * from "tree"
      expect(
        sql.sql,
        'with recursive "tree" as (select * from "nodes" where "parent_id" is null union select "n".* from "nodes" as "n" inner join "tree" as "t" on "n"."parent_id" = "t"."id") select * from "tree"',
      );
      expect(sql.bindings, []);
    });

    test('CTE with WHERE in main query', () {
      final cte = QueryBuilder(
        client,
      ).table('users').select(['*']).where('active', '=', true);

      final query = QueryBuilder(client)
          .withQuery('active_users', cte)
          .select(['id', 'name'])
          .from('active_users')
          .where('role', '=', 'admin');
      final sql = query.toSQL();

      // JS: with "active_users" as (select * from "users" where "active" = true) select "id", "name" from "active_users" where "role" = 'admin'
      expect(
        sql.sql,
        'with "active_users" as (select * from "users" where "active" = \$1) select "id", "name" from "active_users" where "role" = \$2',
      );
      expect(sql.bindings, [true, 'admin']);
    });
  });
}
