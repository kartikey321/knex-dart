#!/usr/bin/env node
// Differential parity fixture generator (knex.js reference side).
//
// DESIGN: cases are DIALECT-AGNOSTIC. Each case is a single builder function
// that works against any client (the query-building API is the same across
// dialects — only the compiled SQL differs). The harness multiplies each case
// across a DIALECT MATRIX, so adding one case adds coverage for every dialect
// at once, and adding one dialect re-tests every existing case.
//
// Dialects fall into three tiers (see DIALECTS below):
//   1. DIRECT   — knex.js has the same client → true differential parity.
//   2. FAMILY   — no dedicated knex.js client, but wire-compatible with one
//                 (turso/d1 ≈ sqlite3) → compared to the family baseline, with
//                 quoting normalized and intentional differences allowlisted.
//   3. GOLDEN   — knex.js has no counterpart (duckdb/bigquery/snowflake) → not
//                 emitted here; the Dart side pins a reviewed golden snapshot.
//
// This writes a COMMITTED fixture so the Dart test never shells out to the
// external knex.js checkout. Regenerate on knex.js bumps / new cases:
//   node tool/parity/run_js.mjs

import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const KNEX_PATH = process.env.KNEX_JS_PATH
  || '/Users/kartik/StudioProjects/knex/knex-js/knex.js';
const KNEX_PKG = process.env.KNEX_JS_PKG
  || '/Users/kartik/StudioProjects/knex/knex-js/package.json';

const { default: knex } = await import(KNEX_PATH);
const { version: knexVersion } = (await import(KNEX_PKG, { with: { type: 'json' } })).default;

// dartDialect → knex.js client name. `family` marks wire-compatible baselines.
// Tier-3 (golden) dialects are intentionally absent — the Dart side owns them.
const DIALECTS = {
  postgres: { knex: 'pg' },
  cockroachdb: { knex: 'cockroachdb' },
  redshift: { knex: 'redshift' },
  mysql: { knex: 'mysql2' },
  mariadb: { knex: 'mysql2', family: 'mysql' },
  sqlite: { knex: 'sqlite3' },
  turso: { knex: 'sqlite3', family: 'sqlite' },
  d1: { knex: 'sqlite3', family: 'sqlite' },
  mssql: { knex: 'mssql' },
};

const clientCache = {};
function clientFor(knexName) {
  return (clientCache[knexName] ??= knex({ client: knexName }));
}

