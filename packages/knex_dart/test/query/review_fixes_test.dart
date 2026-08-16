/// Regression tests for query-compiler correctness fixes surfaced by the
/// adversarial knex.js/knex-dart comparison review.
///
/// Each group documents the *correct* behaviour (and why the previous output
/// was wrong), not merely parity with knex.js. Ground truth was cross-checked
/// against knex.js where the semantics were non-obvious.
library;

import 'package:knex_dart/src/query/query_builder.dart';
import 'package:test/test.dart';

import '../mocks/mock_client.dart';
import '../mocks/mysql_mock_client.dart';
import '../mocks/sqlite_mock_client.dart';

void main() {
  final pg = MockClient(); // Postgres dialect: "double quotes", $N placeholders
  final my = MySQLMockClient(); // MySQL dialect: `backticks`

  group('onConflict().merge().where() — DO UPDATE predicate guard', () {
    // Previously the WHERE clause was silently dropped, so the upsert fired
    // unconditionally. In Postgres `... do update set ... where <cond>` only
    // applies the update when the predicate holds; dropping it changes results.
    test('Postgres appends the WHERE guard after the SET clause', () {
      final sql = QueryBuilder(pg)
          .table('users')
          .insert({'email': 'a@b.com', 'cnt': 1})
          .onConflict('email')
          .merge()
          .where('cnt', '<', 100)
          .toSQL();

      // Column order is alphabetically sorted ("cnt" before "email"),
      // matching knex.js's `_prepInsert`/implicit-merge column ordering —
      // verified against real knex.js output.
      expect(
        sql.sql,
        'insert into "users" ("cnt", "email") values (\$1, \$2) '
        'on conflict ("email") do update set '
        '"cnt" = excluded."cnt", "email" = excluded."email" '
        'where "cnt" < \$3',
      );
      // Binding order: insert values first (sorted-column order), then the
      // guard predicate.
      expect(sql.bindings, [1, 'a@b.com', 100]);
    });

    test('MySQL throws — ON DUPLICATE KEY UPDATE has no WHERE guard', () {
      // Silently dropping the guard would change write semantics (the upsert
      // would fire unconditionally), so this must fail loudly instead.
      expect(
        () => QueryBuilder(my)
            .table('users')
            .insert({'email': 'a@b.com', 'cnt': 1})
            .onConflict('email')
            .merge()
            .where('cnt', '<', 100)
            .toSQL(),
        throwsStateError,
      );
    });

    test('MySQL merge() without a where still compiles', () {
      final sql = QueryBuilder(my)
          .table('users')
          .insert({'email': 'a@b.com', 'cnt': 1})
          .onConflict('email')
          .merge()
          .toSQL();
      expect(sql.sql, contains('on duplicate key update'));
    });

    test('a plain INSERT with .where() is unaffected (no conflict clause)', () {
      final sql = QueryBuilder(pg)
          .table('users')
          .insert({'email': 'a@b.com'})
          .where('cnt', '<', 100) // no onConflict → guard must not leak
          .toSQL();

      expect(sql.sql, isNot(contains('where')));
    });
  });

  group('Multi-row INSERT with ragged columns', () {
    // Previously columns came from row[0] only, so keys unique to later rows
    // were silently dropped (and value/column counts could desync). The column
    // set is now the union of all rows; missing cells emit the DEFAULT keyword.
    test('union of keys; absent cells become `default`', () {
      final sql = QueryBuilder(pg)
          .table('t')
          .insert([
            {'a': 1, 'b': 2},
            {'a': 3, 'c': 4},
          ])
          .toSQL();

      expect(
        sql.sql,
        'insert into "t" ("a", "b", "c") values '
        '(\$1, \$2, DEFAULT), (\$3, DEFAULT, \$4)',
      );
      expect(sql.bindings, [1, 2, 3, 4]);
    });

    test('SQLite refuses a ragged insert (no DEFAULT in a VALUES list)', () {
      // knex.js refuses this too; emitting DEFAULT would be invalid SQLite.
      expect(
        () => QueryBuilder(SqliteMockClient())
            .table('t')
            .insert([
              {'a': 1, 'b': 2},
              {'a': 3},
            ])
            .toSQL(),
        throwsStateError,
      );
    });

    test('explicit null is a binding, not `default`', () {
      final sql = QueryBuilder(pg)
          .table('t')
          .insert([
            {'a': 1, 'b': null},
            {'a': 2},
          ])
          .toSQL();

      // Row 1 sets b explicitly to null (a bound value); row 2 omits b entirely.
      expect(sql.sql, 'insert into "t" ("a", "b") values (\$1, \$2), (\$3, DEFAULT)');
      expect(sql.bindings, [1, null, 2]);
    });
  });

  group('WITH (CTE) prefix on UPDATE and DELETE', () {
    // Previously _with() was only invoked for SELECT, so a CTE referenced by an
    // UPDATE/DELETE was never emitted → the query referenced an undefined name.
    test('UPDATE carries its WITH clause', () {
      final sub = QueryBuilder(pg).table('src').select(['id']);
      final sql = QueryBuilder(pg)
          .table('t')
          .withQuery('recent', sub)
          .where('flag', true)
          .update({'a': 1})
          .toSQL();

      expect(sql.sql, startsWith('with "recent" as (select "id" from "src")'));
      expect(sql.sql, contains('update "t" set "a" ='));
    });

    test('DELETE carries its WITH clause', () {
      final sub = QueryBuilder(pg).table('src').select(['id']);
      final sql = QueryBuilder(pg)
          .table('t')
          .withQuery('recent', sub)
          .whereIn('id', QueryBuilder(pg).table('recent').select(['id']))
          .delete()
          .toSQL();

      expect(sql.sql, startsWith('with "recent" as (select "id" from "src")'));
      expect(sql.sql, contains('delete from "t" where "id" in'));
    });
  });

  group('Aggregate over a schema/table-qualified column', () {
    // Previously the whole "table.column" string was wrapped as a single
    // identifier → count("orders.id") (a column literally named "orders.id").
    test('dotted column splits into qualified identifier', () {
      final sql = QueryBuilder(pg).table('orders').count('orders.id').toSQL();
      expect(sql.sql, 'select count("orders"."id") from "orders"');
    });

    test('plain column and wildcard are unchanged', () {
      expect(
        QueryBuilder(pg).table('orders').count('id').toSQL().sql,
        'select count("id") from "orders"',
      );
      expect(
        QueryBuilder(pg).table('orders').count('*').toSQL().sql,
        'select count(*) from "orders"',
      );
    });
  });

  group("where('col', null) → IS NULL", () {
    // "col" = null never matches (SQL three-valued logic); the 2-arg null form
    // is shorthand for IS NULL, matching user intent.
    test('2-arg null compiles to IS NULL', () {
      final sql =
          QueryBuilder(pg).table('users').where('deleted_at', null).toSQL();
      expect(sql.sql, 'select * from "users" where "deleted_at" is null');
      expect(sql.bindings, isEmpty);
    });

    test('orWhere null keeps the OR boolean', () {
      final sql = QueryBuilder(pg)
          .table('users')
          .where('active', true)
          .orWhere('deleted_at', null)
          .toSQL();
      expect(sql.sql, contains('or "deleted_at" is null'));
    });

    test('3-arg form is left untouched (explicit operator preserved)', () {
      // Not rewritten: this documents the deliberately-narrow 2-arg-only scope.
      final sql =
          QueryBuilder(pg).table('users').where('score', '>', 10).toSQL();
      expect(sql.sql, contains('"score" > \$1'));
    });
  });

  group('orWhereIn', () {
    test('joins with OR and renders IN list', () {
      final sql = QueryBuilder(pg)
          .table('users')
          .where('active', true)
          .orWhereIn('role', ['admin', 'owner'])
          .toSQL();

      expect(sql.sql, contains('or "role" in (\$2, \$3)'));
      expect(sql.bindings, [true, 'admin', 'owner']);
    });
  });

  group('Outer join aliases', () {
    test('leftOuterJoin', () {
      final sql = QueryBuilder(pg)
          .table('users')
          .leftOuterJoin('profiles', 'users.id', 'profiles.user_id')
          .select(['*'])
          .toSQL();
      expect(
        sql.sql,
        'select * from "users" left outer join "profiles" '
        'on "users"."id" = "profiles"."user_id"',
      );
    });

    test('rightOuterJoin', () {
      final sql = QueryBuilder(pg)
          .table('a')
          .rightOuterJoin('b', 'a.id', 'b.a_id')
          .select(['*'])
          .toSQL();
      expect(sql.sql, contains('right outer join "b" on "a"."id" = "b"."a_id"'));
    });

    test('outerJoin', () {
      final sql = QueryBuilder(pg)
          .table('a')
          .outerJoin('b', 'a.id', 'b.a_id')
          .select(['*'])
          .toSQL();
      expect(sql.sql, contains('outer join "b" on "a"."id" = "b"."a_id"'));
    });
  });

  group('Positional \$N placeholder renumbering (multi-digit safety)', () {
    // The old renumbering iterated replaceAll('\$1', …) high→low, which also
    // matched \$1 INSIDE \$10/\$11 — including tokens it had just produced.
    // With 9 parent bindings a 2-binding subquery yielded \$101 instead of \$11,
    // referencing a parameter that does not exist. Now a single regex pass.
    test('subquery placeholders continue correctly past \$9', () {
      final sub = QueryBuilder(pg)
          .table('sub')
          .select(['id'])
          .where('x', 'a')
          .where('y', 'b');
      final sql = QueryBuilder(pg)
          .table('t')
          .where('c1', 1)
          .where('c2', 2)
          .where('c3', 3)
          .where('c4', 4)
          .where('c5', 5)
          .where('c6', 6)
          .where('c7', 7)
          .where('c8', 8)
          .where('c9', 9)
          .whereIn('id', sub)
          .toSQL();

      expect(sql.sql, contains('"x" = \$10 and "y" = \$11'));
      expect(sql.sql, isNot(contains('\$101')));
      expect(sql.bindings.length, 11);
      // Every referenced placeholder must exist in the bindings list.
      for (final m in RegExp(r'\$(\d+)').allMatches(sql.sql)) {
        expect(int.parse(m[1]!), lessThanOrEqualTo(sql.bindings.length));
      }
    });

    test('UNION arm placeholders continue correctly past \$9', () {
      final other = QueryBuilder(pg).table('b').select(['id']).where('z', 'q');
      final sql = QueryBuilder(pg)
          .table('a')
          .select(['id'])
          .where('c1', 1)
          .where('c2', 2)
          .where('c3', 3)
          .where('c4', 4)
          .where('c5', 5)
          .where('c6', 6)
          .where('c7', 7)
          .where('c8', 8)
          .where('c9', 9)
          .where('c10', 10)
          .union([other])
          .toSQL();

      expect(sql.sql, contains('"z" = \$11'));
      for (final m in RegExp(r'\$(\d+)').allMatches(sql.sql)) {
        expect(int.parse(m[1]!), lessThanOrEqualTo(sql.bindings.length));
      }
    });

    test('multiple bound CTEs get distinct placeholders', () {
      final a = QueryBuilder(pg).table('s1').select(['id']).where('x', 10);
      final b = QueryBuilder(pg).table('s2').select(['id']).where('y', 20);
      final sql = QueryBuilder(pg)
          .table('t')
          .withQuery('a', a)
          .withQuery('b', b)
          .where('id', 30)
          .update({'z': 40})
          .toSQL();

      // Each CTE must own a distinct placeholder, not both restart at $1.
      expect(sql.sql, contains('"x" = \$1'));
      expect(sql.sql, contains('"y" = \$2'));
      expect(sql.bindings, [10, 20, 40, 30]);
      for (final m in RegExp(r'\$(\d+)').allMatches(sql.sql)) {
        expect(int.parse(m[1]!), lessThanOrEqualTo(sql.bindings.length));
      }
    });
  });

  group('jsonb key-existence operator', () {
    test('Postgres emits a bare `?` (no leaked backslash)', () {
      final sql = QueryBuilder(pg).table('t').where('tags', '?', 'urgent').toSQL();
      expect(sql.sql, 'select * from "t" where "tags" ? \$1');
      expect(sql.sql, isNot(contains(r'\?')));
    });
  });

  group('onConflict().ignore() capability guard', () {
    test('Postgres emits ON CONFLICT DO NOTHING', () {
      final sql = QueryBuilder(pg)
          .table('users')
          .insert({'email': 'a@b.com'})
          .onConflict('email')
          .ignore()
          .toSQL();
      expect(sql.sql, contains('on conflict ("email") do nothing'));
    });
  });

  group('groupBy(List)', () {
    test('a list produces a comma-separated GROUP BY', () {
      final sql = QueryBuilder(pg)
          .table('sales')
          .select(['region'])
          .groupBy(['region', 'product'])
          .toSQL();
      expect(sql.sql, endsWith('group by "region", "product"'));
    });

    test('single-column form still works', () {
      final sql =
          QueryBuilder(pg).table('sales').groupBy('region').toSQL();
      expect(sql.sql, endsWith('group by "region"'));
    });
  });

  group('where(Raw) — bool/not flags', () {
    // Previously `where()`'s Raw branch hardcoded `'bool': 'and'` and never
    // stored a `'not'` key at all, so `.orWhere(raw(...))` silently compiled
    // as AND (dropping the OR), and `.whereNot(raw(...))`/
    // `.orWhereNot(raw(...))` silently dropped the NOT — both change query
    // semantics, not just formatting. Verified against real knex.js.
    test('.whereNot(raw(...)) prefixes with "not "', () {
      final sql = QueryBuilder(pg)
          .table('testtable')
          .whereNot(pg.raw('is_active'))
          .toSQL();
      expect(sql.sql, 'select * from "testtable" where not is_active');
      expect(sql.bindings, isEmpty);
    });

    test('.orWhereNot(raw(...)) prefixes with "not " and joins with OR', () {
      final sql = QueryBuilder(pg)
          .table('t')
          .where('a', 1)
          .orWhereNot(pg.raw('is_active'))
          .toSQL();
      expect(sql.sql, 'select * from "t" where "a" = \$1 or not is_active');
      expect(sql.bindings, [1]);
    });

    test('.orWhere(raw(...)) joins with OR, not AND', () {
      final sql = QueryBuilder(pg)
          .table('users')
          .where('a', 1)
          .orWhere(pg.raw('b = 2'))
          .toSQL();
      expect(sql.sql, 'select * from "users" where "a" = \$1 or b = 2');
      expect(sql.bindings, [1]);
    });

    test('plain .where(raw(...)) is unaffected (still AND, no NOT)', () {
      final sql = QueryBuilder(pg)
          .table('users')
          .where('a', 1)
          .where(pg.raw('b = 2'))
          .toSQL();
      expect(sql.sql, 'select * from "users" where "a" = \$1 and b = 2');
      expect(sql.bindings, [1]);
    });
  });

  group('select() numeric literal', () {
    // `_columns()` called `.toString()` on every select() column before
    // handing it to `formatter.wrap()`, which loses the `num` type that
    // `wrap()` special-cases (numbers pass through bare) — so `select(0)`
    // compiled to the quoted identifier `"0"` instead of the bare literal
    // `0`. Verified against real knex.js (`select 0`).
    test('select(0) compiles to a bare numeric literal, not a quoted '
        'identifier', () {
      final sql = QueryBuilder(pg).select([0]).toSQL();
      expect(sql.sql, 'select 0');
    });

    test('select(0) with a table still compiles the literal bare', () {
      final sql = QueryBuilder(pg).table('t').select([0]).toSQL();
      expect(sql.sql, 'select 0 from "t"');
    });

    test('string columns are unaffected (still wrapped as identifiers)', () {
      final sql = QueryBuilder(pg).table('t').select(['id']).toSQL();
      expect(sql.sql, 'select "id" from "t"');
    });
  });

  group('whereIn/whereNotIn with a Raw value', () {
    // Previously `whereIn()`'s compiler only handled QueryBuilder/Function
    // values before falling through to an unconditional `values as List`
    // cast — a Raw value (e.g. a raw subquery with named bindings) threw a
    // TypeError instead of compiling. knex.js supports this directly.
    test('whereIn(col, raw(...)) compiles the raw fragment inside IN (...)', () {
      final sql = QueryBuilder(pg)
          .table('users')
          .select(['*'])
          .whereIn(
            'id',
            pg.raw('select (:test)', {
              'test': [1, 2, 3],
            }),
          )
          .toSQL();

      expect(sql.sql, 'select * from "users" where "id" in (select (\$1))');
      expect(sql.bindings, [
        [1, 2, 3],
      ]);
    });

    test('whereNotIn(col, raw(...)) also compiles (shares the same '
        'compiler path)', () {
      final sql = QueryBuilder(pg)
          .table('users')
          .whereNotIn('id', pg.raw('select id from banned'))
          .toSQL();

      expect(sql.sql, 'select * from "users" where "id" not in (select id from banned)');
      expect(sql.bindings, isEmpty);
    });
  });

  group('DELETE ... LIMIT — MySQL-only extension (knex.js 3.2.9+)', () {
    test('MySQL: .delete().limit(n) compiles a trailing LIMIT clause', () {
      final sql = QueryBuilder(
        my,
      ).table('users').where('id', '>', 1).delete().limit(1).toSQL();

      expect(sql.sql, 'delete from `users` where `id` > ? limit ?');
      expect(sql.bindings, [1, 1]);
    });

    test('Postgres: .delete().limit(n) silently ignores the no-op LIMIT '
        '(standard SQL has no DELETE...LIMIT)', () {
      final sql = QueryBuilder(
        pg,
      ).table('users').where('id', '>', 1).delete().limit(1).toSQL();

      expect(sql.sql, 'delete from "users" where "id" > \$1');
      expect(sql.bindings, [1]);
    });

    test('SQLite: .delete().limit(n) silently ignores the no-op LIMIT', () {
      final sql = QueryBuilder(
        SqliteMockClient(),
      ).table('users').where('id', '>', 1).delete().limit(1).toSQL();

      expect(sql.sql, 'delete from "users" where "id" > ?');
      expect(sql.bindings, [1]);
    });
  });

  group(
    'Analytic/window function alias — identifier-wrapped (knex.js 3.2.10+)',
    () {
      test('rank() alias is wrapped like any other identifier', () {
        final sql = QueryBuilder(
          pg,
        ).table('accounts').select(['*']).rank('test_alias', 'email', 'address').toSQL();

        expect(
          sql.sql,
          'select *, rank() over (partition by "address" order by "email") as "test_alias" from "accounts"',
        );
      });
    },
  );

  group('SQLite RETURNING — supported on INSERT/UPDATE, not DELETE '
      '(knex.js 3.2.9+ for the empty-insert shape specifically)', () {
    test('SQLite: insert().returning() emits RETURNING', () {
      final sql = QueryBuilder(
        SqliteMockClient(),
      ).table('users').insert({'email': 'a'}).returning(['id']).toSQL();

      expect(sql.sql, 'insert into "users" ("email") values (?) returning "id"');
    });

    test('SQLite: insert([{}]).returning() emits DEFAULT VALUES + RETURNING', () {
      final sql = QueryBuilder(
        SqliteMockClient(),
      ).table('users').insert([{}]).returning(['id']).toSQL();

      expect(sql.sql, 'insert into "users" default values returning "id"');
    });

    test('SQLite: update().returning() emits RETURNING', () {
      final sql = QueryBuilder(SqliteMockClient())
          .table('users')
          .where('id', 1)
          .update({'email': 'a'})
          .returning(['id'])
          .toSQL();

      expect(
        sql.sql,
        'update "users" set "email" = ? where "id" = ? returning "id"',
      );
    });

    test(
      'SQLite: delete().returning() silently drops RETURNING (matches '
      'knex.js — sqlite3 never supports RETURNING on DELETE)',
      () {
        final sql = QueryBuilder(SqliteMockClient())
            .table('users')
            .where('id', 1)
            .delete()
            .returning(['id'])
            .toSQL();

        expect(sql.sql, 'delete from "users" where "id" = ?');
      },
    );
  });

  // ── CodeRabbit-flagged fixes (PR #17 review) ─────────────────────────────

  group('.pluck() subquery in a parameter position is parenthesized', () {
    test('matches .select()/.first() subquery wrapping', () {
      final sub = pg.queryBuilder().table('t2').pluck('id');
      final sql =
          pg.queryBuilder().table('t1').where('t1_id', '=', sub).toSQL();
      expect(sql.sql, 'select * from "t1" where "t1_id" = (select "id" from "t2")');
    });
  });

  group('whereNot()/orWhereNot() with a "between" operator', () {
    test('whereNot(col, "between", [a, b]) compiles to NOT BETWEEN', () {
      final sql = pg
          .queryBuilder()
          .table('t')
          .whereNot('id', 'between', [1, 2])
          .toSQL();
      expect(sql.sql, 'select * from "t" where "id" not between \$1 and \$2');
    });

    test('orWhereNot(col, "between", [a, b]) compiles to NOT BETWEEN', () {
      final sql = pg
          .queryBuilder()
          .table('t')
          .orWhereNot('id', 'between', [1, 2])
          .toSQL();
      expect(sql.sql, 'select * from "t" where "id" not between \$1 and \$2');
    });

    test('where(col, "between", [a, b]) (no whereNot) still compiles to BETWEEN', () {
      final sql =
          pg.queryBuilder().table('t').where('id', 'between', [1, 2]).toSQL();
      expect(sql.sql, 'select * from "t" where "id" between \$1 and \$2');
    });

    test('where(col, "not between", [a, b]) (operator spelled out directly) still NOT BETWEEN', () {
      final sql = pg
          .queryBuilder()
          .table('t')
          .where('id', 'not between', [1, 2])
          .toSQL();
      expect(sql.sql, 'select * from "t" where "id" not between \$1 and \$2');
    });
  });

  group('lock modes — dialects with no row-locking support', () {
    test('Redshift: forUpdate()/forShare() are silent no-ops (no lock clause)', () {
      final redshift = MockClient(driverName: 'redshift');
      expect(
        redshift.queryBuilder().table('t').forUpdate().toSQL().sql,
        'select * from "t"',
      );
      expect(
        redshift.queryBuilder().table('t').forShare().toSQL().sql,
        'select * from "t"',
      );
    });

    test('SQLite: forUpdate()/forShare() are silent no-ops (no lock clause)', () {
      final sql = SqliteMockClient()
          .queryBuilder()
          .table('t')
          .forUpdate()
          .toSQL();
      expect(sql.sql, 'select * from "t"');
    });

    test('MSSQL: forUpdate()/forShare() throw rather than emit wrong SQL', () {
      final mssql = MockClient(driverName: 'mssql');
      expect(
        () => mssql.queryBuilder().table('t').forUpdate().toSQL(),
        throwsStateError,
      );
    });
  });

  group('MySQL UPDATE ... JOIN ... SET — binding order', () {
    test('join ON-clause bindings precede SET bindings, matching SQL text order', () {
      final sql = my.queryBuilder().table('users').join(
        'accounts',
        (j) => j
            .on('users.id', '=', 'accounts.user_id')
            .onVal('accounts.status', '=', 'active'),
      ).update({'users.name': 'Bob'}).toSQL();

      expect(
        sql.sql,
        'update `users` inner join `accounts` on `users`.`id` = '
        '`accounts`.`user_id` and `accounts`.`status` = ? set `users`.`name` = ?',
      );
      // Previously ['Bob', 'active'] — wrong slot for both placeholders.
      expect(sql.bindings, ['active', 'Bob']);
    });
  });
}
