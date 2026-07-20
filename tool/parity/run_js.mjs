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
  ['union/all', (k) => k('a').select('id').unionAll([k('b').select('id')])],

  // Known-divergence probe (jsonb key-existence operator).
  ['jsonb/qmark-op', (k) => k('t').where('tags', '?', 'urgent')],
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
