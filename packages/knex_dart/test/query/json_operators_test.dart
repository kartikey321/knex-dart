import 'package:test/test.dart';
import 'package:knex_dart/src/query/json_builder.dart';
import '../mocks/mock_client.dart';

void main() {
  group('JSON Operators (PostgreSQL)', () {
    late MockClient pg;

    setUp(() => pg = MockClient(driverName: 'pg'));

    test('whereJsonObject (aliased to where value = jsonEncode)', () {
      final sql = pg.queryBuilder().from('users').whereJsonObject('profile', {
        'role': 'admin',
      }).toSQL();
      expect(sql.sql, 'select * from "users" where "profile" = \$1');
      expect(sql.bindings, ['{"role":"admin"}']);
    });

    test('orWhereJsonObject', () {
      final sql = pg
          .queryBuilder()
          .from('users')
          .where('id', 1)
          .orWhereJsonObject('profile', {'role': 'admin'})
          .toSQL();
      expect(
        sql.sql,
        'select * from "users" where "id" = \$1 or "profile" = \$2',
      );
    });

    test('whereJsonPath with integer inference', () {
      final sql = pg
          .queryBuilder()
          .from('users')
          .whereJsonPath('settings', '\$.theme', '=', 1)
          .toSQL();
      expect(
        sql.sql,
        'select * from "users" where jsonb_path_query_first("settings", \$1)::int = \$2',
      );
      expect(sql.bindings, ['\$.theme', 1]);
    });

    test('whereJsonPath with float inference', () {
      final sql = pg
          .queryBuilder()
          .from('users')
          .whereJsonPath('settings', '\$.score', '>', 5.5)
          .toSQL();
      expect(
        sql.sql,
        'select * from "users" where jsonb_path_query_first("settings", \$1)::float > \$2',
      );
      expect(sql.bindings, ['\$.score', 5.5]);
    });

    test('whereJsonPath with string (no cast)', () {
      final sql = pg
          .queryBuilder()
          .from('users')
          .whereJsonPath('settings', '\$.role', '=', 'admin')
          .toSQL();
      expect(
        sql.sql,
        'select * from "users" where jsonb_path_query_first("settings", \$1) #>> \'{}\' = \$2',
      );
      expect(sql.bindings, ['\$.role', 'admin']);
    });

    test('whereJsonSupersetOf (Map)', () {
      final sql = pg.queryBuilder().from('users').whereJsonSupersetOf(
        'settings',
        {'a': 1},
      ).toSQL();
      expect(sql.sql, 'select * from "users" where "settings" @> \$1');
      expect(sql.bindings, ['{"a":1}']);
    });

    test('whereJsonSupersetOf (String)', () {
      // should not double-encode if already a string
      final sql = pg
          .queryBuilder()
          .from('users')
          .whereJsonSupersetOf('settings', '{"a":1}')
          .toSQL();
      expect(sql.bindings, ['{"a":1}']);
    });

    test('whereJsonSubsetOf', () {
      final sql = pg.queryBuilder().from('users').whereJsonSubsetOf(
        'settings',
        {'a': 1},
      ).toSQL();
      expect(sql.sql, 'select * from "users" where "settings" <@ \$1');
      expect(sql.bindings, ['{"a":1}']);
    });
  });

  group('JSON Operators (MySQL & SQLite)', () {
    test('whereJsonPath uses json_extract in MySQL', () {
      final client = MockClient(driverName: 'mysql');
      final sql = client
          .queryBuilder()
          .from('users')
          .whereJsonPath('settings', '\$.theme', '=', 'dark')
          .toSQL();
      expect(
        sql.sql,
        'select * from `users` where json_extract(`settings`, \$1) = \$2',
      );
      expect(sql.bindings, ['\$.theme', 'dark']);
    });

    test('whereJsonPath uses json_extract in SQLite', () {
      final client = MockClient(driverName: 'sqlite');
      final sql = client
          .queryBuilder()
          .from('users')
          .whereJsonPath('settings', '\$.theme', '=', 'dark')
          .toSQL();
      expect(
        sql.sql,
        'select * from "users" where json_extract("settings", \$1) = \$2',
      );
    });

    test(
      'whereJsonSupersetOf falls back to Basic where in unsupported dialects',
      () {
        final client = MockClient(driverName: 'mysql');
        final sql = client.queryBuilder().from('users').whereJsonSupersetOf(
          'settings',
          {'a': 1},
        ).toSQL();
        // Should fall back to '='
        expect(sql.sql, 'select * from `users` where `settings` = \$1');
      },
    );
  });
}
