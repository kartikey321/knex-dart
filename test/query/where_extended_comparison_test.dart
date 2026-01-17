import 'package:test/test.dart';
import 'package:knex_dart/src/query/query_builder.dart';
import '../mocks/mock_client.dart';

void main() {
  late MockClient client;

  setUp(() {
    client = MockClient();
  });

  group('Extended WHERE Clauses - Comparison with Knex.js', () {
    test('whereColumn - compare two columns', () {
      final query = QueryBuilder(
        client,
      ).table('users').whereColumn('updated_at', '>', 'created_at');

      final sql = query.toSQL();

      // JS: select * from "users" where "updated_at" > "created_at"
      expect(
        sql.sql,
        'select * from "users" where "updated_at" > "created_at"',
      );
      expect(sql.bindings, isEmpty);
    });

    test('orWhereColumn - OR with column comparison', () {
      final query = QueryBuilder(client)
          .table('users')
          .where('active', '=', true)
          .orWhereColumn('email', '=', 'backup_email');

      final sql = query.toSQL();

      // JS: select * from "users" where "active" = true or "email" = "backup_email"
      expect(
        sql.sql,
        'select * from "users" where "active" = \$1 or "email" = "backup_email"',
      );
      expect(sql.bindings, [true]);
    });

    test('whereBetween - value between range', () {
      final query = QueryBuilder(
        client,
      ).table('users').whereBetween('age', [18, 65]);

      final sql = query.toSQL();

      // JS: select * from "users" where "age" between 18 and 65
      expect(sql.sql, 'select * from "users" where "age" between \$1 and \$2');
      expect(sql.bindings, [18, 65]);
    });

    test('whereNotBetween - value not in range', () {
      final query = QueryBuilder(
        client,
      ).table('products').whereNotBetween('price', [0, 10]);

      final sql = query.toSQL();

      // JS: select * from "products" where "price" not between 0 and 10
      expect(
        sql.sql,
        'select * from "products" where "price" not between \$1 and \$2',
      );
      expect(sql.bindings, [0, 10]);
    });

    test('orWhereBetween - OR with BETWEEN', () {
      final query = QueryBuilder(client)
          .table('products')
          .where('active', '=', true)
          .orWhereBetween('price', [10, 100]);

      final sql = query.toSQL();

      // JS: select * from "products" where "active" = true or "price" between 10 and 100
      expect(
        sql.sql,
        'select * from "products" where "active" = \$1 or "price" between \$2 and \$3',
      );
      expect(sql.bindings, [true, 10, 100]);
    });

    test('orWhereNotBetween - OR with NOT BETWEEN', () {
      final query = QueryBuilder(client)
          .table('users')
          .where('active', '=', true)
          .orWhereNotBetween('score', [0, 50]);

      final sql = query.toSQL();

      // JS: select * from "users" where "active" = true or "score" not between 0 and 50
      expect(
        sql.sql,
        'select * from "users" where "active" = \$1 or "score" not between \$2 and \$3',
      );
      expect(sql.bindings, [true, 0, 50]);
    });

    test('whereNot - negate condition', () {
      final query = QueryBuilder(
        client,
      ).table('users').whereNot('status', '=', 'deleted');

      final sql = query.toSQL();

      // JS: select * from "users" where not "status" = 'deleted'
      expect(sql.sql, 'select * from "users" where not "status" = \$1');
      expect(sql.bindings, ['deleted']);
    });

    test('orWhereNot - OR with NOT', () {
      final query = QueryBuilder(client)
          .table('users')
          .where('active', '=', true)
          .orWhereNot('banned', '=', true);

      final sql = query.toSQL();

      // JS: select * from "users" where "active" = true or not "banned" = true
      expect(
        sql.sql,
        'select * from "users" where "active" = \$1 or not "banned" = \$2',
      );
      expect(sql.bindings, [true, true]);
    });

    test('orWhereNotIn - OR with NOT IN', () {
      final query = QueryBuilder(
        client,
      ).table('users').where('active', '=', true).orWhereNotIn('id', [1, 2, 3]);

      final sql = query.toSQL();

      // JS: select * from "users" where "active" = true or "id" not in (1, 2, 3)
      expect(
        sql.sql,
        'select * from "users" where "active" = \$1 or "id" not in (\$2, \$3, \$4)',
      );
      expect(sql.bindings, [true, 1, 2, 3]);
    });

    test('orWhereNotNull - OR with NOT NULL', () {
      final query = QueryBuilder(
        client,
      ).table('users').where('active', '=', true).orWhereNotNull('email');

      final sql = query.toSQL();

      // JS: select * from "users" where "active" = true or "email" is not null
      expect(
        sql.sql,
        'select * from "users" where "active" = \$1 or "email" is not null',
      );
      expect(sql.bindings, [true]);
    });

    test('whereExists - subquery existence check', () {
      final query = QueryBuilder(client).table('users').whereExists((qb) {
        (qb as QueryBuilder)
            .select(['*'])
            .from('orders')
            .where(client.raw('orders.user_id = users.id'));
      });

      final sql = query.toSQL();

      // JS: select * from "users" where exists (select * from "orders" where orders.user_id = users.id)
      expect(
        sql.sql,
        'select * from "users" where exists (select * from "orders" where orders.user_id = users.id)',
      );
      expect(sql.bindings, isEmpty);
    });

    test('whereNotExists - negative existence check', () {
      final query = QueryBuilder(client).table('products').whereNotExists((qb) {
        (qb as QueryBuilder)
            .select(['*'])
            .from('inventory')
            .where(client.raw('inventory.product_id = products.id'));
      });

      final sql = query.toSQL();

      // JS: select * from "products" where not exists (select * from "inventory" where inventory.product_id = products.id)
      expect(
        sql.sql,
        'select * from "products" where not exists (select * from "inventory" where inventory.product_id = products.id)',
      );
      expect(sql.bindings, isEmpty);
    });

    test('orWhereExists - OR with EXISTS', () {
      final query = QueryBuilder(client)
          .table('users')
          .where('active', '=', true)
          .orWhereExists((qb) {
            (qb as QueryBuilder)
                .select(['*'])
                .from('orders')
                .where(client.raw('orders.user_id = users.id'));
          });

      final sql = query.toSQL();

      // JS: select * from "users" where "active" = true or exists (select * from "orders" where orders.user_id = users.id)
      expect(
        sql.sql,
        'select * from "users" where "active" = \$1 or exists (select * from "orders" where orders.user_id = users.id)',
      );
      expect(sql.bindings, [true]);
    });

    test('orWhereNotExists - OR with NOT EXISTS', () {
      final query = QueryBuilder(client)
          .table('users')
          .where('active', '=', true)
          .orWhereNotExists((qb) {
            (qb as QueryBuilder)
                .select(['*'])
                .from('banned_users')
                .where(client.raw('banned_users.user_id = users.id'));
          });

      final sql = query.toSQL();

      // JS: select * from "users" where "active" = true or not exists (select * from "banned_users" where banned_users.user_id = users.id)
      expect(
        sql.sql,
        'select * from "users" where "active" = \$1 or not exists (select * from "banned_users" where banned_users.user_id = users.id)',
      );
      expect(sql.bindings, [true]);
    });

    test('whereWrapped - grouped conditions', () {
      final query = QueryBuilder(client)
          .table('users')
          .where('active', '=', true)
          .whereWrapped((qb) {
            (qb as QueryBuilder)
                .where('age', '>', 18)
                .orWhere('verified', '=', true);
          });

      final sql = query.toSQL();

      // JS: select * from "users" where "active" = true and ("age" > 18 or "verified" = true)
      expect(
        sql.sql,
        'select * from "users" where "active" = \$1 and ("age" > \$2 or "verified" = \$3)',
      );
      expect(sql.bindings, [true, 18, true]);
    });

    test('combined - multiple extended WHERE clauses', () {
      final query = QueryBuilder(client)
          .table('users')
          .whereBetween('age', [18, 65])
          .whereNotNull('email')
          .whereExists((qb) {
            (qb as QueryBuilder)
                .select(['*'])
                .from('orders')
                .where(client.raw('orders.user_id = users.id'));
          });

      final sql = query.toSQL();

      // JS: select * from "users" where "age" between 18 and 65 and "email" is not null and exists (select * from "orders" where orders.user_id = users.id)
      expect(
        sql.sql,
        'select * from "users" where "age" between \$1 and \$2 and "email" is not null and exists (select * from "orders" where orders.user_id = users.id)',
      );
      expect(sql.bindings, [18, 65]);
    });
  });
}
