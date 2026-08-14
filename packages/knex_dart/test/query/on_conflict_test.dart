import 'package:knex_dart/src/query/query_builder.dart';
import 'package:test/test.dart';

import '../mocks/mock_client.dart';
import '../mocks/mysql_mock_client.dart';

void main() {
  final pg = MockClient(); // Postgres/SQLite dialect (double-quote identifiers)
  final my = MySQLMockClient(); // MySQL dialect (backtick identifiers)

  group('onConflict().ignore() — Postgres/SQLite', () {
    test('INSERT IGNORE on single column conflict target', () {
      final sql = QueryBuilder(pg)
          .table('users')
          .insert({'email': 'a@b.com', 'name': 'Alice'})
          .onConflict('email')
          .ignore()
          .toSQL();

      expect(
        sql.sql,
        r'insert into "users" ("email", "name") values ($1, $2) '
        r'on conflict ("email") do nothing',
      );
      expect(sql.bindings, ['a@b.com', 'Alice']);
    });

    test('INSERT IGNORE with multi-column conflict target', () {
      final sql = QueryBuilder(pg)
          .table('items')
          .insert({'sku': 'X1', 'warehouse': 'A', 'qty': 10})
          .onConflict(['sku', 'warehouse'])
          .ignore()
          .toSQL();

      expect(sql.sql, contains('on conflict ("sku", "warehouse") do nothing'));
    });

    test('INSERT IGNORE with no conflict target (global unique)', () {
      final sql = QueryBuilder(pg)
          .table('users')
          .insert({'email': 'a@b.com'})
          .onConflict()
          .ignore()
          .toSQL();

      expect(sql.sql, contains('on conflict do nothing'));
    });
  });

  group('onConflict().merge() — Postgres/SQLite', () {
    test('merge() with no arg updates all inserted columns', () {
      final sql = QueryBuilder(pg)
          .table('users')
          .insert({'email': 'a@b.com', 'name': 'Alice'})
          .onConflict('email')
          .merge()
          .toSQL();

      expect(
        sql.sql,
        r'insert into "users" ("email", "name") values ($1, $2) '
        r'on conflict ("email") do update set "email" = excluded."email", '
        r'"name" = excluded."name"',
      );
    });

    test(
      'merge() with no arg on a ragged multi-row insert updates the union '
      "of all rows' keys, not just row[0]'s (verified against real "
      'knex.js)',
      () {
        final sql = QueryBuilder(pg)
            .table('t')
            .insert([
              {'Zebra': 1, 'apple': 2},
              {'apple': 3, 'Zoo': 4},
            ])
            .onConflict('apple')
            .merge()
            .toSQL();

        expect(
          sql.sql,
          'insert into "t" ("Zebra", "Zoo", "apple") values '
          r'($1, DEFAULT, $2), (DEFAULT, $3, $4) on conflict ("apple") do '
          'update set "Zebra" = excluded."Zebra", "Zoo" = excluded."Zoo", '
          '"apple" = excluded."apple"',
        );
        expect(sql.bindings, [1, 2, 4, 3]);
      },
    );

    test('merge(List) updates only specified columns', () {
      final sql = QueryBuilder(pg)
          .table('users')
          .insert({'email': 'a@b.com', 'name': 'Alice', 'role': 'admin'})
          .onConflict('email')
          .merge(['name'])
          .toSQL();

      expect(sql.sql, contains('do update set "name" = excluded."name"'));
      // should NOT update email or role
      expect(sql.sql, isNot(contains('excluded."email"')));
      expect(sql.sql, isNot(contains('excluded."role"')));
    });

    test('merge(Map) updates with explicit values', () {
      final sql = QueryBuilder(pg)
          .table('users')
          .insert({'email': 'a@b.com', 'name': 'Alice'})
          .onConflict('email')
          .merge({'name': 'Updated Alice'})
          .toSQL();

      expect(sql.sql, contains('do update set "name" ='));
      expect(sql.bindings, contains('Updated Alice'));
    });

    test('merge(Map) inlines a Raw value instead of binding it', () {
      final sql = QueryBuilder(pg)
          .table('leases')
          .insert({'group_key': 'g1', 'fence': 1})
          .onConflict('group_key')
          .merge({
            'fence': pg.raw('DEFAULT'),
            'lease_until': pg.raw('clock_timestamp()'),
          })
          .toSQL();

      expect(
        sql.sql,
        contains(
          'do update set "fence" = DEFAULT, "lease_until" = clock_timestamp()',
        ),
      );
      // Raw fragments must not appear as bound parameters. Binding order
      // follows the sorted INSERT column order ("fence" before "group_key"),
      // matching knex.js's `_prepInsert` — verified against real knex.js.
      expect(sql.bindings, [1, 'g1']);
    });

    test('merge() chained with returning()', () {
      final sql = QueryBuilder(pg)
          .table('users')
          .insert({'email': 'a@b.com', 'name': 'Alice'})
          .onConflict('email')
          .merge()
          .returning(['id', 'name'])
          .toSQL();

      expect(sql.sql, contains('returning "id", "name"'));
    });
  });

  group('onConflict().ignore() — MySQL', () {
    test('produces INSERT IGNORE prefix', () {
      final sql = QueryBuilder(my)
          .table('users')
          .insert({'email': 'a@b.com', 'name': 'Alice'})
          .onConflict('email')
          .ignore()
          .toSQL();

      expect(sql.sql, startsWith('insert ignore into'));
      // MySQL: no ON CONFLICT clause appended
      expect(sql.sql, isNot(contains('on conflict')));
    });
  });

  group('onConflict().merge() — MySQL', () {
    test('merge() produces ON DUPLICATE KEY UPDATE with values()', () {
      final sql = QueryBuilder(my)
          .table('users')
          .insert({'email': 'a@b.com', 'name': 'Alice'})
          .onConflict('email')
          .merge()
          .toSQL();

      expect(sql.sql, startsWith('insert into'));
      expect(
        sql.sql,
        contains(
          'on duplicate key update `email` = values(`email`), '
          '`name` = values(`name`)',
        ),
      );
    });

    test('merge(List) updates only specified columns', () {
      final sql = QueryBuilder(my)
          .table('users')
          .insert({'email': 'a@b.com', 'name': 'Alice', 'role': 'admin'})
          .onConflict('email')
          .merge(['name'])
          .toSQL();

      expect(
        sql.sql,
        contains('on duplicate key update `name` = values(`name`)'),
      );
      expect(sql.sql, isNot(contains('values(`email`)')));
    });

    test('merge(Map) uses explicit values', () {
      final sql = QueryBuilder(my)
          .table('users')
          .insert({'email': 'a@b.com', 'name': 'Alice'})
          .onConflict('email')
          .merge({'name': 'Updated'})
          .toSQL();

      expect(sql.sql, contains('on duplicate key update `name` ='));
      expect(sql.bindings, contains('Updated'));
    });
  });
}
