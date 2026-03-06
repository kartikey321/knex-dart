import 'package:test/test.dart';
import 'package:knex_dart/src/query/query_builder.dart';
import 'package:knex_dart/src/query/query_compiler.dart';
import 'package:knex_dart/src/query/aggregate_options.dart';
import '../mocks/mock_client.dart';
import '../mocks/mysql_mock_client.dart';
import '../mocks/sqlite_mock_client.dart';

void main() {
  late MockClient client;

  setUp(() {
    client = MockClient();
  });

  group('QueryCompiler Step 1 - Basic Structure (JS Comparison)', () {
    test('Test 1: SELECT * (no columns specified)', () {
      // JS: select * from "users"
      final builder = QueryBuilder(client).table('users');
      final sql = builder.toSQL();

      expect(sql.sql, 'select * from "users"');
      expect(sql.bindings, []);
      expect(sql.method, 'select');
      expect(sql.uid?.length, 12);
    });

    test('Test 2: SELECT with specific columns', () {
      // JS: select "id", "name" from "users"
      final builder = QueryBuilder(
        client,
      ).table('users').select(['id', 'name']);
      final sql = builder.toSQL();

      expect(sql.sql, 'select "id", "name" from "users"');
      expect(sql.bindings, []);
      expect(sql.method, 'select');
    });

    test('Test 3: SELECT with dotted columns', () {
      // JS: select "users"."id", "users"."name" from "users"
      final builder = QueryBuilder(
        client,
      ).table('users').select(['users.id', 'users.name']);
      final sql = builder.toSQL();

      expect(sql.sql, 'select "users"."id", "users"."name" from "users"');
      expect(sql.bindings, []);
    });

    test('Test 4: Just table, no select', () {
      // JS: select * from "posts"
      final builder = QueryBuilder(client).table('posts');
      final sql = builder.toSQL();

      expect(sql.sql, 'select * from "posts"');
      expect(sql.bindings, []);
    });

    test('Test 5: Multiple columns', () {
      // JS: select "id", "name", "email", "status" from "users"
      final builder = QueryBuilder(
        client,
      ).table('users').select(['id', 'name', 'email', 'status']);
      final sql = builder.toSQL();

      expect(sql.sql, 'select "id", "name", "email", "status" from "users"');
      expect(sql.bindings, []);
    });

    test('Test 6: Table with schema', () {
      // JS: select "id" from "public"."users"
      final builder = QueryBuilder(client).table('public.users').select(['id']);
      final sql = builder.toSQL();

      expect(sql.sql, 'select "id" from "public"."users"');
      expect(sql.bindings, []);
    });
  });

  group('QueryCompiler - Structure Tests', () {
    test('Statement grouping works correctly', () {
      final builder = QueryBuilder(
        client,
      ).table('users').select(['id', 'name']);

      final compiler = QueryCompiler(client, builder);

      // Check grouped statements
      expect(compiler.grouped.containsKey('columns'), true);
      expect(compiler.grouped['columns']?.length, 1);
    });

    test('Single values extracted correctly', () {
      final builder = QueryBuilder(client).table('users');
      final compiler = QueryCompiler(client, builder);

      expect(compiler.single['table'], 'users');
    });

    test('Method extracted correctly', () {
      final builder = QueryBuilder(client).table('users');
      final compiler = QueryCompiler(client, builder);

      expect(compiler.method, 'select');
    });

    test('UID is generated and unique', () {
      final builder = QueryBuilder(client).table('users');
      final sql1 = builder.toSQL();
      final sql2 = builder.toSQL();

      expect(sql1.uid, isNot(equals(sql2.uid)));
      expect(sql1.uid?.length, 12);
      expect(sql2.uid?.length, 12);
    });
  });

  group('QueryCompiler Step 2 - WHERE Clause', () {
    test('WHERE with string value', () {
      // JS: select * from "users" where "status" = $1
      final builder = QueryBuilder(
        client,
      ).table('users').where('status', 'active');
      final sql = builder.toSQL();

      expect(sql.sql, 'select * from "users" where "status" = \$1');
      expect(sql.bindings, ['active']);
      expect(sql.method, 'select');
    });

    test('WHERE with number value', () {
      // JS: select * from "users" where "age" = $1
      final builder = QueryBuilder(client).table('users').where('age', 25);
      final sql = builder.toSQL();

      expect(sql.sql, 'select * from "users" where "age" = \$1');
      expect(sql.bindings, [25]);
    });

    test('WHERE with explicit operator >', () {
      // JS: select * from "users" where "age" > $1
      final builder = QueryBuilder(client).table('users').where('age', '>', 18);
      final sql = builder.toSQL();

      expect(sql.sql, 'select * from "users" where "age" > \$1');
      expect(sql.bindings, [18]);
    });

    test('SELECT columns with WHERE', () {
      // JS: select "id", "name" from "users" where "status" = $1
      final builder = QueryBuilder(
        client,
      ).table('users').select(['id', 'name']).where('status', 'active');
      final sql = builder.toSQL();

      expect(sql.sql, 'select "id", "name" from "users" where "status" = \$1');
      expect(sql.bindings, ['active']);
    });

    test('Multiple WHERE clauses (AND)', () {
      // JS: select * from "users" where "status" = $1 and "age" >= $2
      final builder = QueryBuilder(
        client,
      ).table('users').where('status', 'active').where('age', '>=', 18);
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "users" where "status" = \$1 and "age" >= \$2',
      );
      expect(sql.bindings, ['active', 18]);
    });

    test('WHERE with dotted column name', () {
      // JS: select * from "users" where "users"."status" = $1
      final builder = QueryBuilder(
        client,
      ).table('users').where('users.status', 'active');
      final sql = builder.toSQL();

      expect(sql.sql, 'select * from "users" where "users"."status" = \$1');
      expect(sql.bindings, ['active']);
    });

    test('WHERE with != operator', () {
      // JS: select * from "users" where "status" != $1
      final builder = QueryBuilder(
        client,
      ).table('users').where('status', '!=', 'banned');
      final sql = builder.toSQL();

      expect(sql.sql, 'select * from "users" where "status" != \$1');
      expect(sql.bindings, ['banned']);
    });

    test('WHERE with < operator', () {
      // JS: select * from "posts" where "views" < $1
      final builder = QueryBuilder(
        client,
      ).table('posts').where('views', '<', 1000);
      final sql = builder.toSQL();

      expect(sql.sql, 'select * from "posts" where "views" < \$1');
      expect(sql.bindings, [1000]);
    });

    test('WHERE with LIKE operator', () {
      // JS: select * from "users" where "email" like $1
      final builder = QueryBuilder(
        client,
      ).table('users').where('email', 'like', '%@gmail.com');
      final sql = builder.toSQL();

      expect(sql.sql, 'select * from "users" where "email" like \$1');
      expect(sql.bindings, ['%@gmail.com']);
    });

    test('Three WHERE clauses with different types', () {
      // JS: select * from "users" where "status" = $1 and "age" > $2 and "email" like $3
      final builder = QueryBuilder(client)
          .table('users')
          .where('status', 'active')
          .where('age', '>', 21)
          .where('email', 'like', '%@company.com');
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "users" where "status" = \$1 and "age" > \$2 and "email" like \$3',
      );
      expect(sql.bindings, ['active', 21, '%@company.com']);
    });
  });

  group('QueryCompiler Step 3 - ORDER BY', () {
    test('ORDER BY single column (default ASC)', () {
      // JS: select * from "users" order by "name" asc
      final builder = QueryBuilder(client).table('users').orderBy('name');
      final sql = builder.toSQL();

      expect(sql.sql, 'select * from "users" order by "name" asc');
      expect(sql.bindings, []);
      expect(sql.method, 'select');
    });

    test('ORDER BY with DESC', () {
      // JS: select * from "users" order by "created_at" desc
      final builder = QueryBuilder(
        client,
      ).table('users').orderBy('created_at', 'desc');
      final sql = builder.toSQL();

      expect(sql.sql, 'select * from "users" order by "created_at" desc');
      expect(sql.bindings, []);
    });

    test('Multiple ORDER BY columns', () {
      // JS: select * from "users" order by "status" asc, "name" desc
      final builder = QueryBuilder(
        client,
      ).table('users').orderBy('status').orderBy('name', 'desc');
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "users" order by "status" asc, "name" desc',
      );
      expect(sql.bindings, []);
    });

    test('ORDER BY with WHERE', () {
      // JS: select * from "users" where "active" = ? order by "name" asc
      final builder = QueryBuilder(
        client,
      ).table('users').where('active', true).orderBy('name');
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "users" where "active" = \$1 order by "name" asc',
      );
      expect(sql.bindings, [true]);
    });

    test('ORDER BY with dotted column', () {
      // JS: select * from "users" order by "users"."created_at" desc
      final builder = QueryBuilder(
        client,
      ).table('users').orderBy('users.created_at', 'desc');
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "users" order by "users"."created_at" desc',
      );
      expect(sql.bindings, []);
    });

    test('ORDER BY with SELECT columns', () {
      // JS: select "id", "name" from "users" order by "name" asc
      final builder = QueryBuilder(
        client,
      ).table('users').select(['id', 'name']).orderBy('name');
      final sql = builder.toSQL();

      expect(sql.sql, 'select "id", "name" from "users" order by "name" asc');
      expect(sql.bindings, []);
    });

    test('ORDER BY with WHERE and SELECT', () {
      // JS: select "id", "name" from "users" where "status" = ? order by "name" desc
      final builder = QueryBuilder(client)
          .table('users')
          .select(['id', 'name'])
          .where('status', 'active')
          .orderBy('name', 'desc');
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select "id", "name" from "users" where "status" = \$1 order by "name" desc',
      );
      expect(sql.bindings, ['active']);
    });

    test('Three ORDER BY columns', () {
      // JS: select * from "users" order by "status" asc, "created_at" desc, "name" asc
      final builder = QueryBuilder(client)
          .table('users')
          .orderBy('status')
          .orderBy('created_at', 'desc')
          .orderBy('name');
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "users" order by "status" asc, "created_at" desc, "name" asc',
      );
      expect(sql.bindings, []);
    });
  });

  group('QueryCompiler Step 4 - LIMIT & OFFSET', () {
    test('LIMIT only', () {
      // JS: select * from "users" limit ?
      final builder = QueryBuilder(client).table('users').limit(10);
      final sql = builder.toSQL();

      expect(sql.sql, 'select * from "users" limit \$1');
      expect(sql.bindings, [10]);
      expect(sql.method, 'select');
    });

    test('OFFSET only', () {
      // JS: select * from "users" offset ?
      final builder = QueryBuilder(client).table('users').offset(20);
      final sql = builder.toSQL();

      expect(sql.sql, 'select * from "users" offset \$1');
      expect(sql.bindings, [20]);
    });

    test('LIMIT + OFFSET together', () {
      // JS: select * from "users" limit ? offset ?
      final builder = QueryBuilder(client).table('users').limit(10).offset(20);
      final sql = builder.toSQL();

      expect(sql.sql, 'select * from "users" limit \$1 offset \$2');
      expect(sql.bindings, [10, 20]);
    });

    test('LIMIT with WHERE', () {
      // JS: select * from "users" where "status" = ? limit ?
      final builder = QueryBuilder(
        client,
      ).table('users').where('status', 'active').limit(5);
      final sql = builder.toSQL();

      expect(sql.sql, 'select * from "users" where "status" = \$1 limit \$2');
      expect(sql.bindings, ['active', 5]);
    });

    test('LIMIT with ORDER BY', () {
      // JS: select * from "users" order by "created_at" desc limit ?
      final builder = QueryBuilder(
        client,
      ).table('users').orderBy('created_at', 'desc').limit(3);
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "users" order by "created_at" desc limit \$1',
      );
      expect(sql.bindings, [3]);
    });

    test('Complete pagination (WHERE + ORDER BY + LIMIT + OFFSET)', () {
      // JS: select * from "users" where "status" = ? order by "name" asc limit ? offset ?
      final builder = QueryBuilder(client)
          .table('users')
          .where('status', 'active')
          .orderBy('name')
          .limit(25)
          .offset(50);
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "users" where "status" = \$1 order by "name" asc limit \$2 offset \$3',
      );
      expect(sql.bindings, ['active', 25, 50]);
    });
  });

  group('QueryCompiler Step 5 - Advanced WHERE', () {
    test('Basic orWhere', () {
      // JS: where "status" = ? or "role" = ?
      final builder = QueryBuilder(
        client,
      ).table('users').where('status', 'active').orWhere('role', 'admin');
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "users" where "status" = \$1 or "role" = \$2',
      );
      expect(sql.bindings, ['active', 'admin']);
    });

    test('Multiple orWhere', () {
      // JS: where "age" > ? or "verified" = ? or "role" = ?
      final builder = QueryBuilder(client)
          .table('users')
          .where('age', '>', 18)
          .orWhere('verified', true)
          .orWhere('role', 'admin');
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "users" where "age" > \$1 or "verified" = \$2 or "role" = \$3',
      );
      expect(sql.bindings, [18, true, 'admin']);
    });

    test('whereNull', () {
      // JS: where "deleted_at" is null
      final builder = QueryBuilder(
        client,
      ).table('users').whereNull('deleted_at');
      final sql = builder.toSQL();

      expect(sql.sql, 'select * from "users" where "deleted_at" is null');
      expect(sql.bindings, []);
    });

    test('whereNotNull', () {
      // JS: where "email" is not null
      final builder = QueryBuilder(client).table('users').whereNotNull('email');
      final sql = builder.toSQL();

      expect(sql.sql, 'select * from "users" where "email" is not null');
      expect(sql.bindings, []);
    });

    test('whereNull with AND', () {
      // JS: where "status" = ? and "banned_at" is null
      final builder = QueryBuilder(
        client,
      ).table('users').where('status', 'active').whereNull('banned_at');
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "users" where "status" = \$1 and "banned_at" is null',
      );
      expect(sql.bindings, ['active']);
    });

    test('whereIn with strings', () {
      // JS: where "status" in (?, ?)
      final builder = QueryBuilder(
        client,
      ).table('users').whereIn('status', ['active', 'pending']);
      final sql = builder.toSQL();

      expect(sql.sql, 'select * from "users" where "status" in (\$1, \$2)');
      expect(sql.bindings, ['active', 'pending']);
    });

    test('whereIn with numbers', () {
      // JS: where "id" in (?, ?, ?, ?, ?)
      final builder = QueryBuilder(
        client,
      ).table('users').whereIn('id', [1, 2, 3, 4, 5]);
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "users" where "id" in (\$1, \$2, \$3, \$4, \$5)',
      );
      expect(sql.bindings, [1, 2, 3, 4, 5]);
    });

    test('whereNotIn', () {
      // JS: where "role" not in (?, ?)
      final builder = QueryBuilder(
        client,
      ).table('users').whereNotIn('role', ['guest', 'banned']);
      final sql = builder.toSQL();

      expect(sql.sql, 'select * from "users" where "role" not in (\$1, \$2)');
      expect(sql.bindings, ['guest', 'banned']);
    });

    test('Combined WHERE + OR + NULL', () {
      // JS: where "status" = ? or "premium_until" is null
      final builder = QueryBuilder(
        client,
      ).table('users').where('status', 'active').orWhereNull('premium_until');
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "users" where "status" = \$1 or "premium_until" is null',
      );
      expect(sql.bindings, ['active']);
    });

    test('Combined WHERE + IN + ORDER BY + LIMIT', () {
      // JS: where "id" in (?, ?, ?) order by "name" asc limit ?
      final builder = QueryBuilder(
        client,
      ).table('users').whereIn('id', [10, 20, 30]).orderBy('name').limit(5);
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "users" where "id" in (\$1, \$2, \$3) order by "name" asc limit \$4',
      );
      expect(sql.bindings, [10, 20, 30, 5]);
    });
  });

  group('QueryCompiler Step 6 - GROUP BY & HAVING', () {
    test('Basic GROUP BY single column', () {
      // JS: group by "customer_id"
      final builder = QueryBuilder(
        client,
      ).table('orders').groupBy('customer_id');
      final sql = builder.toSQL();

      expect(sql.sql, 'select * from "orders" group by "customer_id"');
      expect(sql.bindings, []);
    });

    test('GROUP BY multiple columns', () {
      // JS: group by "customer_id", "status"
      final builder = QueryBuilder(
        client,
      ).table('orders').groupBy('customer_id').groupBy('status');
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "orders" group by "customer_id", "status"',
      );
      expect(sql.bindings, []);
    });

    test('GROUP BY with WHERE', () {
      // JS: where "status" = ? group by "customer_id"
      final builder = QueryBuilder(
        client,
      ).table('orders').where('status', 'completed').groupBy('customer_id');
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "orders" where "status" = \$1 group by "customer_id"',
      );
      expect(sql.bindings, ['completed']);
    });

    test('Basic HAVING', () {
      // JS: group by "customer_id" having "total" > ?
      final builder = QueryBuilder(
        client,
      ).table('orders').groupBy('customer_id').having('total', '>', 100);
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "orders" group by "customer_id" having "total" > \$1',
      );
      expect(sql.bindings, [100]);
    });

    test('HAVING with multiple conditions', () {
      // JS: group by "customer_id" having "total" > ? and "count" >= ?
      final builder = QueryBuilder(client)
          .table('orders')
          .groupBy('customer_id')
          .having('total', '>', 100)
          .having('count', '>=', 5);
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "orders" group by "customer_id" having "total" > \$1 and "count" >= \$2',
      );
      expect(sql.bindings, [100, 5]);
    });

    test('GROUP BY + HAVING combined', () {
      // JS: group by "customer_id", "status" having "amount" >= ?
      final builder = QueryBuilder(client)
          .table('orders')
          .groupBy('customer_id')
          .groupBy('status')
          .having('amount', '>=', 1000);
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "orders" group by "customer_id", "status" having "amount" >= \$1',
      );
      expect(sql.bindings, [1000]);
    });

    test('WHERE + GROUP BY + HAVING + ORDER BY', () {
      // JS: where "status" = ? group by "customer_id" having "total" > ? order by "total" desc
      final builder = QueryBuilder(client)
          .table('orders')
          .where('status', 'active')
          .groupBy('customer_id')
          .having('total', '>', 500)
          .orderBy('total', 'desc');
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "orders" where "status" = \$1 group by "customer_id" having "total" > \$2 order by "total" desc',
      );
      expect(sql.bindings, ['active', 500]);
    });

    test('Complete query with all clauses', () {
      // JS: where "year" = ? group by "customer_id" having "revenue" >= ? order by "revenue" desc limit ?
      final builder = QueryBuilder(client)
          .table('orders')
          .where('year', 2024)
          .groupBy('customer_id')
          .having('revenue', '>=', 10000)
          .orderBy('revenue', 'desc')
          .limit(10);
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "orders" where "year" = \$1 group by "customer_id" having "revenue" >= \$2 order by "revenue" desc limit \$3',
      );
      expect(sql.bindings, [2024, 10000, 10]);
    });
  });

  group('QueryCompiler Step 7 - DISTINCT', () {
    test('Basic DISTINCT', () {
      // JS: select distinct * from "users"
      final builder = QueryBuilder(client).table('users').distinct();
      final sql = builder.toSQL();

      expect(sql.sql, 'select distinct * from "users"');
      expect(sql.bindings, []);
    });

    test('DISTINCT with WHERE', () {
      // JS: select distinct * from "users" where "active" = ?
      final builder = QueryBuilder(
        client,
      ).table('users').distinct().where('active', true);
      final sql = builder.toSQL();

      expect(sql.sql, 'select distinct * from "users" where "active" = \$1');
      expect(sql.bindings, [true]);
    });

    test('DISTINCT with specific columns', () {
      // JS: select distinct "role" from "users"
      final builder = QueryBuilder(client).table('users').distinct(['role']);
      final sql = builder.toSQL();

      expect(sql.sql, 'select distinct "role" from "users"');
      expect(sql.bindings, []);
    });

    test('DISTINCT with ORDER BY', () {
      // JS: select distinct * from "users" order by "name" asc
      final builder = QueryBuilder(
        client,
      ).table('users').distinct().orderBy('name');
      final sql = builder.toSQL();

      expect(sql.sql, 'select distinct * from "users" order by "name" asc');
      expect(sql.bindings, []);
    });

    test('DISTINCT with WHERE + ORDER BY + LIMIT', () {
      // JS: select distinct * from "users" where "status" = ? order by "created_at" desc limit ?
      final builder = QueryBuilder(client)
          .table('users')
          .distinct()
          .where('status', 'active')
          .orderBy('created_at', 'desc')
          .limit(10);
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select distinct * from "users" where "status" = \$1 order by "created_at" desc limit \$2',
      );
      expect(sql.bindings, ['active', 10]);
    });
  });

  group('QueryCompiler Step 8 - JOINs', () {
    test('Basic INNER JOIN', () {
      // JS: select * from "users" inner join "orders" on "users"."id" = "orders"."user_id"
      final builder = QueryBuilder(
        client,
      ).table('users').join('orders', 'users.id', 'orders.user_id');
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "users" inner join "orders" on "users"."id" = "orders"."user_id"',
      );
      expect(sql.bindings, []);
    });

    test('LEFT JOIN', () {
      // JS: select * from "users" left join "orders" on "users"."id" = "orders"."user_id"
      final builder = QueryBuilder(
        client,
      ).table('users').leftJoin('orders', 'users.id', 'orders.user_id');
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "users" left join "orders" on "users"."id" = "orders"."user_id"',
      );
      expect(sql.bindings, []);
    });

    test('JOIN with WHERE', () {
      // JS: ... inner join ... where "users"."active" = ?
      final builder = QueryBuilder(client)
          .table('users')
          .join('orders', 'users.id', 'orders.user_id')
          .where('users.active', true);
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "users" inner join "orders" on "users"."id" = "orders"."user_id" where "users"."active" = \$1',
      );
      expect(sql.bindings, [true]);
    });

    test('JOIN with SELECT columns', () {
      // JS: select "users"."name", "orders"."total" from "users" inner join "orders" on ...
      final builder = QueryBuilder(client)
          .table('users')
          .select(['users.name', 'orders.total'])
          .join('orders', 'users.id', 'orders.user_id');
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select "users"."name", "orders"."total" from "users" inner join "orders" on "users"."id" = "orders"."user_id"',
      );
      expect(sql.bindings, []);
    });

    test('Multiple JOINs', () {
      // JS: ... inner join "orders" ... inner join "products" ...
      final builder = QueryBuilder(client)
          .table('users')
          .join('orders', 'users.id', 'orders.user_id')
          .join('products', 'orders.product_id', 'products.id');
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "users" inner join "orders" on "users"."id" = "orders"."user_id" inner join "products" on "orders"."product_id" = "products"."id"',
      );
      expect(sql.bindings, []);
    });

    test('LEFT JOIN with WHERE', () {
      // JS: ... left join ... where "users"."status" = ?
      final builder = QueryBuilder(client)
          .table('users')
          .leftJoin('orders', 'users.id', 'orders.user_id')
          .where('users.status', 'active');
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "users" left join "orders" on "users"."id" = "orders"."user_id" where "users"."status" = \$1',
      );
      expect(sql.bindings, ['active']);
    });

    test('JOIN with ORDER BY', () {
      // JS: ... inner join ... order by "users"."created_at" desc
      final builder = QueryBuilder(client)
          .table('users')
          .join('orders', 'users.id', 'orders.user_id')
          .orderBy('users.created_at', 'desc');
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "users" inner join "orders" on "users"."id" = "orders"."user_id" order by "users"."created_at" desc',
      );
      expect(sql.bindings, []);
    });

    test('Complex query (JOIN + WHERE + ORDER BY + LIMIT)', () {
      // JS: select ... inner join ... where ... order by ... limit ?
      final builder = QueryBuilder(client)
          .table('users')
          .select(['users.name', 'orders.total'])
          .join('orders', 'users.id', 'orders.user_id')
          .where('orders.status', 'completed')
          .orderBy('orders.total', 'desc')
          .limit(10);
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select "users"."name", "orders"."total" from "users" inner join "orders" on "users"."id" = "orders"."user_id" where "orders"."status" = \$1 order by "orders"."total" desc limit \$2',
      );
      expect(sql.bindings, ['completed', 10]);
    });

    test('Mixed INNER and LEFT JOINs', () {
      // JS: ... inner join "orders" ... left join "reviews" ...
      final builder = QueryBuilder(client)
          .table('users')
          .join('orders', 'users.id', 'orders.user_id')
          .leftJoin('reviews', 'orders.id', 'reviews.order_id');
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "users" inner join "orders" on "users"."id" = "orders"."user_id" left join "reviews" on "orders"."id" = "reviews"."order_id"',
      );
      expect(sql.bindings, []);
    });

    test('JOIN with GROUP BY and HAVING', () {
      // JS: select ... inner join ... group by ... having "count" > ?
      final builder = QueryBuilder(client)
          .table('users')
          .select(['users.id', 'users.name'])
          .join('orders', 'users.id', 'orders.user_id')
          .groupBy('users.id')
          .groupBy('users.name')
          .having('count', '>', 5);
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select "users"."id", "users"."name" from "users" inner join "orders" on "users"."id" = "orders"."user_id" group by "users"."id", "users"."name" having "count" > \$1',
      );
      expect(sql.bindings, [5]);
    });
  });

  group('QueryCompiler Step 9 - Advanced JOINs', () {
    test('Callback-based join - simple ON', () {
      final builder = QueryBuilder(client).table('users').join('orders', (j) {
        j.on('users.id', 'orders.user_id');
      });
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "users" inner join "orders" on "users"."id" = "orders"."user_id"',
      );
      expect(sql.bindings, []);
    });

    test('Callback-based join - multiple AND ON', () {
      final builder = QueryBuilder(client).table('users').join('orders', (j) {
        j
            .on('users.id', 'orders.user_id')
            .andOn('users.region', 'orders.region');
      });
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "users" inner join "orders" on "users"."id" = "orders"."user_id" and "users"."region" = "orders"."region"',
      );
      expect(sql.bindings, []);
    });

    test('Callback-based join - OR ON', () {
      final builder = QueryBuilder(client).table('users').join('orders', (j) {
        j.on('users.id', 'orders.user_id').orOn('users.email', 'orders.email');
      });
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "users" inner join "orders" on "users"."id" = "orders"."user_id" or "users"."email" = "orders"."email"',
      );
      expect(sql.bindings, []);
    });

    test('Callback-based join - mixed AND/OR', () {
      final builder = QueryBuilder(client).table('users').join('orders', (j) {
        j
            .on('users.id', 'orders.user_id')
            .andOn('users.active', 'orders.active')
            .orOn('users.status', 'premium');
      });
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "users" inner join "orders" on "users"."id" = "orders"."user_id" and "users"."active" = "orders"."active" or "users"."status" = "premium"',
      );
      expect(sql.bindings, []);
    });

    test('Callback-based join - with explicit operators', () {
      final builder = QueryBuilder(client).table('users').join('orders', (j) {
        j
            .on('users.id', '=', 'orders.user_id')
            .andOn('orders.total', '>', '1000');
      });
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "users" inner join "orders" on "users"."id" = "orders"."user_id" and "orders"."total" > "1000"',
      );
      expect(sql.bindings, []);
    });

    test('LEFT JOIN with callback', () {
      final builder = QueryBuilder(client).table('users').leftJoin('profiles', (
        j,
      ) {
        j.on('users.id', 'profiles.user_id');
      });
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "users" left join "profiles" on "users"."id" = "profiles"."user_id"',
      );
      expect(sql.bindings, []);
    });

    test('RIGHT JOIN with callback', () {
      final builder = QueryBuilder(client).table('orders').rightJoin(
        'products',
        (j) {
          j.on('orders.product_id', 'products.id');
        },
      );
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "orders" right join "products" on "orders"."product_id" = "products"."id"',
      );
      expect(sql.bindings, []);
    });

    test('FULL OUTER JOIN', () {
      final builder = QueryBuilder(client)
          .table('users')
          .fullOuterJoin('profiles', 'users.id', 'profiles.user_id');
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "users" full outer join "profiles" on "users"."id" = "profiles"."user_id"',
      );
      expect(sql.bindings, []);
    });

    test('CROSS JOIN', () {
      final builder = QueryBuilder(
        client,
      ).table('users').crossJoin('categories');
      final sql = builder.toSQL();

      expect(sql.sql, 'select * from "users" cross join "categories"');
      expect(sql.bindings, []);
    });

    test('Mixed simple and callback joins', () {
      final builder = QueryBuilder(client)
          .table('users')
          .join('orders', 'users.id', 'orders.user_id')
          .leftJoin('reviews', (j) {
            j.on('orders.id', 'reviews.order_id');
          });
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "users" inner join "orders" on "users"."id" = "orders"."user_id" left join "reviews" on "orders"."id" = "reviews"."order_id"',
      );
      expect(sql.bindings, []);
    });

    test('Callback join with WHERE and ORDER BY', () {
      final builder = QueryBuilder(client)
          .table('users')
          .join('orders', (j) {
            j
                .on('users.id', 'orders.user_id')
                .andOn('orders.status', 'completed');
          })
          .where('users.active', true)
          .orderBy('users.created_at', 'desc');
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "users" inner join "orders" on "users"."id" = "orders"."user_id" and "orders"."status" = "completed" where "users"."active" = \$1 order by "users"."created_at" desc',
      );
      expect(sql.bindings, [true]);
    });

    test('Complex callback join with all clauses', () {
      final builder = QueryBuilder(client)
          .table('users')
          .select(['users.id', 'users.name'])
          .join('orders', (j) {
            j
                .on('users.id', 'orders.user_id')
                .andOn('users.region', 'orders.region');
          })
          .where('orders.status', 'completed')
          .groupBy('users.id')
          .groupBy('users.name')
          .orderBy('users.name')
          .limit(10);
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select "users"."id", "users"."name" from "users" inner join "orders" on "users"."id" = "orders"."user_id" and "users"."region" = "orders"."region" where "orders"."status" = \$1 group by "users"."id", "users"."name" order by "users"."name" asc limit \$2',
      );
      expect(sql.bindings, ['completed', 10]);
    });
  });

  group('QueryCompiler Step 10 - INSERT', () {
    test('Single row insert', () {
      final builder = QueryBuilder(
        client,
      ).table('users').insert({'name': 'John', 'email': 'john@example.com'});
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'insert into "users" ("name", "email") values (\$1, \$2)',
      );
      expect(sql.bindings, ['John', 'john@example.com']);
    });

    test('Multiple rows insert', () {
      final builder = QueryBuilder(client).table('users').insert([
        {'name': 'John', 'email': 'john@example.com'},
        {'name': 'Jane', 'email': 'jane@example.com'},
      ]);
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'insert into "users" ("name", "email") values (\$1, \$2), (\$3, \$4)',
      );
      expect(sql.bindings, [
        'John',
        'john@example.com',
        'Jane',
        'jane@example.com',
      ]);
    });

    test('Insert with RETURNING - single column', () {
      final builder = QueryBuilder(client)
          .table('users')
          .insert({'name': 'John', 'email': 'john@example.com'})
          .returning(['id']);
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'insert into "users" ("name", "email") values (\$1, \$2) returning "id"',
      );
      expect(sql.bindings, ['John', 'john@example.com']);
    });

    test('Insert with RETURNING - multiple columns', () {
      final builder = QueryBuilder(client)
          .table('users')
          .insert({'name': 'John', 'email': 'john@example.com'})
          .returning(['id', 'name', 'created_at']);
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'insert into "users" ("name", "email") values (\$1, \$2) returning "id", "name", "created_at"',
      );
      expect(sql.bindings, ['John', 'john@example.com']);
    });

    test('Insert with NULL values', () {
      final builder = QueryBuilder(
        client,
      ).table('users').insert({'name': 'John', 'email': null, 'phone': null});
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'insert into "users" ("name", "email", "phone") values (\$1, \$2, \$3)',
      );
      expect(sql.bindings, ['John', null, null]);
    });

    test('Insert with different data types', () {
      final builder = QueryBuilder(client).table('products').insert({
        'name': 'Widget',
        'price': 19.99,
        'quantity': 100,
        'active': true,
      });
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'insert into "products" ("name", "price", "quantity", "active") values (\$1, \$2, \$3, \$4)',
      );
      expect(sql.bindings, ['Widget', 19.99, 100, true]);
    });

    test('Multiple rows with RETURNING', () {
      final builder = QueryBuilder(client)
          .table('users')
          .insert([
            {'name': 'John', 'age': 30},
            {'name': 'Jane', 'age': 25},
          ])
          .returning(['id', 'name']);
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'insert into "users" ("name", "age") values (\$1, \$2), (\$3, \$4) returning "id", "name"',
      );
      expect(sql.bindings, ['John', 30, 'Jane', 25]);
    });

    test('Insert with schema qualification', () {
      final builder = QueryBuilder(client).table('public.users').insert({
        'name': 'John',
        'email': 'john@example.com',
      });
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'insert into "public"."users" ("name", "email") values (\$1, \$2)',
      );
      expect(sql.bindings, ['John', 'john@example.com']);
    });

    test('Insert empty array should throw', () {
      expect(
        () => QueryBuilder(client).table('users').insert([]).toSQL(),
        throwsArgumentError,
      );
    });

    test('Insert empty object should throw', () {
      expect(
        () => QueryBuilder(client).table('users').insert({}).toSQL(),
        throwsArgumentError,
      );
    });
  });

  group('QueryCompiler Step 11 - UPDATE', () {
    test('Basic update with WHERE', () {
      final builder = QueryBuilder(
        client,
      ).table('users').where('id', 1).update({'name': 'John Updated'});
      final sql = builder.toSQL();

      expect(sql.sql, 'update "users" set "name" = \$1 where "id" = \$2');
      expect(sql.bindings, ['John Updated', 1]);
      expect(sql.method, 'update');
    });

    test('Update multiple columns', () {
      final builder = QueryBuilder(client).table('users').where('id', 1).update(
        {'name': 'Jane Doe', 'email': 'jane@example.com', 'age': 30},
      );
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'update "users" set "name" = \$1, "email" = \$2, "age" = \$3 where "id" = \$4',
      );
      expect(sql.bindings, ['Jane Doe', 'jane@example.com', 30, 1]);
    });

    test('Update with multiple WHERE conditions', () {
      final builder = QueryBuilder(client)
          .table('users')
          .where('status', 'active')
          .where('role', 'user')
          .update({'last_login': '2024-01-15'});
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'update "users" set "last_login" = \$1 where "status" = \$2 and "role" = \$3',
      );
      expect(sql.bindings, ['2024-01-15', 'active', 'user']);
    });

    test('Update with RETURNING clause', () {
      final builder = QueryBuilder(client)
          .table('users')
          .where('id', 1)
          .update({'name': 'Updated Name'})
          .returning(['id', 'name', 'updated_at']);
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'update "users" set "name" = \$1 where "id" = \$2 returning "id", "name", "updated_at"',
      );
      expect(sql.bindings, ['Updated Name', 1]);
    });

    test('Update with NULL value', () {
      final builder = QueryBuilder(
        client,
      ).table('users').where('id', 1).update({'middle_name': null});
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'update "users" set "middle_name" = \$1 where "id" = \$2',
      );
      expect(sql.bindings, [null, 1]);
    });

    test('Increment operation', () {
      final builder = QueryBuilder(
        client,
      ).table('users').where('id', 1).increment('login_count', 1);
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'update "users" set "login_count" = "login_count" + \$1 where "id" = \$2',
      );
      expect(sql.bindings, [1, 1]);
      expect(sql.method, 'update');
    });

    test('Decrement operation', () {
      final builder = QueryBuilder(
        client,
      ).table('products').where('id', 100).decrement('stock', 5);
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'update "products" set "stock" = "stock" - \$1 where "id" = \$2',
      );
      expect(sql.bindings, [5, 100]);
    });

    test('Increment with additional updates', () {
      final builder = QueryBuilder(client)
          .table('users')
          .where('id', 1)
          .increment('login_count', 1)
          .update({'last_login': '2024-01-15'});
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'update "users" set "last_login" = \$1, "login_count" = "login_count" + \$2 where "id" = \$3',
      );
      expect(sql.bindings, ['2024-01-15', 1, 1]);
    });

    test('Update with whereIn', () {
      final builder = QueryBuilder(
        client,
      ).table('users').whereIn('id', [1, 2, 3]).update({'status': 'inactive'});
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'update "users" set "status" = \$1 where "id" in (\$2, \$3, \$4)',
      );
      expect(sql.bindings, ['inactive', 1, 2, 3]);
    });

    test('Update with complex WHERE and RETURNING', () {
      final builder = QueryBuilder(client)
          .table('orders')
          .where('status', 'pending')
          .where('created_at', '<', '2024-01-01')
          .update({'status': 'cancelled'})
          .returning(['id', 'status']);
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'update "orders" set "status" = \$1 where "status" = \$2 and "created_at" < \$3 returning "id", "status"',
      );
      expect(sql.bindings, ['cancelled', 'pending', '2024-01-01']);
    });
  });

  group('QueryCompiler Step 12 - DELETE', () {
    test('Basic DELETE with WHERE', () {
      final builder = QueryBuilder(
        client,
      ).table('users').where('id', 1).delete();
      final sql = builder.toSQL();

      expect(sql.sql, 'delete from "users" where "id" = \$1');
      expect(sql.bindings, [1]);
      expect(sql.method, 'delete');
    });

    test('DELETE with multiple WHERE conditions', () {
      final builder = QueryBuilder(client)
          .table('users')
          .where('status', 'inactive')
          .where('created_at', '<', '2020-01-01')
          .delete();
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'delete from "users" where "status" = \$1 and "created_at" < \$2',
      );
      expect(sql.bindings, ['inactive', '2020-01-01']);
    });

    test('DELETE with RETURNING', () {
      final builder = QueryBuilder(
        client,
      ).table('users').where('id', 1).delete(['id', 'name']);
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'delete from "users" where "id" = \$1 returning "id", "name"',
      );
      expect(sql.bindings, [1]);
    });

    test('DELETE with WHERE IN', () {
      final builder = QueryBuilder(
        client,
      ).table('users').whereIn('id', [1, 2, 3, 4, 5]).delete();
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'delete from "users" where "id" in (\$1, \$2, \$3, \$4, \$5)',
      );
      expect(sql.bindings, [1, 2, 3, 4, 5]);
    });

    test('DELETE with WHERE NULL', () {
      final builder = QueryBuilder(
        client,
      ).table('users').whereNull('deleted_at').delete();
      final sql = builder.toSQL();

      expect(sql.sql, 'delete from "users" where "deleted_at" is null');
      expect(sql.bindings, []);
    });

    test('DELETE with OR WHERE', () {
      final builder = QueryBuilder(client)
          .table('users')
          .where('status', 'banned')
          .orWhere('verified', false)
          .delete();
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'delete from "users" where "status" = \$1 or "verified" = \$2',
      );
      expect(sql.bindings, ['banned', false]);
    });

    test('DELETE with complex WHERE and RETURNING', () {
      final builder = QueryBuilder(client)
          .table('orders')
          .where('status', 'cancelled')
          .where('created_at', '<', '2023-01-01')
          .delete(['id', 'status', 'total']);
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'delete from "orders" where "status" = \$1 and "created_at" < \$2 returning "id", "status", "total"',
      );
      expect(sql.bindings, ['cancelled', '2023-01-01']);
    });

    test('DELETE with schema qualification', () {
      final builder = QueryBuilder(
        client,
      ).table('public.users').where('id', 100).delete();
      final sql = builder.toSQL();

      expect(sql.sql, 'delete from "public"."users" where "id" = \$1');
      expect(sql.bindings, [100]);
    });
  });

  group('QueryCompiler Step 13 - Raw Queries', () {
    test('Raw with array bindings', () {
      final raw = client.raw('select * from users where id = ?', [1]);
      final sql = raw.toSQL();

      expect(sql.sql, 'select * from users where id = \$1');
      expect(sql.bindings, [1]);
      expect(sql.method, 'raw');
    });

    test('Raw with multiple array bindings', () {
      final raw = client.raw('select * from users where id = ? and age > ?', [
        1,
        18,
      ]);
      final sql = raw.toSQL();

      expect(sql.sql, 'select * from users where id = \$1 and age > \$2');
      expect(sql.bindings, [1, 18]);
    });

    test('Raw with identifier wrapping (??)', () {
      final raw = client.raw('select ?? from ??', ['id', 'users']);
      final sql = raw.toSQL();

      expect(sql.sql, 'select "id" from "users"');
      expect(sql.bindings, []);
    });

    test('Raw with named bindings', () {
      final raw = client.raw('select * from users where id = :id', {'id': 1});
      final sql = raw.toSQL();

      expect(sql.sql, 'select * from users where id = \$1');
      expect(sql.bindings, [1]);
    });

    test('Raw in WHERE clause', () {
      final builder = QueryBuilder(
        client,
      ).table('users').where(client.raw('age > 18'));
      final sql = builder.toSQL();

      expect(sql.sql, 'select * from "users" where age > 18');
      expect(sql.bindings, []);
    });

    test('Raw in SELECT clause', () {
      final builder = QueryBuilder(
        client,
      ).table('users').select(client.raw('count(*) as total'));
      final sql = builder.toSQL();

      expect(sql.sql, 'select count(*) as total from "users"');
      expect(sql.bindings, []);
    });

    test('Raw with bindings in WHERE', () {
      final builder = QueryBuilder(
        client,
      ).table('users').where(client.raw('age > ?', [21]));
      final sql = builder.toSQL();

      expect(sql.sql, 'select * from "users" where age > \$1');
      expect(sql.bindings, [21]);
    });

    test('Raw with named identifier bindings', () {
      final raw = client.raw('select :column: from :table:', {
        'column': 'name',
        'table': 'users',
      });
      final sql = raw.toSQL();

      expect(sql.sql, 'select "name" from "users"');
      expect(sql.bindings, []);
    });
  });

  // QueryCompiler Step 14 - Aggregate Functions
  group('QueryCompiler Step 14 - Aggregate Functions', () {
    test('Basic count', () {
      final builder = QueryBuilder(client).table('users').count('*');
      final sql = builder.toSQL();

      expect(sql.sql, 'select count(*) from "users"');
      expect(sql.bindings, []);
    });

    test('Count with explicit alias', () {
      final builder = QueryBuilder(
        client,
      ).table('users').count('*', AggregateOptions(as: 'total'));
      final sql = builder.toSQL();

      expect(sql.sql, 'select count(*) as "total" from "users"');
      expect(sql.bindings, []);
    });

    test('Sum with column', () {
      final builder = QueryBuilder(client).table('orders').sum('amount');
      final sql = builder.toSQL();

      expect(sql.sql, 'select sum("amount") from "orders"');
      expect(sql.bindings, []);
    });

    test('Avg with alias', () {
      final builder = QueryBuilder(
        client,
      ).table('products').avg('price', AggregateOptions(as: 'average_price'));
      final sql = builder.toSQL();

      expect(sql.sql, 'select avg("price") as "average_price" from "products"');
      expect(sql.bindings, []);
    });

    test('Min and max', () {
      final builder = QueryBuilder(
        client,
      ).table('transactions').min('created_at').max('updated_at');
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select min("created_at"), max("updated_at") from "transactions"',
      );
      expect(sql.bindings, []);
    });

    test('Count distinct', () {
      final builder = QueryBuilder(
        client,
      ).table('orders').countDistinct('user_id');
      final sql = builder.toSQL();

      expect(sql.sql, 'select count(distinct "user_id") from "orders"');
      expect(sql.bindings, []);
    });

    test('Sum distinct with alias', () {
      final builder = QueryBuilder(client)
          .table('payments')
          .sumDistinct('amount', AggregateOptions(as: 'unique_total'));
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select sum(distinct "amount") as "unique_total" from "payments"',
      );
      expect(sql.bindings, []);
    });

    test('Avg distinct', () {
      final builder = QueryBuilder(
        client,
      ).table('scores').avgDistinct('points');
      final sql = builder.toSQL();

      expect(sql.sql, 'select avg(distinct "points") from "scores"');
      expect(sql.bindings, []);
    });

    test('Count with inline alias', () {
      final builder = QueryBuilder(
        client,
      ).table('users').count('id as user_count');
      final sql = builder.toSQL();

      expect(sql.sql, 'select count("id") as "user_count" from "users"');
      expect(sql.bindings, []);
    });

    test('Aggregate with WHERE clause', () {
      final builder = QueryBuilder(client)
          .table('orders')
          .count('*', AggregateOptions(as: 'total'))
          .where('status', '=', 'completed');
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select count(*) as "total" from "orders" where "status" = \$1',
      );
      expect(sql.bindings, ['completed']);
    });

    test('Multiple aggregates', () {
      final builder = QueryBuilder(client)
          .table('sales')
          .count('*', AggregateOptions(as: 'total_sales'))
          .sum('amount', AggregateOptions(as: 'total_amount'))
          .avg('amount', AggregateOptions(as: 'average_amount'));
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select count(*) as "total_sales", sum("amount") as "total_amount", '
        'avg("amount") as "average_amount" from "sales"',
      );
      expect(sql.bindings, []);
    });

    test('Count distinct with multiple columns', () {
      final builder = QueryBuilder(
        client,
      ).table('events').countDistinct(['user_id', 'event_type']);
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select count(distinct "user_id", "event_type") from "events"',
      );
      expect(sql.bindings, []);
    });
  });

  group('QueryCompiler Step 15 - first/pluck and lock/wait modes', () {
    test('first() compiles to SELECT with LIMIT 1', () {
      final builder = QueryBuilder(client).table('users').first('id');
      final sql = builder.toSQL();

      expect(sql.sql, 'select "id" from "users" limit \$1');
      expect(sql.bindings, [1]);
      expect(sql.method, 'first');
    });

    test('pluck() compiles selected single column', () {
      final builder = QueryBuilder(client).table('users').pluck('email');
      final sql = builder.toSQL();

      expect(sql.sql, 'select "email" from "users"');
      expect(sql.bindings, []);
      expect(sql.method, 'pluck');
      expect(sql.pluck, 'email');
    });

    test('pluck() normalizes dotted column name metadata', () {
      final builder = QueryBuilder(client).table('users').pluck('users.email');
      final sql = builder.toSQL();

      expect(sql.sql, 'select "users"."email" from "users"');
      expect(sql.pluck, 'email');
    });

    test('forUpdate() + skipLocked() on postgres-like client', () {
      final builder = QueryBuilder(
        client,
      ).table('users').forUpdate().skipLocked();
      final sql = builder.toSQL();

      expect(sql.sql, 'select * from "users" for update skip locked');
      expect(sql.bindings, []);
    });

    test('forShare() with table list on postgres-like client', () {
      final builder = QueryBuilder(client).table('users').forShare(['users']);
      final sql = builder.toSQL();

      expect(sql.sql, 'select * from "users" for share of "users"');
      expect(sql.bindings, []);
    });

    test('forNoKeyUpdate() + noWait() on postgres-like client', () {
      final builder = QueryBuilder(
        client,
      ).table('users').forNoKeyUpdate().noWait();
      final sql = builder.toSQL();

      expect(sql.sql, 'select * from "users" for no key update nowait');
      expect(sql.bindings, []);
    });

    test('forShare() on MySQL compiles lock in share mode', () {
      final my = MySQLMockClient();
      final builder = QueryBuilder(my).table('users').forShare();
      final sql = builder.toSQL();

      expect(sql.sql, 'select * from `users` lock in share mode');
      expect(sql.bindings, []);
    });

    test('skipLocked() requires prior lock mode', () {
      expect(
        () => QueryBuilder(client).table('users').skipLocked(),
        throwsA(
          predicate(
            (e) =>
                e is StateError &&
                e.message.toString().contains('.forShare() or .forUpdate()'),
          ),
        ),
      );
    });

    test('noWait() and skipLocked() are mutually exclusive', () {
      expect(
        () => QueryBuilder(
          client,
        ).table('users').forUpdate().noWait().skipLocked(),
        throwsA(
          predicate(
            (e) =>
                e is StateError &&
                e.message.toString().contains('cannot be used together'),
          ),
        ),
      );
    });

    test('forNoKeyUpdate() is rejected on MySQL', () {
      final my = MySQLMockClient();
      final builder = QueryBuilder(my).table('users').forNoKeyUpdate();

      expect(
        () => builder.toSQL(),
        throwsA(
          predicate(
            (e) =>
                e is StateError &&
                e.message.toString().contains('only supported on PostgreSQL'),
          ),
        ),
      );
    });
  });

  group('QueryCompiler Step 16 - Advanced JOIN ON clauses', () {
    test('Join onVal adds bound parameter in ON clause', () {
      final builder = QueryBuilder(client).table('users').join('orders', (j) {
        j
            .on('users.id', 'orders.user_id')
            .andOnVal('orders.status', '=', 'completed');
      });
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "users" inner join "orders" on "users"."id" = "orders"."user_id" and "orders"."status" = \$1',
      );
      expect(sql.bindings, ['completed']);
    });

    test('Join onIn compiles IN list with bindings', () {
      final builder = QueryBuilder(client).table('users').join('orders', (j) {
        j.on('users.id', 'orders.user_id').andOnIn('orders.status', [
          'paid',
          'pending',
        ]);
      });
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "users" inner join "orders" on "users"."id" = "orders"."user_id" and "orders"."status" in (\$1, \$2)',
      );
      expect(sql.bindings, ['paid', 'pending']);
    });

    test('Join onNull and onNotNull compile NULL checks', () {
      final builder = QueryBuilder(client).table('users').join('orders', (j) {
        j
            .on('users.id', 'orders.user_id')
            .andOnNull('orders.deleted_at')
            .orOnNotNull('orders.archived_at');
      });
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "users" inner join "orders" on "users"."id" = "orders"."user_id" and "orders"."deleted_at" is null or "orders"."archived_at" is not null',
      );
      expect(sql.bindings, []);
    });

    test('Join onBetween and onNotBetween compile ranges', () {
      final builder = QueryBuilder(client).table('users').join('orders', (j) {
        j
            .on('users.id', 'orders.user_id')
            .andOnBetween('orders.total', [10, 100])
            .orOnNotBetween('orders.discount', [5, 20]);
      });
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "users" inner join "orders" on "users"."id" = "orders"."user_id" and "orders"."total" between \$1 and \$2 or "orders"."discount" not between \$3 and \$4',
      );
      expect(sql.bindings, [10, 100, 5, 20]);
    });

    test('Join onExists and onNotExists compile subqueries', () {
      final builder = QueryBuilder(client).table('users').join('orders', (j) {
        j
            .on('users.id', 'orders.user_id')
            .andOnExists((qb) {
              qb
                  .select(['id'])
                  .from('payments')
                  .whereColumn('payments.order_id', '=', 'orders.id');
            })
            .orOnNotExists((qb) {
              qb
                  .select(['id'])
                  .from('refunds')
                  .whereColumn('refunds.order_id', '=', 'orders.id');
            });
      });
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "users" inner join "orders" on "users"."id" = "orders"."user_id" and exists (select "id" from "payments" where "payments"."order_id" = "orders"."id") or not exists (select "id" from "refunds" where "refunds"."order_id" = "orders"."id")',
      );
      expect(sql.bindings, []);
    });

    test('Join onWrapped groups nested ON conditions', () {
      final builder = QueryBuilder(client).table('users').join('orders', (j) {
        j.on('users.id', 'orders.user_id').andOn((nested) {
          nested
              .onVal('orders.status', '=', 'completed')
              .orOnVal('orders.status', '=', 'shipped');
        });
      });
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "users" inner join "orders" on "users"."id" = "orders"."user_id" and ("orders"."status" = \$1 or "orders"."status" = \$2)',
      );
      expect(sql.bindings, ['completed', 'shipped']);
    });

    test('Join using() compiles USING clause', () {
      final builder = QueryBuilder(client).table('users').join('orders', (j) {
        j.using(['user_id']);
      });
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "users" inner join "orders" using ("user_id")',
      );
      expect(sql.bindings, []);
    });

    test('Join onIn with multi-column tuple values', () {
      final builder = QueryBuilder(client).table('users').join('orders', (j) {
        j.onIn(
          ['orders.type', 'orders.state'],
          [
            ['online', 'paid'],
            ['retail', 'pending'],
          ],
        );
      });
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "users" inner join "orders" on ("orders"."type", "orders"."state") in ((\$1, \$2),(\$3, \$4))',
      );
      expect(sql.bindings, ['online', 'paid', 'retail', 'pending']);
    });

    test('Join onJsonPathEquals for postgres-like client', () {
      final builder = QueryBuilder(client).table('users').join('orders', (j) {
        j.onJsonPathEquals('users.meta', r'$.id', 'orders.meta', r'$.user_id');
      });
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from "users" inner join "orders" on jsonb_path_query_first("users"."meta", \$1) = jsonb_path_query_first("orders"."meta", \$2)',
      );
      expect(sql.bindings, [r'$.id', r'$.user_id']);
    });

    test('Join onJsonPathEquals for mysql client uses json_extract', () {
      final my = MySQLMockClient();
      final builder = QueryBuilder(my).table('users').join('orders', (j) {
        j.onJsonPathEquals('users.meta', r'$.id', 'orders.meta', r'$.user_id');
      });
      final sql = builder.toSQL();

      expect(
        sql.sql,
        'select * from `users` inner join `orders` on json_extract(`users`.`meta`, ?) = json_extract(`orders`.`meta`, ?)',
      );
      expect(sql.bindings, [r'$.id', r'$.user_id']);
    });
  });

  group('Dialect capability guards', () {
    test('RETURNING throws on mysql dialect', () {
      final my = MySQLMockClient();
      expect(
        () => QueryBuilder(
          my,
        ).table('users').insert({'name': 'John'}).returning(['id']).toSQL(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('RETURNING is not supported'),
          ),
        ),
      );
    });

    test('RETURNING throws on sqlite dialect', () {
      final sqlite = SqliteMockClient();
      expect(
        () => QueryBuilder(
          sqlite,
        ).table('users').insert({'name': 'John'}).returning(['id']).toSQL(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('RETURNING is not supported'),
          ),
        ),
      );
    });

    test('fullOuterJoin throws on sqlite dialect', () {
      final sqlite = SqliteMockClient();
      expect(
        () => QueryBuilder(sqlite)
            .table('users')
            .fullOuterJoin('profiles', 'users.id', 'profiles.user_id')
            .toSQL(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('FULL OUTER JOIN is not supported'),
          ),
        ),
      );
    });
  });
}
