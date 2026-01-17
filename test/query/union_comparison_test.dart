import 'package:test/test.dart';
import 'package:knex_dart/src/query/query_builder.dart';
import '../mocks/mock_client.dart';

void main() {
  late MockClient client;

  setUp(() {
    client = MockClient();
  });

  group('UNION Operations - Comparison with Knex.js', () {
    test('Simple UNION', () {
      final query1 = QueryBuilder(
        client,
      ).table('users').where('active', '=', true);
      final query2 = QueryBuilder(
        client,
      ).table('users').where('role', '=', 'admin');

      final query = query1.union([query2]);
      final sql = query.toSQL();

      // JS: select * from "users" where "active" = true union select * from "users" where "role" = 'admin'
      expect(
        sql.sql,
        'select * from "users" where "active" = \$1 union select * from "users" where "role" = \$2',
      );
      expect(sql.bindings, [true, 'admin']);
    });

    test('UNION ALL', () {
      final query1 = QueryBuilder(
        client,
      ).table('users').select(['name']).where('active', '=', true);
      final query2 = QueryBuilder(
        client,
      ).table('users').select(['name']).where('role', '=', 'admin');

      final query = query1.unionAll([query2]);
      final sql = query.toSQL();

      // JS: select "name" from "users" where "active" = true union all select "name" from "users" where "role" = 'admin'
      expect(
        sql.sql,
        'select "name" from "users" where "active" = \$1 union all select "name" from "users" where "role" = \$2',
      );
      expect(sql.bindings, [true, 'admin']);
    });

    test('Multiple UNIONs', () {
      final query1 = QueryBuilder(
        client,
      ).table('users').where('type', '=', 'customer');
      final query2 = QueryBuilder(
        client,
      ).table('users').where('type', '=', 'admin');
      final query3 = QueryBuilder(
        client,
      ).table('users').where('type', '=', 'moderator');

      final query = query1.union([query2, query3]);
      final sql = query.toSQL();

      // JS: select * from "users" where "type" = 'customer' union select * from "users" where "type" = 'admin' union select * from "users" where "type" = 'moderator'
      expect(
        sql.sql,
        'select * from "users" where "type" = \$1 union select * from "users" where "type" = \$2 union select * from "users" where "type" = \$3',
      );
      expect(sql.bindings, ['customer', 'admin', 'moderator']);
    });

    test('UNION with ORDER BY and LIMIT', () {
      final query1 = QueryBuilder(
        client,
      ).table('users').where('active', '=', true);
      final query2 = QueryBuilder(
        client,
      ).table('users').where('role', '=', 'admin');

      final query = query1.union([query2]).orderBy('name').limit(10);
      final sql = query.toSQL();

      // JS: select * from "users" where "active" = true union select * from "users" where "role" = 'admin' order by "name" asc limit 10
      expect(
        sql.sql,
        'select * from "users" where "active" = \$1 union select * from "users" where "role" = \$2 order by "name" asc limit \$3',
      );
      expect(sql.bindings, [true, 'admin', 10]);
    });
  });
}
