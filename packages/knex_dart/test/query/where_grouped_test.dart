import 'package:test/test.dart';
import 'package:knex_dart/src/query/query_builder.dart';
import '../mocks/mock_client.dart';

void main() {
  late MockClient client;

  setUp(() {
    client = MockClient();
  });

  group('Grouped / Nested WHERE clauses', () {
    test('Test 1: Simple grouped where using closure', () {
      final query = QueryBuilder(client)
          .table('users')
          .where('active', true)
          .where((builder) {
            builder.where('age', '>', 18).orWhere('role', 'admin');
          });

      final sql = query.toSQL();

      // JS: select * from "users" where "active" = ? and ("age" > ? or "role" = ?)
      expect(
        sql.sql,
        'select * from "users" where "active" = \$1 and ("age" > \$2 or "role" = \$3)',
      );
      expect(sql.bindings, [true, 18, 'admin']);
    });

    test('Test 2: Grouped orWhere using closure', () {
      final query = QueryBuilder(client)
          .table('users')
          .where('status', 'active')
          .orWhere((builder) {
            builder.where('status', 'pending').whereNotNull('last_login');
          });

      final sql = query.toSQL();

      // JS: select * from "users" where "status" = ? or ("status" = ? and "last_login" is not null)
      expect(
        sql.sql,
        'select * from "users" where "status" = \$1 or ("status" = \$2 and "last_login" is not null)',
      );
      expect(sql.bindings, ['active', 'pending']);
    });

    test('Test 3: Multiple nested closures', () {
      final query = QueryBuilder(client)
          .table('products')
          .where('published', true)
          .where((builder) {
            builder.where('price', '<', 50).orWhere((innerBuilder) {
              innerBuilder.where('on_sale', true).where('stock', '>', 0);
            });
          });

      final sql = query.toSQL();

      // JS: select * from "products" where "published" = ? and ("price" < ? or ("on_sale" = ? and "stock" > ?))
      expect(
        sql.sql,
        'select * from "products" where "published" = \$1 and ("price" < \$2 or ("on_sale" = \$3 and "stock" > \$4))',
      );
      expect(sql.bindings, [true, 50, true, 0]);
    });

    test('Test 4: Not Grouped where', () {
      final query = QueryBuilder(client).table('users').whereNot((builder) {
        builder.where('banned', true).orWhere('deleted', true);
      });

      final sql = query.toSQL();

      // JS: select * from "users" where not ("banned" = ? or "deleted" = ?)
      expect(
        sql.sql,
        'select * from "users" where not ("banned" = \$1 or "deleted" = \$2)',
      );
      expect(sql.bindings, [true, true]);
    });
  });
}
