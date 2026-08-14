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

  ['schema/create-table-foreign-both-actions', (k) => k.schema.createTable('orders', (t) => {
    t.increments('id');
    t.integer('user_id');
    t.foreign('user_id').references('id').inTable('users').onDelete('cascade').onUpdate('set null');
  })],

  // Directly mirrored from the defaultTo() cases in knex.js's sqlite3.js,
  // mysql.js, and postgres.js schema-builder suites.
  ['schema/default-string-embedded-quote', (k) => k.schema.alterTable('users', (t) => {
    t.string('nickname').defaultTo("single 'quoted' value");
  })],

  ['schema/default-null', (k) => k.schema.alterTable('users', (t) => {
    t.string('nickname').defaultTo(null);
  })],

  ['schema/default-string-not-null', (k) => k.schema.alterTable('users', (t) => {
    t.string('nickname', 100).notNullable().defaultTo('guest');
  })],

  ['schema/default-raw-current-timestamp', (k) => k.schema.alterTable('users', (t) => {
    t.timestamp('created_at').defaultTo(k.raw('CURRENT_TIMESTAMP'));
  })],

  ['schema/default-boolean-false', (k) => k.schema.alterTable('users', (t) => {
    t.boolean('enabled').defaultTo(false);
  })],

  ['schema/default-json-object', (k) => k.schema.alterTable('users', (t) => {
    t.json('preferences').defaultTo({}).notNullable();
  })],

  ['schema/default-jsonb-object', (k) => k.schema.alterTable('users', (t) => {
    t.jsonb('preferences').defaultTo({}).notNullable();
  })],

  ['schema/create-table-column-primary', (k) => k.schema.createTable('users', (t) => {
    t.string('external_id').primary();
  })],

  ['schema/create-table-unique-composite-named', (k) => k.schema.createTable('memberships', (t) => {
    t.integer('user_id');
    t.integer('org_id');
    t.unique(['user_id', 'org_id'], 'uq_membership');
  })],

  ['schema/alter-table-add-unique-composite', (k) => k.schema.alterTable('memberships', (t) => {
    t.unique(['user_id', 'org_id']);
  })],

  ['schema/alter-table-add-index-composite', (k) => k.schema.alterTable('memberships', (t) => {
    t.index(['user_id', 'org_id']);
  })],

  ['schema/alter-table-add-column-foreign', (k) => k.schema.alterTable('orders', (t) => {
    t.integer('user_id').references('id').inTable('users');
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

  // Column type + modifier dispatch (unsigned is MySQL-only grammar;
  // postgres/sqlite silently ignore it — real dialect-dispatch territory).
  ['schema/create-table-column-unsigned', (k) => k.schema.createTable('t', (t) => {
    t.integer('qty').unsigned();
  })],

  // NOTE: exercised as an ADD (not a MODIFY/.alter()) — knex-dart's
  // ColumnBuilder has no generic .alter() at all (by design: it exposes
  // narrow setNullable()/dropNullable() instead of a generic "redefine this
  // column" op — see the alter-table-set-nullable::postgres allowlist entry
  // for the rationale), so `.unsigned().alter()` has no Dart-side mirror.
  ['schema/alter-table-column-unsigned', (k) => k.schema.alterTable('t', (t) => {
    t.integer('qty').unsigned();
  })],

  // NOTE: column-level .comment() intentionally NOT added here — knex-dart's
  // ColumnBuilder has no comment() method at all (only TableBuilder.comment()
  // for table-level comments), so there is no Dart-side call to mirror this
  // with. Confirmed via `grep -n comment lib/src/schema/*.dart`. This is a
  // real capability gap (postgres: separate `COMMENT ON COLUMN` statement;
  // mysql: inline `COMMENT '...'`; sqlite: unsupported) but adding the
  // feature (new public API + dispatch in schema_compiler/column_builder for
  // 3 dialect families) is a scoped feature addition, not a parity fix —
  // left out of this harness and reported separately.

  // NOTE: a `.alter()` type-change case (postgres 3-statement drop-default/
  // drop-not-null/type-cast sequence vs mysql single MODIFY vs sqlite PRAGMA
  // rebuild) intentionally NOT added — same reason as the unsigned-alter
  // note above: no generic .alter() exists on knex-dart's ColumnBuilder to
  // mirror it with. Already covered in spirit by the existing
  // alter-table-set-nullable/drop-nullable allowlist entries, which document
  // this exact API-shape difference.

  // NOTE: a composite (multi-column) named foreign key via alterTable
  // (`t.foreign(['user_id','org_id'], 'name').references([...]).inTable(...)`)
  // intentionally NOT added here — knex-dart's `TableBuilder.foreign()` only
  // accepts a single `String column` (see ForeignBuilder in
  // table_builder.dart), so there is no Dart-side call to mirror knex.js's
  // composite-FK fluent form with. `primary()`/`unique()`/`index()` all
  // accept `dynamic columns` (single or list) + optional name, but
  // `foreign()` never gained the same treatment — a genuine, real capability
  // gap. Fixing it means changing a public API signature
  // (`foreign(String)` -> `foreign(dynamic, [String?])`) and updating
  // foreign-key generation at ~6 call sites across schema_compiler.dart
  // (createTable inline, alterTable add-column deferred, alterTable
  // drop-foreign naming, alterTable fluent foreign, plus duplicated logic
  // further down the file) that all currently assume a single column/
  // reference string baked into interpolation — architectural, not a small
  // fix. Left out of this harness and reported separately.
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
