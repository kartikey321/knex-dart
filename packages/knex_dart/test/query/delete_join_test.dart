/// Regression tests for `.del()` combined with `.join(...)`.
///
/// Previously `_deleteQuery()` never consulted the compiled JOIN clause at
/// all, so any join attached to a DELETE was silently dropped — a query with
/// a join meant to scope which rows get deleted would instead delete every
/// row in the table. Fixed to mirror knex.js's per-dialect handling:
///   - Postgres/CockroachDB: `DELETE FROM t USING j WHERE ... AND <join on>`
///     (join ON conditions fold into WHERE, after the original predicate).
///   - MySQL/SQLite/Redshift (and default): `DELETE t FROM t <join> WHERE
///     ...` (join stays a real JOIN clause).
/// Expected SQL cross-checked against real knex.js (`node -e "require(...)"`)
/// for every dialect below.
library;

import 'package:knex_dart/knex_dart.dart';
import 'package:test/test.dart';

QueryBuilder _qb(String dialect) =>
    KnexQuery.forClient(dialect).queryBuilder();

void main() {
  group('DELETE + JOIN — Postgres/CockroachDB (USING transform)', () {
    for (final dialect in ['postgres', 'cockroachdb']) {
      test('$dialect: single join + where folds ON into WHERE after the '
          'original predicate', () {
        final sql = _qb(dialect)
            .table('users')
            .delete()
            .join('photos', 'photos.id', 'users.id')
            .where('user.email', 'mock@example.com')
            .toSQL();

        expect(
          sql.sql,
          'delete from "users" using "photos" '
          'where "user"."email" = \$1 and "photos"."id" = "users"."id"',
        );
        expect(sql.bindings, ['mock@example.com']);
      });

      test('$dialect: no WHERE — join ON becomes the sole predicate', () {
        final sql = _qb(dialect)
            .table('users')
            .delete()
            .join('photos', 'photos.id', 'users.id')
            .toSQL();

        expect(
          sql.sql,
          'delete from "users" using "photos" where "photos"."id" = "users"."id"',
        );
        expect(sql.bindings, isEmpty);
      });
    }

    test('multiple joins become a comma-separated USING list', () {
      final sql = _qb('postgres')
          .table('users')
          .delete()
          .join('photos', 'photos.id', 'users.id')
          .join('docs', 'docs.id', 'users.id')
          .where('user.email', 'mock@example.com')
          .toSQL();

      expect(
        sql.sql,
        'delete from "users" using "photos","docs" '
        'where "user"."email" = \$1 and "photos"."id" = "users"."id" '
        'and "docs"."id" = "users"."id"',
      );
      expect(sql.bindings, ['mock@example.com']);
    });

    test('bound values inside a join ON condition accumulate AFTER the '
        'WHERE bindings, with no duplication', () {
      // Regression for a binding-order bug introduced while writing the
      // USING-transform fix: an earlier draft called `_join()` up front just
      // to check for emptiness (a side-effecting compile that appends
      // bindings), then compiled the same join conditions again inside the
      // USING branch — doubling any bound join values and placing them
      // before the WHERE bindings instead of after.
      final sql = _qb('postgres')
          .table('users')
          .delete()
          .join(
            'photos',
            (j) => j
                .on('photos.id', 'users.id')
                .onIn('photos.kind', ['primary', 'secondary']),
          )
          .where('user.email', 'mock@example.com')
          .toSQL();

      expect(
        sql.sql,
        'delete from "users" using "photos" '
        'where "user"."email" = \$1 and "photos"."id" = "users"."id" '
        'and "photos"."kind" in (\$2, \$3)',
      );
      // WHERE's binding first, then the join condition's bindings — each
      // value appears exactly once.
      expect(sql.bindings, ['mock@example.com', 'primary', 'secondary']);
    });
  });

  group('DELETE + JOIN — MySQL/SQLite/Redshift (JOIN clause retained)', () {
    test('MySQL: DELETE t FROM t JOIN ... WHERE ...', () {
      final sql = _qb('mysql')
          .table('users')
          .delete()
          .join('photos', 'photos.id', 'users.id')
          .where('user.email', 'mock@example.com')
          .toSQL();

      expect(
        sql.sql,
        'delete `users` from `users` inner join `photos` '
        'on `photos`.`id` = `users`.`id` where `user`.`email` = ?',
      );
      expect(sql.bindings, ['mock@example.com']);
    });

    test('MySQL: no WHERE — join clause still present, no trailing WHERE', () {
      final sql = _qb('mysql')
          .table('users')
          .delete()
          .join('photos', 'photos.id', 'users.id')
          .toSQL();

      expect(
        sql.sql,
        'delete `users` from `users` inner join `photos` '
        'on `photos`.`id` = `users`.`id`',
      );
      expect(sql.bindings, isEmpty);
    });

    test('SQLite: DELETE t FROM t JOIN ... WHERE ... (double-quote '
        'identifiers, not the USING transform)', () {
      final sql = _qb('sqlite')
          .table('users')
          .delete()
          .join('photos', 'photos.id', 'users.id')
          .where('user.email', 'mock@example.com')
          .toSQL();

      expect(
        sql.sql,
        'delete "users" from "users" inner join "photos" '
        'on "photos"."id" = "users"."id" where "user"."email" = ?',
      );
      expect(sql.bindings, ['mock@example.com']);
    });

    test('Redshift: keeps the JOIN-clause shape, NOT the Postgres USING '
        'transform — verifies the postgres-like dialect split excludes '
        'redshift (knex.js\'s redshift-querycompiler does not inherit '
        'pg-querycompiler\'s del() override)', () {
      final sql = _qb('redshift')
          .table('users')
          .delete()
          .join('photos', 'photos.id', 'users.id')
          .where('user.email', 'mock@example.com')
          .toSQL();

      expect(
        sql.sql,
        'delete "users" from "users" inner join "photos" '
        'on "photos"."id" = "users"."id" where "user"."email" = \$1',
      );
      expect(sql.bindings, ['mock@example.com']);
    });
  });

  test('DELETE with no join is unaffected (plain delete from)', () {
    final sql = _qb('postgres')
        .table('users')
        .delete()
        .where('id', 2)
        .toSQL();

    expect(sql.sql, 'delete from "users" where "id" = \$1');
    expect(sql.bindings, [2]);
  });
}
