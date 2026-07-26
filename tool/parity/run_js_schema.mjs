#!/usr/bin/env node
// Differential parity fixture generator — SCHEMA DDL (knex.js reference side).
//
// Sibling to run_js.mjs, which covers the query builder. Schema DDL got its
// own script/fixture/corpus because knex.js's schema builder `.toSQL()`
// returns an ARRAY of statements (not one), and comparison needs the same
// shape on both sides — see schema_parity_test.dart.
//
// Motivation: a dart_mutant mutation-testing pass on schema_compiler.dart
// found the largest untested cluster in the whole compiler was dialect
// dispatch in schema DDL (sqlite/mysql/mssql branching for
// primary/unique/foreign key/index) — ~215 surviving mutants. This corpus
// targets exactly that dispatch.
//
// Regenerate: node tool/parity/run_js_schema.mjs

import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const KNEX_PATH = process.env.KNEX_JS_PATH
  || '/Users/kartik/StudioProjects/knex/knex-js/knex.js';
const KNEX_PKG = process.env.KNEX_JS_PKG
  || '/Users/kartik/StudioProjects/knex/knex-js/package.json';

const { default: knex } = await import(KNEX_PATH);
const { version: knexVersion } = (await import(KNEX_PKG, { with: { type: 'json' } })).default;

// Same dialect matrix/tiers as run_js.mjs (query corpus) — see its header.
const DIALECTS = {
  postgres: { knex: 'pg' },
  cockroachdb: { knex: 'cockroachdb' },
  redshift: { knex: 'redshift' },
  mysql: { knex: 'mysql2' },
  sqlite: { knex: 'sqlite3', useNullAsDefault: true },
  turso: { knex: 'sqlite3', useNullAsDefault: true, family: 'sqlite' },
  d1: { knex: 'sqlite3', useNullAsDefault: true, family: 'sqlite' },
};

const clientCache = {};
function clientFor(cfg) {
  const cacheKey = cfg.knex + (cfg.useNullAsDefault ? ':nnad' : '');
  return (clientCache[cacheKey] ??= knex({
    client: cfg.knex,
    useNullAsDefault: cfg.useNullAsDefault,
  }));
}