// ── Corpus (dialect-agnostic) ────────────────────────────────────────────────
// [id, build]. `build(k)` returns a knex query builder. IDs are the contract
// with the Dart side — keep them stable.
const cases = [
  ['where/eq-string', (k) => k('users').where('status', 'active')],
  ['where/eq-number', (k) => k('users').where('age', 25)],
  ['where/op-gt', (k) => k('users').where('age', '>', 18)],
  ['where/op-lte', (k) => k('users').where('age', '<=', 65)],
  ['where/and-chain', (k) => k('users').where('a', 1).where('b', 2)],
  ['where/or', (k) => k('users').where('a', 1).orWhere('b', 2)],
  ['where/null', (k) => k('users').where('deleted_at', null)],
  ['where/not-null', (k) => k('users').whereNotNull('email')],
  ['where/in', (k) => k('users').whereIn('id', [1, 2, 3])],
  ['where/not-in', (k) => k('users').whereNotIn('id', [1, 2])],
  ['where/or-in', (k) => k('users').where('a', 1).orWhereIn('role', ['x', 'y'])],
  ['where/between', (k) => k('users').whereBetween('age', [18, 65])],
  ['where/grouped', (k) => k('users').where('a', 1).where((q) => q.where('b', 2).orWhere('c', 3))],
  ['where/subquery-in', (k) => k('users').whereIn('id', k('orders').select('user_id').where('total', '>', 100))],

  ['select/columns', (k) => k('users').select('id', 'name')],
  ['select/orderby-multi', (k) => k('users').orderBy('a').orderBy('b', 'desc')],
  ['select/limit-offset', (k) => k('users').limit(10).offset(5)],

  ['join/inner', (k) => k('a').join('b', 'a.id', 'b.a_id').select('*')],
  ['join/left', (k) => k('a').leftJoin('b', 'a.id', 'b.a_id').select('*')],

  ['insert/single', (k) => k('users').insert({ email: 'a@b.com', name: 'Alice' })],
  ['insert/multi-ragged', (k) => k('t').insert([{ a: 1, b: 2 }, { a: 3, c: 4 }])],
  ['update/set', (k) => k('users').where('id', 2).update({ name: 'Bob' })],
  ['delete/where', (k) => k('users').where('id', 2).del()],

  ['union/two', (k) => k('a').select('id').where('x', 1).union([k('b').select('id').where('y', 2)])],
  ['cte/select', (k) => k('t').with('recent', k('src').select('id').where('flag', true)).select('*')],

  // Capability-varying (expected to be supported on some dialects, refused on
  // others — the harness records both-refuse as parity, one-refuse as a finding).
  ['upsert/merge', (k) => k('users').insert({ email: 'a@b.com', name: 'Alice' }).onConflict('email').merge()],
  ['returning/insert', (k) => k('users').insert({ email: 'a@b.com' }).returning(['id'])],

  // Batch 2 — aggregates, grouping, distinct, counters, set-ops
  ['where/not', (k) => k('users').whereNot('status', 'banned')],
  ['select/distinct', (k) => k('users').distinct('name')],
  ['select/desc', (k) => k('users').orderBy('created_at', 'desc')],
  ['agg/count-col', (k) => k('t').count('id')],
  ['agg/sum', (k) => k('t').sum('amount')],
  ['agg/min-max', (k) => k('t').min('lo').max('hi')],
  ['having/basic', (k) => k('t').groupBy('cat').having('cnt', '>', 1)],
  ['update/increment', (k) => k('t').where('id', 1).increment('views', 5)],
  ['delete/all', (k) => k('users').del()],
  ['delete/limit-mysql', (k) => k('users').where('id', '>', 1).del().limit(1)],
  ['union/all', (k) => k('a').select('id').unionAll([k('b').select('id')])],

  // Known-divergence probe (jsonb key-existence operator).
  ['jsonb/qmark-op', (k) => k('t').where('tags', '?', 'urgent')],

  // Batch 3 — nested subqueries, EXISTS, UNION/INTERSECT, CTEs, window
  // functions, DML with RETURNING/onConflict. Mined from knex.js's own
  // test/unit/query/builder.js so every shape here is a real, already-CI
  // verified call pattern.

  // ── Subqueries (select / where / from, incl. 2+ level nesting) ──────────
  ['subquery/from-aliased', (k) =>
    k(k('foo').select('*').as('bar')).join('baz', 'foo.id', 'bar.foo_id')],
  ['subquery/where-scalar', (k) =>
    k('users').where('id', '=', k('users').select('id').where('email', 'bar'))],
  ['subquery/where-scalar-callback', (k) =>
    k('users').where('id', '=', function () {
      this.select(k.raw('max(id)')).from('users').where('email', '=', 'bar');
    })],
  ['subquery/select-scalar', (k) =>
    k('employee as e')
      .select('e.lastname', 'e.salary')
      .select(
        k('employee').select('avg(salary)').whereRaw('dept_no = e.dept_no').as('avg_sal_dept'),
      )
      .where('dept_no', '=', 'e.dept_no')],
  ['subquery/select-first-as', (k) =>
    k('employee as e')
      .select(
        'e.lastname',
        'e.salary',
        k.queryBuilder().first('salary').from('employee').whereRaw('dept_no = e.dept_no').orderBy('salary', 'desc').as('top_dept_salary'),
      )
      .from('employee as e')
      .where('dept_no', '=', 'e.dept_no')],
  ['subquery/from-basic-alias', (k) =>
    k(k('orders').select(k.raw('? as f', ['inner raw select'])).as('g'))
      .select(k.raw('?', ['outer raw select']), 'g.f')
      .where('g.secret', 123)],
  ['subquery/from-nested-2level', (k) =>
    k(k(k('inner_t').select('*').where('x', 1).as('mid')).select('*').as('outer_alias'))
      .select('*')],
  ['subquery/where-in-2level', (k) =>
    k('users').whereIn(
      'id',
      k('orders').select('user_id').whereIn('product_id', k('products').select('id').where('active', true)),
    )],

  // ── CTEs ──────────────────────────────────────────────────────────────
  ['cte/nested', (k) =>
    k.queryBuilder()
      .with('withClause', function () {
        this.with('withSubClause', function () {
          this.select('foo').as('baz').from('users');
        }).select('*').from('withSubClause');
      })
      .select('*')
      .from('withClause')],
  ['cte/chained-siblings', (k) =>
    k.queryBuilder()
      .with('firstWithClause', function () { this.select('foo').from('users'); })
      .with('secondWithClause', function () { this.select('bar').from('users'); })
      .select('*')
      .from('secondWithClause')],
  ['cte/raw', (k) =>
    k.queryBuilder()
      .with('withRawClause', k.raw('select "foo" as "baz" from "users"'))
      .select('*')
      .from('withRawClause')],
  ['cte/recursive-nested-chained', (k) =>
    k.queryBuilder()
      .withRecursive('firstWithClause', function () {
        this.withRecursive('firstWithSubClause', function () {
          this.select('foo').as('foz').from('users');
        }).select('*').from('firstWithSubClause');
      })
      .withRecursive('secondWithClause', function () {
        this.withRecursive('secondWithSubClause', function () {
          this.select('bar').as('baz').from('users');
        }).select('*').from('secondWithSubClause');
      })
      .select('*')
      .from('secondWithClause')],
  ['cte/insert-multi-source', (k) =>
    k.queryBuilder()
      .with('withClause', function () {
        this.select('foo').from('users').where({ name: 'bob' });
      })
      .insert([
        { email: 'thisMail', name: 'sam' },
        { email: 'thatMail', name: 'jack' },
      ])
      .into('users')],
  ['cte/update-source', (k) =>
    k.queryBuilder()
      .with(
        'updated_group',
        k.queryBuilder().table('group').update({ group_name: 'bar' }).where({ group_id: 1 }).returning('group_id'),
      )
      .table('user')
      .update({ name: 'foo' })
      .where({ group_id: 1 })],
  ['cte/delete-source', (k) =>
    k.queryBuilder()
      .with('delete1', (builder) => builder.delete().from('accounts').where('id', 1))
      .from('accounts')],

  // ── EXISTS / NOT EXISTS ──────────────────────────────────────────────────
  ['exists/where', (k) =>
    k('orders').select('*').whereExists(function () {
      this.select('*').from('products').where('products.id', '=', k.raw('"orders"."id"'));
    })],
  ['exists/where-not', (k) =>
    k('orders').select('*').whereNotExists(function () {
      this.select('*').from('products').where('products.id', '=', k.raw('"orders"."id"'));
    })],
  ['exists/or-where', (k) =>
    k('orders').select('*').where('id', '=', 1).orWhereExists(function () {
      this.select('*').from('products').where('products.id', '=', k.raw('"orders"."id"'));
    })],
  ['exists/or-where-not', (k) =>
    k('orders').select('*').where('id', '=', 1).orWhereNotExists(function () {
      this.select('*').from('products').where('products.id', '=', k.raw('"orders"."id"'));
    })],
  ['exists/wrapped-or', (k) =>
    k('orders').select('*').where('status', 'shipped').where(function () {
      this.whereExists(function () {
        this.select('*').from('products').where('products.id', '=', k.raw('"orders"."id"'));
      }).orWhereExists(function () {
        this.select('*').from('refunds').where('refunds.order_id', '=', k.raw('"orders"."id"'));
      });
    })],
  ['exists/with-select-subquery', (k) =>
    k('orders')
      .select('*', k('order_meta').select('value').where('order_meta.order_id', '=', k.raw('"orders"."id"')).as('meta_value'))
      .whereExists(function () {
        this.select('*').from('products').where('products.id', '=', k.raw('"orders"."id"'));
      })],

  // ── UNION / INTERSECT / EXCEPT ───────────────────────────────────────────
  ['union/three-way', (k) =>
    k('a').select('id').where('x', 1)
      .union(k('b').select('id').where('y', 2), k('c').select('id').where('z', 3))],
  ['union/array-callbacks', (k) =>
    k('users').select('*').where({ id: 1 })
      .union([
        function () { this.select('*').from('users').where({ id: 2 }); },
        function () { this.select('*').from('users').where({ id: 3 }); },
      ])],
  ['union/order-limit-outer', (k) =>
    k('a').select('id', 'name').where('x', 1)
      .union(k('b').select('id', 'name').where('y', 2))
      .orderBy('name')
      .limit(10)],
  ['intersect/basic', (k) =>
    k('a').select('*').where('id', '=', 1).intersect(k('b').select('*').where('id', '=', 2))],
  ['intersect/three-way', (k) =>
    k('a').select('id').intersect(k('b').select('id'), k('c').select('id'))],
  ['except/basic', (k) =>
    k('a').select('id').except(k('b').select('id'))],
  ['union/all-order-limit', (k) =>
    k('a').select('id').where('x', 1)
      .unionAll(k('b').select('id').where('y', 2))
      .orderBy('id', 'desc')
      .limit(5)
      .offset(2)],

  // ── Window / analytic functions ──────────────────────────────────────────
  ['window/rank-string-partition', (k) =>
    k('accounts').select('*').rank('alias_name', 'email', 'firstName')],
  ['window/rank-array-both', (k) =>
    k('accounts').select('*').rank('alias_name', ['email', 'address'], ['firstName', 'lastName'])],
  ['window/dense-rank-callback', (k) =>
    k('accounts').select('*').denseRank('test_alias', function () {
      this.orderBy('email').partitionBy('address');
    })],
  ['window/dense-rank-callback-chains', (k) =>
    k('accounts').select('*').denseRank('test_alias', function () {
      this.orderBy('email').partitionBy('address').partitionBy('phone').orderBy('name');
    })],
  ['window/row-number-array', (k) =>
    k('accounts').select('*').rowNumber('alias_name', ['email', 'address'], ['firstName', 'lastName'])],
  ['window/rank-raw', (k) =>
    k('accounts').select('*').rank(null, k.raw('partition by address order by email'))],
  ['window/chained-multiple', (k) =>
    k('accounts').select('*').denseRank('first_alias', 'email').denseRank('second_alias', 'address')],
  ['window/dense-rank-raw-alias', (k) =>
    k('accounts').select('*').denseRank('test_alias', k.raw('partition by address order by email'))],
  ['window/rank-then-orderby', (k) =>
    k('accounts').select('*').rank('rnk', 'salary').where('dept', '=', 'eng').orderBy('rnk')],

  // ── DML with RETURNING / onConflict ──────────────────────────────────────
  ['dml/onconflict-ignore', (k) =>
    k('users').insert([{ email: 'foo' }, { email: 'bar' }]).onConflict('email').ignore()],
  ['dml/onconflict-composite-ignore', (k) =>
    k('users').insert([{ org: 'acme-inc', email: 'foo' }]).onConflict(['org', 'email']).ignore()],
  ['dml/onconflict-merge-explicit', (k) =>
    k('users').from('users')
      .insert([{ email: 'foo', name: 'taylor' }, { email: 'bar', name: 'dayle' }])
      .onConflict('email')
      .merge({ name: 'overidden' })],
  ['dml/onconflict-merge-implicit-multi', (k) =>
    k('users').from('users')
      .insert([{ email: 'foo', name: 'taylor' }, { email: 'bar', name: 'dayle' }])
      .onConflict('email')
      .merge()],
  ['dml/onconflict-raw-target', (k) =>
    k('users').insert([{ email: 'foo' }, { email: 'bar' }])
      .onConflict(k.raw('(value) WHERE deleted_at IS NULL'))
      .ignore()],
  ['dml/onconflict-merge-where', (k) =>
    k('users').insert({ email: 'foo', name: 'taylor' }).onConflict('email').merge().where('email', 'foo2')],
  ['dml/returning-multi-insert', (k) =>
    k('users').insert([{ email: 'a' }, { email: 'b' }]).returning(['id', 'email'])],
  ['dml/returning-update', (k) =>
    k('users').where('id', 1).update({ name: 'Bob' }).returning('*')],
  ['dml/returning-delete', (k) =>
    k('users').where('id', 1).del().returning('id')],

  // Batch 4 — mined from knex.js test/unit/query/builder.js lines 385-1917
  // (select/alias shapes, clear(), where variants, raw wheres, where-in edge
  // cases). Only shapes with a knex-dart API equivalent are mined; JS-only
  // overloads (multi-arg select(), whereLike/whereILike family, custom
  // wrapIdentifier/queryContext, toQuery()-only assertions) are out of scope
  // — see the parity mining report for the full skip list.
  ['select/star', (k) => k('users').select('*')],
  ['select/multi-calls', (k) => k('users').select('foo').select('bar').select(['baz', 'boom'])],
  ['select/distinct-then-select', (k) => k('users').distinct().select('foo', 'bar')],
  ['select/alias-map', (k) => k('users').select({ bar: 'foo' })],
  ['select/alias-array-mixed', (k) => k('users').select(['baz', { bar: 'foo' }])],
  ['select/old-style-alias', (k) => k('users').select('foo as bar')],
  ['select/alias-trim-spaces', (k) => k('users').select(' foo   as bar ')],
  ['select/alias-case-insensitive', (k) => k('users').select(' foo   aS bar ')],
  ['select/alias-dotted', (k) => k('users').select('foo as bar.baz')],
  ['table/dotted-schema', (k) => k('public.users').select('*')],

  ['clear/select-basic', (k) => k('users').select('id', 'email').clearSelect()],
  ['clear/select-then-reselect', (k) => k('users').select('id').clearSelect().select('email')],
  ['clear/where-basic', (k) => k('users').select('id').where('id', '=', 1).clearWhere()],
  ['clear/where-then-rewhere', (k) =>
    k('users').select('id').where('id', '=', 1).clearWhere().where('id', '=', 2)],
  ['clear/group-basic', (k) => k('users').groupBy('name').clearGroup()],
  ['clear/group-then-regroup', (k) => k('users').groupBy('name').clearGroup().groupBy('id')],
  ['clear/order-basic', (k) => k('users').orderBy('name', 'desc').clearOrder()],
  ['clear/order-then-reorder', (k) =>
    k('users').orderBy('name', 'desc').clearOrder().orderBy('id', 'asc')],
  ['clear/having-then-rehaving', (k) =>
    k('users').having('id', '>', 100).clearHaving().having('id', '>', 10)],
  ['clear/counters', (k) =>
    k('users')
      .where('id', '=', 1)
      .update({ email: 'foo@bar.com' })
      .increment('balance', 10)
      .clear('counter')
      .decrement('value', 50)
      .clear('counters')],

  // Batch 2 (HAVING) — mined from knex.js test/unit/query/builder.js lines
  // 3547-5949.

  // ── HAVING ────────────────────────────────────────────────────────────
  ['having/nested', (k) =>
    k('users').select('*').having(function () { this.where('email', '>', 1); })],
  ['having/nested-or', (k) =>
    k('users').select('*').having(function () {
      this.where('email', '>', 10);
      this.orWhere('email', '=', 7);
    })],
  ['having/grouped', (k) =>
    k('users').select('*').from('users').groupBy('email').having('email', '>', 1)],
  ['having/from-alias', (k) =>
    k('users').select('email as foo_email').from('users').having('foo_email', '>', 1)],
  ['having/raw', (k) =>
    k('users').select('*').from('users').having(k.raw('user_foo < user_bar'))],
  ['having/raw-or', (k) =>
    k('users').select('*').from('users').having('baz', '=', 1).orHaving(k.raw('user_foo < user_bar'))],
  ['having/null', (k) => k('users').select('*').havingNull('baz')],
  ['having/or-null', (k) => k('users').select('*').havingNull('baz').orHavingNull('foo')],
  ['having/not-null', (k) => k('users').select('*').havingNotNull('baz')],
  ['having/or-not-null', (k) =>
    k('users').select('*').havingNotNull('baz').orHavingNotNull('foo')],
  ['having/exists', (k) =>
    k('users').select('*').havingExists(function () { this.select('baz').from('users'); })],
  ['having/or-exists', (k) =>
    k('users').select('*')
      .havingExists(function () { this.select('baz').from('users'); })
      .orHavingExists(function () { this.select('foo').from('users'); })],
  ['having/not-exists', (k) =>
    k('users').select('*').havingNotExists(function () { this.select('baz').from('users'); })],
  ['having/or-not-exists', (k) =>
    k('users').select('*')
      .havingNotExists(function () { this.select('baz').from('users'); })
      .orHavingNotExists(function () { this.select('foo').from('users'); })],
  ['having/between', (k) => k('users').select('*').havingBetween('baz', [5, 10])],
  ['having/or-between', (k) =>
    k('users').select('*').havingBetween('baz', [5, 10]).orHavingBetween('baz', [20, 30])],
  ['having/not-between', (k) => k('users').select('*').havingNotBetween('baz', [5, 10])],
  ['having/or-not-between', (k) =>
    k('users').select('*').havingNotBetween('baz', [5, 10]).orHavingNotBetween('baz', [20, 30])],
  ['having/in', (k) => k('users').select('*').havingIn('baz', [5, 10, 37])],
  ['having/or-in', (k) =>
    k('users').select('*').havingIn('baz', [5, 10, 37]).orHavingIn('foo', ['Batman', 'Joker'])],
  ['having/not-in', (k) => k('users').select('*').havingNotIn('baz', [5, 10, 37])],
  ['having/or-not-in', (k) =>
    k('users').select('*').havingNotIn('baz', [5, 10, 37]).orHavingNotIn('foo', ['Batman', 'Joker'])],

  // ── Batch 3 (lines 5950-8353 of knex.js's builder.js) ────────────────────
  // insert edge cases, update() basic variations, and MySQL UPDATE...
  // ORDER BY/LIMIT/JOIN probes.

  // ── Insert edge cases ──────────────────────────────────────────────────
  ['insert/ragged-defaults-3col', (k) =>
    k('table').insert([{ a: 1 }, { b: 2 }, { a: 2, c: 3 }])],
  ['insert/empty-array-noop', (k) =>
    k.queryBuilder().into('users').insert([])],
  ['insert/empty-object-returning', (k) =>
    k.queryBuilder().into('users').insert([{}], 'id')],
  ['insert/raw-value', (k) =>
    k.queryBuilder().insert({ email: k.raw('CURRENT TIMESTAMP') }).into('users')],

  // ── update() basic variations ────────────────────────────────────────────
  ['update/two-cols', (k) =>
    k.queryBuilder().update({ email: 'foo', name: 'bar' }).table('users').where('id', '=', 1)],
  ['update/null-value', (k) =>
    k.queryBuilder().update({ email: null, name: 'bar' }).table('users').where('id', 1)],
  ['update/from-where-then-update', (k) =>
    k('users').where('id', '=', 1).update({ email: 'foo', name: 'bar' })],
  ['update/raw-value', (k) =>
    k('users').where('id', '=', 1).update({ email: k.raw('foo'), name: 'bar' })],

  // ── update() + orderBy/limit/join — probing whether they're honored ─────
  ['update/orderby-limit', (k) =>
    k('users').where('id', '=', 1).orderBy('foo', 'desc').limit(5).update({ email: 'foo', name: 'bar' })],
  ['update/join-mysql', (k) =>
    k('users').join('orders', 'users.id', 'orders.user_id').where('users.id', '=', 1).update({ email: 'foo', name: 'bar' })],
  ['update/limit-mysql', (k) =>
    k('users').where('users.id', '=', 1).update({ email: 'foo', name: 'bar' }).limit(1)],
  ['update/join-mysql-qualified-col', (k) =>
    k('tblPerson').update({ 'tblPerson.City': 'Boonesville' })
      .join('tblPersonData', 'tblPersonData.PersonId', '=', 'tblPerson.PersonId')
      .where('tblPersonData.DataId', 1)
      .where('tblPerson.PersonId', 5)],

  // Batch 4 — mined from knex.js test/unit/query/builder.js lines 8354-end.
  // Window-function callback/chain shapes, insert-value subqueries, raw
  // identifier substitution (?? / :key:), CTE + simple UPDATE/DELETE,
  // knex.ref(), .first() chained onto a non-select method, DELETE + JOIN
  // (Postgres/CockroachDB USING transform vs MySQL/SQLite/Redshift JOIN
  // clause), and the JSON-where family (whereJsonObject/whereJsonPath/
  // whereJsonSupersetOf/whereJsonSubsetOf).

  // ── Window functions (representative shapes only — rank/denseRank/
  // rowNumber all share one dispatcher, so one case per *shape* covers all
  // three; see parity_cases.dart) ──────────────────────────────────────────
  ['window/rank-callback-orderby-only', (k) =>
    k('accounts').select('*').rank(null, function () { this.orderBy('email'); })],
  ['window/rank-callback-alias-partition', (k) =>
    k('accounts').select('*').rank('test_alias', function () {
      this.orderBy('email').partitionBy('address');
    })],
  ['window/rank-callback-arrays', (k) =>
    k('accounts').select('*').rank('test_alias', function () {
      this.orderBy(['email', 'name']).partitionBy(['address', 'phone']);
    })],
  ['window/rank-chained-multiple', (k) =>
    k('accounts').select('*').rank('first_alias', 'email').rank('second_alias', 'address')],
  ['window/rank-raw-alias', (k) =>
    k('accounts').select('*').rank('test_alias', k.raw('partition by address order by email'))],
  ['window/row-number-no-partition', (k) =>
    k('accounts').select('*').rowNumber(null, 'email')],

  // ── Insert / subqueries ───────────────────────────────────────────────
  ['insert/value-subselect', (k) =>
    k('entries').insert({
      secret: 123,
      sequence: k('entries').count('*').where('secret', 123),
    })],
  ['subquery/from-no-alias', (k) => {
    const subquery = k.queryBuilder().select(k.raw('?', ['inner raw select']), 'bar');
    return k.queryBuilder().select(k.raw('?', ['outer raw select'])).from(subquery);
  }],

  // ── select() / where() extras ────────────────────────────────────────
  ['select/fromraw', (k) => k.queryBuilder().select('*').fromRaw('(select * from users where age > 18)')],
  ['select/modify-callback', (k) => {
    const withBars = function (queryBuilder, table, fk) {
      this.leftJoin('bars', table + '.' + fk, 'bars.id').select('bars.*');
    };
    return k.queryBuilder().select('foo_id').from('foos').modify(withBars, 'foos', 'bar_id');
  }],
  ['where/empty-callback', (k) => k.queryBuilder().select('foo').from('tbl').where(() => {})],
  ['where/not-raw', (k) => k.queryBuilder().from('testtable').whereNot(k.raw('is_active'))],
  ['where/or-raw', (k) => k('users').where('a', 1).orWhere(k.raw('b = 2'))],
  ['where/named-binding-array', (k) =>
    k.queryBuilder().select('*').from('users').whereIn('id', k.raw('select (:test)', { test: [1, 2, 3] }))],
  ['where/named-binding-identifier', (k) =>
    k.queryBuilder().select('*').from('users').where(
      k.raw(':name: = :thisGuy or :name: = :otherGuy', {
        name: 'users.name',
        thisGuy: 'Bob',
        otherGuy: 'Jay',
      })
    )],
  ['jsonb/pipe-op', (k) => k('users').select('*').where('id', '?|', 1)],
  ['jsonb/amp-op', (k) => k('users').select('*').where('id', '?&', 1)],
  ['select/numeric-literal', (k) => k.queryBuilder().select(0)],

  // ── CTE + simple UPDATE/DELETE (as opposed to batch-3's cte/update-source
  // and cte/delete-source, where the WITH body itself is the mutating
  // statement — here the outer query is the mutation and the CTE is a
  // plain SELECT feeding it) ───────────────────────────────────────────────
  ['cte/update-simple', (k) =>
    k.queryBuilder()
      .with('withClause', function () { this.select('foo').from('users'); })
      .update({ foo: 'updatedFoo' })
      .where('email', '=', 'foo')
      .from('users')],
  ['cte/delete-simple', (k) =>
    k.queryBuilder()
      .with('withClause', function () { this.select('email').from('users'); })
      .del()
      .where('foo', '=', 'updatedFoo')
      .from('users')],

  // ── knex.ref() ────────────────────────────────────────────────────────
  ['ref/where-column', (k) =>
    k.queryBuilder().table('sometable').where('sometable.column', k.ref('someothertable.someothercolumn')).select()],
  ['ref/select-alias', (k) =>
    k.queryBuilder().table('sometable').select(['one', k.ref('sometable.two').as('Two')])],

  // ── .first() chained onto a non-select method — must throw ────────────
  ['errors/first-on-update', (k) => k.queryBuilder().table('sometable').update({ column: 'value' }).first()],
  ['errors/first-on-insert', (k) => k.queryBuilder().table('sometable').insert({ column: 'value' }).first()],
  ['errors/first-on-delete', (k) => k.queryBuilder().table('sometable').del().first()],

  // ── DELETE + JOIN (previously silently dropped the join in knex-dart —
  // see the fix in query_compiler.dart's _deleteQuery()) ──────────────────
  ['delete/join-single', (k) =>
    k.queryBuilder().del().from('users').join('photos', 'photos.id', 'users.id').where({ 'user.email': 'mock@example.com' })],
  ['delete/join-multi', (k) =>
    k.queryBuilder().del().from('users')
      .join('photos', 'photos.id', 'users.id')
      .join('docs', 'docs.id', 'users.id')
      .where({ 'user.email': 'mock@example.com' })],
  ['delete/join-no-where', (k) =>
    k.queryBuilder().del().from('users').join('photos', 'photos.id', 'users.id')],
  ['delete/join-oncallback-where', (k) =>
    k.queryBuilder().table('users').where('activated', false).join('accounts', function (jb) {
      jb.on('accounts.id', 'users.account_id').andOn('accounts.user_id', 'users.id');
    }).del()],

  // ── JSON where family (adapted from knex.js tests that paired these with
  // whereJsonNot*/orWhereNotJsonObject — knex-dart has no "Not" variant of
  // these, so both sides here use the plain/OR forms only) ────────────────
  ['json/where-object', (k) =>
    k('users').select()
      .whereJsonObject('address', { street: 'street1', number: 5 })
      .orWhereJsonObject('address', { street: 'street2', number: 7 })],
  ['json/where-path', (k) =>
    k('users').select()
      .whereJsonPath('address', '$.street.number', '>', 5)
      .orWhereJsonPath('address', '$.street.number', '<', 8)],
  ['json/where-superset-object', (k) =>
    k('users').select()
      .whereJsonSupersetOf('address', { test: 'value' })
      .orWhereJsonSupersetOf('address', { test: 'value2' })],
  ['json/where-superset-string', (k) =>
    k('users').select()
      .whereJsonSupersetOf('address', 'test')
      .orWhereJsonSupersetOf('address', 'test2')],
  ['json/where-subset', (k) =>
    k('users').select()
      .whereJsonSubsetOf('address', { test: 'value' })
      .orWhereJsonSubsetOf('address', { test: 'value2' })],

  // Batch 5 — mined from knex.js test/unit/query/builder.js regions not
  // covered by batches 1-4 (lines 1918-3546: set-ops wrap flag, JOIN family
  // cross/full-outer/right/using/raw arg, on-* join-clause family, sub
  // select where ins, countDistinct multi-column, raw group/order, plus
  // whereColumn / whereNotBetween).

  // ── Set-ops wrap=true quartet ───────────────────────────────────────
  ['union/wrapped-array', (k) =>
    k('users').select('*').where({ id: 1 }).union([
      function () { this.select('*').from('users').where({ id: 2 }); },
      function () { this.select('*').from('users').where({ id: 3 }); },
    ], true)],
  ['unionAll/wrapped-array', (k) =>
    k('users').select('*').where({ id: 1 }).unionAll([
      function () { this.select('*').from('users').where({ id: 2 }); },
      function () { this.select('*').from('users').where({ id: 3 }); },
    ], true)],
  ['intersect/wrapped-array', (k) =>
    k('users').select('*').where({ id: 1 }).intersect([
      function () { this.select('*').from('users').where({ id: 2 }); },
      function () { this.select('*').from('users').where({ id: 3 }); },
    ], true)],
  ['except/wrapped-array', (k) =>
    k('users').select('*').where({ id: 1 }).except([
      function () { this.select('*').from('users').where({ id: 2 }); },
      function () { this.select('*').from('users').where({ id: 3 }); },
    ], true)],

  // ── whereColumn, whereNotBetween ────────────────────────────────────
  ['where/column', (k) =>
    k('users').select('*').whereColumn('users.id', '=', 'users.otherId')],
  ['where/not-between', (k) =>
    k('users').select('*').whereNotBetween('id', [1, 2])],
  ['where/not-between-alt', (k) =>
    k('users').select('*').where('id', 'not between ', [1, 2])],

  // ── countDistinct multi-column (pg wraps in extra parens) ───────────
  ['agg/count-distinct-multi-col', (k) =>
    k('users').countDistinct('foo', 'bar')],

  // ── Raw group/order ─────────────────────────────────────────────────
  ['group/raw', (k) =>
    k('users').select('*').groupByRaw('id, email')],
  ['order/raw', (k) =>
    k('users').select('*').orderByRaw('col NULLS LAST DESC')],
  ['order/raw-with-binding', (k) =>
    k('users').select('*').orderByRaw('col NULLS LAST ?', 'dEsc')],

  // ── JOIN family: cross, full-outer, right, joins with raw ───────────
  ['join/cross-multi', (k) =>
    k('users').select('*').crossJoin('contracts').crossJoin('photos')],
  // knex.js `crossJoin('t', 'a', 'b')` form (CROSS JOIN ... ON) has no
  // knex-dart API equivalent (dart's crossJoin is cross-product only).
  // Deliberately skipped — see parity_cases.dart for the rationale.
  ['join/full-outer', (k) =>
    k('users').select('*').fullOuterJoin('contacts', 'users.id', '=', 'contacts.id')],
  ['join/right-and-right-outer', (k) =>
    k('users').select('*')
      .rightJoin('contacts', 'users.id', '=', 'contacts.id')
      .rightOuterJoin('photos', 'users.id', '=', 'photos.id')],
  ['join/raw-operand', (k) =>
    k('users').select('*')
      .join('contacts', 'users.id', k.raw(1))
      .leftJoin('photos', 'photos.title', '=', k.raw('?', ['My Photo']))],

  // ── on-* family in JOIN clause ──────────────────────────────────────
  ['on/null', (k) =>
    k('users').select('*').join('contacts', function (qb) {
      qb.on('users.id', '=', 'contacts.id').onNull('contacts.address');
    })],
  ['on/or-null', (k) =>
    k('users').select('*').join('contacts', function (qb) {
      qb.on('users.id', '=', 'contacts.id')
        .onNull('contacts.address')
        .orOnNull('contacts.phone');
    })],
  ['on/not-null', (k) =>
    k('users').select('*').join('contacts', function (qb) {
      qb.on('users.id', '=', 'contacts.id').onNotNull('contacts.address');
    })],
  ['on/or-not-null', (k) =>
    k('users').select('*').join('contacts', function (qb) {
      qb.on('users.id', '=', 'contacts.id')
        .onNotNull('contacts.address')
        .orOnNotNull('contacts.phone');
    })],
  ['on/in', (k) =>
    k('users').select('*').join('contacts', function (qb) {
      qb.onIn('users.id', [1, 2, 3]);
    })],
  ['on/or-in', (k) =>
    k('users').select('*').join('contacts', function (qb) {
      qb.onIn('users.id', [1, 2, 3]).orOnIn('users.id', [4, 5]);
    })],
  ['on/not-in', (k) =>
    k('users').select('*').join('contacts', function (qb) {
      qb.onNotIn('users.id', [1, 2, 3]);
    })],
  ['on/between', (k) =>
    k('users').select('*').join('contacts', function (qb) {
      qb.onBetween('users.id', [1, 5]);
    })],
  ['on/not-between', (k) =>
    k('users').select('*').join('contacts', function (qb) {
      qb.onNotBetween('users.id', [1, 5]);
    })],
  ['on/exists', (k) =>
    k('users').select('*').join('contacts', function (qb) {
      qb.onExists(function () { this.select('*').from('phones').where('phones.contact_id', '=', k.raw('"contacts"."id"')); });
    })],
  ['on/not-exists', (k) =>
    k('users').select('*').join('contacts', function (qb) {
      qb.onNotExists(function () { this.select('*').from('phones').where('phones.contact_id', '=', k.raw('"contacts"."id"')); });
    })],
];

