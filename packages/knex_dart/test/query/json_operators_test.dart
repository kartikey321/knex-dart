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

    test('whereJsonSupersetOf uses json_contains() in MySQL', () {
      // Previously this fell back to a plain `= ?` comparison — silently
      // wrong, since a JSON value is never byte-equal to a superset check.
      // knex.js's mysql-querycompiler wraps in json_contains(); verified
      // against real knex.js.
      final client = MockClient(driverName: 'mysql');
      final sql = client.queryBuilder().from('users').whereJsonSupersetOf(
        'settings',
        {'a': 1},
      ).toSQL();
      expect(sql.sql, 'select * from `users` where json_contains(`settings`,\$1)');
      expect(sql.bindings, ['{"a":1}']);
    });

    test(
      'whereJsonSupersetOf throws on a dialect with no implementation '
      '(SQLite — knex.js itself refuses this: "Json superset where clause '
      'not actually supported by SQLite")',
      () {
        final client = MockClient(driverName: 'sqlite');
        expect(
          () => client
              .queryBuilder()
              .from('users')
              .whereJsonSupersetOf('settings', {'a': 1})
              .toSQL(),
          throwsA(isA<StateError>()),
        );
      },
    );

    test('whereJsonSubsetOf reverses argument order in json_contains() for '
        'MySQL (asymmetric vs. supersetOf — matches knex.js)', () {
      final client = MockClient(driverName: 'mysql');
      final sql = client.queryBuilder().from('users').whereJsonSubsetOf(
        'settings',
        {'a': 1},
      ).toSQL();
      expect(sql.sql, 'select * from `users` where json_contains(\$1,`settings`)');
      expect(sql.bindings, ['{"a":1}']);
    });

    test('whereJsonObject uses json_contains() in MySQL (not plain `=`)', () {
      final client = MockClient(driverName: 'mysql');
      final sql = client.queryBuilder().from('users').whereJsonObject(
        'settings',
        {'a': 1},
      ).toSQL();
      expect(sql.sql, 'select * from `users` where json_contains(`settings`, \$1)');
    });
  });

  group('JSON operators use the ACTUAL driver-name strings this codebase '
      'produces (regression)', () {
    // The dialect-dispatch checks in query_compiler.dart previously compared
    // client.driverName against bare 'mysql'/'sqlite' — but
    // KnexQuery.forClient() (the real, documented entry point) always
    // produces 'mysql2'/'sqlite3' for those dialects (see
    // KnexQuery._driverStr()). The mysql/sqlite JSON branches were
    // therefore DEAD CODE for every query built the normal way; only
    // MockClient(driverName: 'mysql')-style tests with the "friendly" name
    // ever exercised them. Verified against real knex.js via
    // tool/parity/run_js.mjs's json/where-* cases.
    test('mysql2 gets json_extract() for whereJsonPath, not the '
        'whereBasic() fallback', () {
      final client = MockClient(driverName: 'mysql2');
      final sql = client
          .queryBuilder()
          .from('users')
          .whereJsonPath('settings', '\$.theme', '=', 'dark')
          .toSQL();
      expect(
        sql.sql,
        'select * from `users` where json_extract(`settings`, \$1) = \$2',
      );
    });

    test('sqlite3 gets json_extract() for whereJsonPath, not the '
        'whereBasic() fallback', () {
      final client = MockClient(driverName: 'sqlite3');
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

    test('turso (sqlite-family) also gets json_extract(), not just the '
        'bare "sqlite"/"sqlite3" strings', () {
      final client = MockClient(driverName: 'turso');
      final sql = client
          .queryBuilder()
          .from('users')
          .whereJsonPath('settings', '\$.theme', '=', 'dark')
          .toSQL();
      expect(sql.sql, contains('json_extract('));
    });

    test('a dialect with no whereJsonPath implementation throws instead of '
        'silently compiling a wrong plain-column comparison (previous '
        'behavior: unconditional whereBasic() fallback)', () {
      final client = MockClient(driverName: 'redshift');
      expect(
        () => client
            .queryBuilder()
            .from('users')
            .whereJsonPath('settings', '\$.theme', '=', 'dark')
            .toSQL(),
        throwsA(isA<StateError>()),
      );
    });
  });
}