// ── Corpus (dialect-agnostic) ────────────────────────────────────────────────
// [id, build]. `build(k)` returns a SchemaBuilder (via k.schema...). IDs are
// the contract with the Dart side — keep them stable.
const cases = [
  ['schema/create-table-basic', (k) => k.schema.createTable('users', (t) => {
    t.increments('id');
    t.string('email');
    t.integer('age');
  })],

  ['schema/create-table-primary-composite', (k) => k.schema.createTable('memberships', (t) => {
    t.integer('user_id');
    t.integer('org_id');
    t.primary(['user_id', 'org_id']);
  })],

  ['schema/create-table-primary-named', (k) => k.schema.createTable('memberships', (t) => {
    t.integer('user_id');
    t.integer('org_id');
    t.primary(['user_id', 'org_id'], 'membership_pk');
  })],

  ['schema/create-table-unique-column', (k) => k.schema.createTable('users', (t) => {
    t.increments('id');
    t.string('email').unique();
  })],

  ['schema/create-table-unique-named', (k) => k.schema.createTable('users', (t) => {
    t.increments('id');
    t.string('email');
    t.unique(['email'], 'uq_users_email');
  })],

  ['schema/create-table-foreign-column', (k) => k.schema.createTable('orders', (t) => {
    t.increments('id');
    t.integer('user_id').references('id').inTable('users');
  })],

  ['schema/create-table-foreign-fluent-cascade', (k) => k.schema.createTable('orders', (t) => {
    t.increments('id');
    t.integer('user_id');
    t.foreign('user_id').references('id').inTable('users').onDelete('cascade');
  })],

  ['schema/create-table-foreign-onupdate', (k) => k.schema.createTable('orders', (t) => {
    t.increments('id');
    t.integer('user_id');
    t.foreign('user_id').references('id').inTable('users').onUpdate('cascade');
  })],

  ['schema/alter-table-add-column', (k) => k.schema.alterTable('users', (t) => {
    t.string('nickname');
  })],

  ['schema/alter-table-drop-column', (k) => k.schema.alterTable('users', (t) => {
    t.dropColumn('nickname');
  })],

  ['schema/alter-table-rename-column', (k) => k.schema.alterTable('users', (t) => {
    t.renameColumn('nickname', 'nick');
  })],

  ['schema/alter-table-add-unique', (k) => k.schema.alterTable('users', (t) => {
    t.unique(['email']);
  })],

  ['schema/alter-table-add-unique-named', (k) => k.schema.alterTable('users', (t) => {
    t.unique(['email'], 'uq_users_email');
  })],

  ['schema/alter-table-add-index', (k) => k.schema.alterTable('users', (t) => {
    t.index(['email']);
  })],

  ['schema/alter-table-add-index-named', (k) => k.schema.alterTable('users', (t) => {
    t.index(['email'], 'idx_users_email');
  })],

  ['schema/alter-table-drop-unique', (k) => k.schema.alterTable('users', (t) => {
    t.dropUnique(['email']);
  })],

  ['schema/alter-table-drop-unique-named', (k) => k.schema.alterTable('users', (t) => {
    t.dropUnique(['email'], 'uq_users_email');
  })],

  ['schema/alter-table-drop-index', (k) => k.schema.alterTable('users', (t) => {
    t.dropIndex(['email']);
  })],

  ['schema/alter-table-drop-index-named', (k) => k.schema.alterTable('users', (t) => {
    t.dropIndex(['email'], 'idx_users_email');
  })],

  ['schema/alter-table-drop-primary', (k) => k.schema.alterTable('memberships', (t) => {
    t.dropPrimary();
  })],

  ['schema/alter-table-drop-foreign', (k) => k.schema.alterTable('orders', (t) => {
    t.dropForeign(['user_id']);
  })],

  // Capability-varying: sqlite cannot ALTER TABLE ADD CONSTRAINT (primary,
  // foreign, not-null toggles), so knex.js reroutes through a PRAGMA-based
  // table-rebuild compat path instead of refusing outright. Expect a
  // documented ACCEPTED divergence here, not a bug.
  ['schema/alter-table-primary', (k) => k.schema.alterTable('memberships', (t) => {
    t.primary(['user_id', 'org_id']);
  })],

  ['schema/alter-table-foreign', (k) => k.schema.alterTable('orders', (t) => {
    t.foreign('user_id').references('id').inTable('users');
  })],

  ['schema/alter-table-set-nullable', (k) => k.schema.alterTable('users', (t) => {
    t.string('email').nullable().alter();
  })],

  ['schema/alter-table-drop-nullable', (k) => k.schema.alterTable('users', (t) => {
    t.string('email').notNullable().alter();
  })],

  ['schema/drop-table', (k) => k.schema.dropTable('users')],
  ['schema/drop-table-if-exists', (k) => k.schema.dropTableIfExists('users')],
  ['schema/rename-table', (k) => k.schema.renameTable('users', 'accounts')],
];

const out = [];
for (const [id, build] of cases) {
  for (const [dialect, cfg] of Object.entries(DIALECTS)) {
    const k = clientFor(cfg);
    const entry = { id, dialect };
    if (cfg.family) entry.family = cfg.family;
    try {
      const statements = build(k).toSQL();
      entry.statements = statements.map((s) => ({ sql: s.sql, bindings: s.bindings }));
    } catch (e) {
      entry.error = String((e && e.message) || e);
    }
    out.push(entry);
  }
}

const __dirname = dirname(fileURLToPath(import.meta.url));
const target = resolve(
  __dirname,
  '../../packages/knex_dart/test/parity/fixtures/schema_parity_cases.json',
);
const payload = {
  _comment: 'GENERATED by tool/parity/run_js_schema.mjs — do not edit by hand.',
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