const out = [];
for (const [id, build] of cases) {
  for (const [dialect, cfg] of Object.entries(DIALECTS)) {
    const k = clientFor(cfg.knex);
    const entry = { id, dialect };
    if (cfg.family) entry.family = cfg.family;
    try {
      const native = build(k).toSQL().toNative();
      entry.sql = native.sql;
      entry.bindings = native.bindings;
    } catch (e) {
      // A refusal is meaningful data: the Dart side may refuse too (parity) or
      // not (finding). Record it rather than dropping the case.
      entry.error = String((e && e.message) || e);
    }
    out.push(entry);
  }
}

const __dirname = dirname(fileURLToPath(import.meta.url));
const target = resolve(
  __dirname,
  '../../packages/knex_dart/test/parity/fixtures/parity_cases.json',
);
const payload = {
  _comment: 'GENERATED by tool/parity/run_js.mjs — do not edit by hand.',
  knexVersion,
  generatedAt: new Date().toISOString().slice(0, 10),
  dialects: Object.fromEntries(
    Object.entries(DIALECTS).map(([d, c]) => [d, c.knex + (c.family ? ` (family:${c.family})` : '')]),
  ),
  caseCount: out.length,
  cases: out,
};
writeFileSync(target, JSON.stringify(payload, null, 2) + '\n');

const errs = out.filter((c) => c.error);
console.log(`Wrote ${out.length} entries (${cases.length} cases × ${Object.keys(DIALECTS).length} dialects, knex ${knexVersion}) → ${target}`);
if (errs.length) console.log(`  ${errs.length} refused on the JS side (capability differences to reconcile with Dart).`);
