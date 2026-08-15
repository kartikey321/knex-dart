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

  // ── Mined from knex.js test/unit/schema-builder/mysql.js ──────────────────

  // createTableLike
  ['schema/create-table-like-basic', (k) => k.schema.createTableLike('users_like', 'users')],
  ['schema/create-table-like-with-columns', (k) => k.schema.createTableLike('users_like', 'users', (t) => {
    t.text('add_col');
    t.integer('numeric_col');
  })],

  // Composite primary key that also includes an incrementing column
  // (mysql.js "test basic create table with composite key on incrementing
  // column + other") — MySQL emits a 2nd `ALTER TABLE ... MODIFY COLUMN
  // ... auto_increment` statement because the incrementing column can't
  // carry its own inline PRIMARY KEY once it's part of a composite key.
  ['schema/create-table-primary-composite-with-increments', (k) => k.schema.createTable('users', (t) => {
    t.primary(['userId', 'name']);
    t.increments('userId');
    t.string('name');
  })],

  // Views (createView/dropView/renameView — no `.columns()` clause, since
  // knex-dart's createView() takes a definition directly rather than a
  // view-builder callback with a separate .columns() step).
  ['schema/view-create-basic', (k) => k.schema.createView('adults', (view) => {
    view.as(k('users').select('name').where('age', '>', '18'));
  })],
  ['schema/view-create-or-replace', (k) => k.schema.createViewOrReplace('adults', (view) => {
    view.as(k('users').select('name').where('age', '>', '18'));
  })],
  ['schema/view-drop', (k) => k.schema.dropView('users')],
  ['schema/view-drop-with-schema', (k) => k.schema.withSchema('myschema').dropView('users')],
  ['schema/view-rename', (k) => k.schema.renameView('old_view', 'new_view')],
  ['schema/view-create-materialized', (k) => k.schema.createMaterializedView('mat_view', (view) => {
    view.as(k('users').select('name').where('age', '>', '18'));
  })],
  ['schema/view-refresh-materialized', (k) => k.schema.refreshMaterializedView('view_to_refresh')],

  // Bare add of json/jsonb (no defaultTo — that's already covered by the
  // schema/default-json-object cases above).
  ['schema/alter-table-add-json', (k) => k.schema.alterTable('user', (t) => {
    t.json('preferences');
  })],
  ['schema/alter-table-add-jsonb', (k) => k.schema.alterTable('user', (t) => {
    t.jsonb('preferences');
  })],

  // dropColumn(s) — array form ("drops multiple columns with an array").
  ['schema/alter-table-drop-columns-multiple', (k) => k.schema.alterTable('users', (t) => {
    t.dropColumn(['foo', 'bar']);
  })],

  // dropUnique/dropIndex/dropForeign with columns omitted (null) and an
  // explicit custom name — mysql.js "test drop unique, custom" / "test drop
  // index, custom" / "test drop foreign, custom".
  ['schema/alter-table-drop-unique-null-columns-named', (k) => k.schema.alterTable('users', (t) => {
    t.dropUnique(null, 'foo');
  })],
  ['schema/alter-table-drop-index-null-columns-named', (k) => k.schema.alterTable('users', (t) => {
    t.dropIndex(null, 'foo');
  })],
  ['schema/alter-table-drop-foreign-null-columns-named', (k) => k.schema.alterTable('users', (t) => {
    t.dropForeign(null, 'foo');
  })],

  ['schema/alter-table-drop-timestamps', (k) => k.schema.alterTable('users', (t) => {
    t.dropTimestamps();
  })],

  // primary()/unique() with a single bare string column (not an array) plus
  // an explicit name — mysql.js "test adding primary key" / "test adding
  // unique key".
  ['schema/alter-table-primary-single-column', (k) => k.schema.alterTable('users', (t) => {
    t.primary('foo', 'bar');
  })],
  ['schema/alter-table-unique-single-column', (k) => k.schema.alterTable('users', (t) => {
    t.unique('foo', 'bar');
  })],

  // Composite named primary key via alterTable (mysql.js "#1430 - .primary
  // & .dropPrimary takes columns and constraintName").
  ['schema/alter-table-primary-named', (k) => k.schema.alterTable('users', (t) => {
    t.primary(['test1', 'test2'], 'testconstraintname');
  })],

  // Bare adds of incrementing columns via alterTable.
  ['schema/alter-table-add-increments', (k) => k.schema.alterTable('users', (t) => {
    t.increments('id');
  })],
  ['schema/alter-table-add-bigincrements', (k) => k.schema.alterTable('users', (t) => {
    t.bigIncrements('id');
  })],

  // Bare column-type adds not otherwise covered by an existing case.
  ['schema/alter-table-add-text', (k) => k.schema.alterTable('users', (t) => {
    t.text('foo');
  })],
  ['schema/alter-table-add-biginteger', (k) => k.schema.alterTable('users', (t) => {
    t.bigInteger('foo');
  })],
  ['schema/alter-table-add-boolean', (k) => k.schema.alterTable('users', (t) => {
    t.boolean('foo');
  })],
  ['schema/alter-table-add-enum', (k) => k.schema.alterTable('users', (t) => {
    t.enum('foo', ['bar', 'baz']);
  })],
  ['schema/alter-table-add-date', (k) => k.schema.alterTable('users', (t) => {
    t.date('foo');
  })],
  ['schema/alter-table-add-datetime', (k) => k.schema.alterTable('users', (t) => {
    t.dateTime('foo');
  })],
  ['schema/alter-table-add-time', (k) => k.schema.alterTable('users', (t) => {
    t.time('foo');
  })],
  ['schema/alter-table-add-timestamp', (k) => k.schema.alterTable('users', (t) => {
    t.timestamp('foo');
  })],
  ['schema/alter-table-add-timestamps', (k) => k.schema.alterTable('users', (t) => {
    t.timestamps();
  })],
  ['schema/alter-table-add-binary', (k) => k.schema.alterTable('users', (t) => {
    t.binary('foo');
  })],
  ['schema/alter-table-add-uuid', (k) => k.schema.alterTable('users', (t) => {
    t.uuid('foo');
  })],
  ['schema/alter-table-add-decimal', (k) => k.schema.alterTable('users', (t) => {
    t.decimal('foo', 5, 2);
  })],
  ['schema/alter-table-add-double', (k) => k.schema.alterTable('users', (t) => {
    t.double('foo');
  })],

  // Raw defaultTo inside createTable (mysql.js "is possible to set raw
  // statements in defaultTo, #146" — the existing schema/default-raw-
  // current-timestamp case is the alterTable form of this).
  ['schema/create-table-default-raw-timestamp', (k) => k.schema.createTable('default_raw_test', (t) => {
    t.timestamp('created_at').defaultTo(k.raw('CURRENT_TIMESTAMP'));
  })],

  // dropUnique with a composite (2-column), unnamed index (mysql.js "allows
  // dropping a unique compound index").
  ['schema/alter-table-drop-unique-composite', (k) => k.schema.alterTable('composite_key_test', (t) => {
    t.dropUnique(['column_a', 'column_b']);
  })],

  // Table-level comment (mysql.js "test set comment" / "test set empty
  // comment").
  ['schema/alter-table-comment', (k) => k.schema.alterTable('users', (t) => {
    t.comment('Custom comment');
  })],
  ['schema/create-table-comment', (k) => k.schema.createTable('users', (t) => {
    t.string('username');
    t.comment('Custom comment');
  })],

  // ── Mined from knex.js test/unit/schema-builder/redshift.js ──────────────
  // (schema DDL batch 4 — see tool/parity/README.md). Cases are written
  // dialect-agnostically; the harness multiplies each across every dialect.
  // Column-type shapes deliberately use only the arguments knex-dart's
  // narrower API surface can express (e.g. plain `t.float('foo')`, not
  // `t.float('foo', 5, 2)` — knex-dart's float()/double() take no
  // precision/scale) so a case tests dialect dispatch, not a manufactured
  // signature mismatch.

  // ── Column types (via alterTable, one column each) ────────────────────────
  ['schema/column-increments', (k) => k.schema.alterTable('users', (t) => {
    t.increments('foo');
  })],
  ['schema/column-bigincrements', (k) => k.schema.alterTable('users', (t) => {
    t.bigIncrements('foo');
  })],
  ['schema/column-string-length', (k) => k.schema.alterTable('users', (t) => {
    t.string('foo', 100);
  })],
  ['schema/column-string-default', (k) => k.schema.alterTable('users', (t) => {
    t.string('foo', 100).defaultTo('bar');
  })],
  ['schema/column-text', (k) => k.schema.alterTable('users', (t) => {
    t.text('foo');
  })],
  ['schema/column-biginteger', (k) => k.schema.alterTable('users', (t) => {
    t.bigInteger('foo');
  })],
  ['schema/column-integer', (k) => k.schema.alterTable('users', (t) => {
    t.integer('foo');
  })],
  ['schema/column-float', (k) => k.schema.alterTable('users', (t) => {
    t.float('foo');
  })],
  ['schema/column-double', (k) => k.schema.alterTable('users', (t) => {
    t.double('foo');
  })],
  ['schema/column-decimal', (k) => k.schema.alterTable('users', (t) => {
    t.decimal('foo', 5, 2);
  })],
  ['schema/column-boolean-default', (k) => k.schema.alterTable('users', (t) => {
    t.boolean('foo').defaultTo(false);
  })],
  ['schema/column-enum', (k) => k.schema.alterTable('users', (t) => {
    t.enum('foo', ['bar', 'baz']);
  })],
  ['schema/column-date', (k) => k.schema.alterTable('users', (t) => {
    t.date('foo');
  })],
  ['schema/column-datetime', (k) => k.schema.alterTable('users', (t) => {
    t.dateTime('foo');
  })],
  ['schema/column-time', (k) => k.schema.alterTable('users', (t) => {
    t.time('foo');
  })],
  ['schema/column-timestamp', (k) => k.schema.alterTable('users', (t) => {
    t.timestamp('foo');
  })],
  ['schema/column-timestamps-basic', (k) => k.schema.alterTable('users', (t) => {
    t.timestamps();
  })],
  ['schema/column-timestamps-defaults', (k) => k.schema.alterTable('users', (t) => {
    t.timestamps(false, true);
  })],
  ['schema/column-binary', (k) => k.schema.alterTable('users', (t) => {
    t.binary('foo');
  })],
  ['schema/column-jsonb', (k) => k.schema.alterTable('users', (t) => {
    t.jsonb('foo');
  })],
  ['schema/column-uuid', (k) => k.schema.alterTable('users', (t) => {
    t.uuid('foo');
  })],
  ['schema/column-json-default-notnull', (k) => k.schema.alterTable('users', (t) => {
    t.json('foo').defaultTo({}).notNullable();
  })],
  ['schema/column-specifictype-unique-notnull', (k) => k.schema.alterTable('users', (t) => {
    t.specificType('foo', 'CITEXT').unique().notNullable();
  })],

  // ── Mined from knex.js test/unit/schema-builder/postgres.js ──────────────
  // (schema DDL batch 6; also covers test/unit/schema-builder/cockroachdb.js
  // — that file's 5 tests all exercise dropUniqueIfExists/dropForeignIfExists/
  // dropPrimaryIfExists and uuid('id', {primaryKey: true}), none of which
  // knex-dart's TableBuilder/ColumnBuilder expose at all, so it contributed
  // zero mirrorable cases; don't re-walk it in a future pass). Cases limited
  // to shapes expressible with
  // knex-dart's current public API — many postgres.js tests exercise
  // options-object arguments (index predicates/storage engine types,
  // .checkPositive()/.checkIn()/etc, .inherits(), useNative enums,
  // deferrable(), IfExists constraint drops, uuid({primaryKey}),
  // increments({primaryKey: false}), mediumint/tinyint/smallint,
  // queryContext) that knex-dart's TableBuilder/ColumnBuilder simply have no
  // method for — real capability gaps, but scoped feature additions, not
  // parity fixes; left out of this harness (same reasoning as the
  // composite-foreign()/column .comment() notes above).

  // "refresh view concurrently"
  ['schema/view-refresh-materialized-concurrently', (k) =>
    k.schema.refreshMaterializedView('view_to_refresh', true)],

  // "drop table with schema" / "drop table if exists with schema"
  ['schema/drop-table-with-schema', (k) =>
    k.schema.withSchema('myschema').dropTable('users')],
  ['schema/drop-table-if-exists-with-schema', (k) =>
    k.schema.withSchema('myschema').dropTableIfExists('users')],

  // "drop index, with schema"
  ['schema/alter-table-drop-index-with-schema', (k) =>
    k.schema.withSchema('mySchema').alterTable('users', (t) => {
      t.dropIndex('foo');
    })],

  // "drop primary takes constraint name"
  ['schema/alter-table-drop-primary-named', (k) => k.schema.alterTable('users', (t) => {
    t.dropPrimary('testconstraintname');
  })],

  // "adding primary key" — bare single-string column, no constraint name
  // (distinct from the existing alter-table-primary-single-column case,
  // which always passes an explicit name).
  ['schema/alter-table-primary-single-column-unnamed', (k) => k.schema.alterTable('users', (t) => {
    t.primary('foo');
  })],

  // "adds foreign key with onUpdate and onDelete" — two FK columns in one
  // createTable, each with a SINGLE action (not both on the same column,
  // which the existing create-table-foreign-both-actions case already
  // covers) — exercises multiple deferred FK statements together, plus the
  // 'table.column' dotted references() shorthand on the first column.
  ['schema/create-table-foreign-mixed-actions', (k) => k.schema.createTable('person', (t) => {
    t.integer('user_id').notNullable().references('users.id').onDelete('SET NULL');
    t.integer('account_id').notNullable().references('id').inTable('accounts').onUpdate('cascade');
  })],

  // "set empty comment"
  ['schema/alter-table-comment-empty', (k) => k.schema.alterTable('user', (t) => {
    t.comment('');
  })],

  // "allows creating an extension" / IfNotExists / dropping / IfExists —
  // not yet in this corpus at all.
  ['schema/create-extension', (k) => k.schema.createExtension('test')],
  ['schema/create-extension-if-not-exists', (k) => k.schema.createExtensionIfNotExists('test')],
  ['schema/drop-extension', (k) => k.schema.dropExtension('test')],
  ['schema/drop-extension-if-exists', (k) => k.schema.dropExtensionIfExists('test')],

  // "alter with primary" > "liquid argument" / "liquid argument with name"
  // — fluent column.primary() inside alterTable (add column + a SEPARATE
  // deferred add-constraint statement), as opposed to createTable's inline/
  // single-statement form already covered by create-table-column-primary.
  ['schema/alter-table-add-column-primary-fluent', (k) => k.schema.alterTable('users', (t) => {
    t.string('test').primary();
  })],
  ['schema/alter-table-add-column-primary-fluent-named', (k) => k.schema.alterTable('users', (t) => {
    t.string('test').primary('testname');
  })],

  // "#1430" second part — fluent column.primary(name) inside createTable
  // (single inline statement), as opposed to the composite
  // TableBuilder.primary([...], name) form already covered by
  // create-table-primary-named.
  ['schema/create-table-primary-fluent-named', (k) => k.schema.createTable('users', (t) => {
    t.string('test').primary('testconstraintname');
  })],
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
