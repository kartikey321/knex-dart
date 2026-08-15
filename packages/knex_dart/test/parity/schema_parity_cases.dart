/// Dialect-agnostic schema DDL corpus for the differential parity harness.
///
/// Sibling to parity_cases.dart (query builder). Split out because schema
/// DDL's `.toSQL()` returns a LIST of statements (not one) on both sides —
/// see schema_parity_test.dart for the comparison shape.
///
/// Each entry mirrors — by the SAME id — a builder in
/// `tool/parity/run_js_schema.mjs`. To add coverage, add a case here AND
/// there under the same id, then regenerate the fixture.
library;

import 'package:knex_dart/knex_dart.dart';

SchemaBuilder _sb(String dialect) => KnexQuery.forClient(dialect).schemaBuilder();

typedef SchemaParityCase = List<Map<String, dynamic>> Function(String dialect);

final Map<String, SchemaParityCase> schemaParityCases = {
  'schema/create-table-basic': (d) => _sb(d).createTable('users', (t) {
        t.increments('id');
        t.string('email');
        t.integer('age');
      }).toSQL(),

  'schema/create-table-primary-composite': (d) => _sb(d).createTable('memberships', (t) {
        t.integer('user_id');
        t.integer('org_id');
        t.primary(['user_id', 'org_id']);
      }).toSQL(),

  'schema/create-table-primary-named': (d) => _sb(d).createTable('memberships', (t) {
        t.integer('user_id');
        t.integer('org_id');
        t.primary(['user_id', 'org_id'], 'membership_pk');
      }).toSQL(),

  'schema/create-table-unique-column': (d) => _sb(d).createTable('users', (t) {
        t.increments('id');
        t.string('email').unique();
      }).toSQL(),

  'schema/create-table-unique-named': (d) => _sb(d).createTable('users', (t) {
        t.increments('id');
        t.string('email');
        t.unique(['email'], 'uq_users_email');
      }).toSQL(),

  'schema/create-table-foreign-column': (d) => _sb(d).createTable('orders', (t) {
        t.increments('id');
        t.integer('user_id').references('id').inTable('users');
      }).toSQL(),

  'schema/create-table-foreign-fluent-cascade': (d) => _sb(d).createTable('orders', (t) {
        t.increments('id');
        t.integer('user_id');
        t.foreign('user_id').references('id').inTable('users').onDelete('cascade');
      }).toSQL(),

  'schema/create-table-foreign-onupdate': (d) => _sb(d).createTable('orders', (t) {
        t.increments('id');
        t.integer('user_id');
        t.foreign('user_id').references('id').inTable('users').onUpdate('cascade');
      }).toSQL(),

  'schema/create-table-foreign-both-actions': (d) => _sb(d).createTable('orders', (t) {
        t.increments('id');
        t.integer('user_id');
        t.foreign('user_id')
            .references('id')
            .inTable('users')
            .onDelete('cascade')
            .onUpdate('set null');
      }).toSQL(),

  'schema/default-string-embedded-quote': (d) => _sb(d).alterTable('users', (t) {
        t.string('nickname').defaultTo("single 'quoted' value");
      }).toSQL(),

  'schema/default-null': (d) => _sb(d).alterTable('users', (t) {
        t.string('nickname').defaultTo(null);
      }).toSQL(),

  'schema/default-string-not-null': (d) => _sb(d).alterTable('users', (t) {
        t.string('nickname', 100).notNullable().defaultTo('guest');
      }).toSQL(),

  'schema/default-raw-current-timestamp': (d) => _sb(d).alterTable('users', (t) {
        t.timestamp('created_at').defaultTo(_sb(d).client.raw('CURRENT_TIMESTAMP'));
      }).toSQL(),

  'schema/default-boolean-false': (d) => _sb(d).alterTable('users', (t) {
        t.boolean('enabled').defaultTo(false);
      }).toSQL(),

  'schema/default-json-object': (d) => _sb(d).alterTable('users', (t) {
        t.json('preferences').defaultTo({}).notNullable();
      }).toSQL(),

  'schema/default-jsonb-object': (d) => _sb(d).alterTable('users', (t) {
        t.jsonb('preferences').defaultTo({}).notNullable();
      }).toSQL(),

  'schema/create-table-column-primary': (d) => _sb(d).createTable('users', (t) {
        t.string('external_id').primary();
      }).toSQL(),

  'schema/create-table-unique-composite-named': (d) => _sb(d).createTable('memberships', (t) {
        t.integer('user_id');
        t.integer('org_id');
        t.unique(['user_id', 'org_id'], 'uq_membership');
      }).toSQL(),

  'schema/alter-table-add-unique-composite': (d) => _sb(d).alterTable('memberships', (t) {
        t.unique(['user_id', 'org_id']);
      }).toSQL(),

  'schema/alter-table-add-index-composite': (d) => _sb(d).alterTable('memberships', (t) {
        t.index(['user_id', 'org_id']);
      }).toSQL(),

  'schema/alter-table-add-column-foreign': (d) => _sb(d).alterTable('orders', (t) {
        t.integer('user_id').references('id').inTable('users');
      }).toSQL(),

  'schema/alter-table-add-column': (d) => _sb(d).alterTable('users', (t) {
        t.string('nickname');
      }).toSQL(),

  'schema/alter-table-drop-column': (d) => _sb(d).alterTable('users', (t) {
        t.dropColumn('nickname');
      }).toSQL(),

  'schema/alter-table-rename-column': (d) => _sb(d).alterTable('users', (t) {
        t.renameColumn('nickname', 'nick');
      }).toSQL(),

  'schema/alter-table-add-unique': (d) => _sb(d).alterTable('users', (t) {
        t.unique(['email']);
      }).toSQL(),

  'schema/alter-table-add-unique-named': (d) => _sb(d).alterTable('users', (t) {
        t.unique(['email'], 'uq_users_email');
      }).toSQL(),

  'schema/alter-table-add-index': (d) => _sb(d).alterTable('users', (t) {
        t.index(['email']);
      }).toSQL(),

  'schema/alter-table-add-index-named': (d) => _sb(d).alterTable('users', (t) {
        t.index(['email'], 'idx_users_email');
      }).toSQL(),

  'schema/alter-table-drop-unique': (d) => _sb(d).alterTable('users', (t) {
        t.dropUnique(['email']);
      }).toSQL(),

  'schema/alter-table-drop-unique-named': (d) => _sb(d).alterTable('users', (t) {
        t.dropUnique(['email'], 'uq_users_email');
      }).toSQL(),

  'schema/alter-table-drop-index': (d) => _sb(d).alterTable('users', (t) {
        t.dropIndex(['email']);
      }).toSQL(),

  'schema/alter-table-drop-index-named': (d) => _sb(d).alterTable('users', (t) {
        t.dropIndex(['email'], 'idx_users_email');
      }).toSQL(),

  'schema/alter-table-drop-primary': (d) => _sb(d).alterTable('memberships', (t) {
        t.dropPrimary();
      }).toSQL(),

  'schema/alter-table-drop-foreign': (d) => _sb(d).alterTable('orders', (t) {
        t.dropForeign(['user_id']);
      }).toSQL(),

  'schema/alter-table-primary': (d) => _sb(d).alterTable('memberships', (t) {
        t.primary(['user_id', 'org_id']);
      }).toSQL(),

  'schema/alter-table-foreign': (d) => _sb(d).alterTable('orders', (t) {
        t.foreign('user_id').references('id').inTable('users');
      }).toSQL(),

  'schema/alter-table-set-nullable': (d) => _sb(d).alterTable('users', (t) {
        t.setNullable('email');
      }).toSQL(),

  'schema/alter-table-drop-nullable': (d) => _sb(d).alterTable('users', (t) {
        t.dropNullable('email');
      }).toSQL(),

  'schema/drop-table': (d) => _sb(d).dropTable('users').toSQL(),
  'schema/drop-table-if-exists': (d) => _sb(d).dropTableIfExists('users').toSQL(),
  'schema/rename-table': (d) => _sb(d).renameTable('users', 'accounts').toSQL(),

  'schema/create-table-column-unsigned': (d) => _sb(d).createTable('t', (t) {
        t.integer('qty').unsigned();
      }).toSQL(),

  'schema/alter-table-column-unsigned': (d) => _sb(d).alterTable('t', (t) {
        t.integer('qty').unsigned();
      }).toSQL(),

  // Batch 6 — column-type dialect-dispatch + views + createTableLike +
  // createTableIfNotExists + dropColumns-multi. Mirrors run_js_schema.mjs
  // 1:1 by id. Dart's column-type dispatch goes through column_builder.dart's
  // `toSQL()`; views go through schema_compiler.dart's per-method dispatchers.

  // ── Column types (dialect-dispatch territory) ────────────────────────
  'schema/column-boolean': (d) => _sb(d).alterTable('users', (t) {
        t.boolean('enabled').defaultTo(false);
      }).toSQL(),
  // dart's float(column) takes only a column name; precision/scale
  // unsupported (knex.js accepts them positionally, ignores them on most
  // backends). Mirror faithfully — both sides emit a plain float, no
  // precision/scale.
  'schema/column-float': (d) => _sb(d).alterTable('users', (t) {
        t.float('score');
      }).toSQL(),
  'schema/column-binary': (d) => _sb(d).alterTable('users', (t) {
        t.binary('avatar');
      }).toSQL(),
  'schema/column-uuid-bare': (d) => _sb(d).alterTable('users', (t) {
        t.uuid('external_id');
      }).toSQL(),
  // knex-dart's ColumnBuilder has `enu` (no `enum` alias). Both call the
  // same underlying dispatch.
  'schema/column-enum': (d) => _sb(d).alterTable('users', (t) {
        t.enu('role', ['admin', 'user', 'guest']);
      }).toSQL(),
  'schema/column-enu': (d) => _sb(d).alterTable('users', (t) {
        t.enu('status', ['active', 'idle']);
      }).toSQL(),
  'schema/column-bigInteger': (d) => _sb(d).alterTable('users', (t) {
        t.bigInteger('big_count');
      }).toSQL(),
  'schema/column-bigIncrements': (d) => _sb(d).alterTable('users', (t) {
        t.bigIncrements('audit_id');
      }).toSQL(),

  // ── Views cluster ────────────────────────────────────────────────────
  'schema/create-view-bare': (d) => _sb(d).createView(
        'active_users',
        KnexQuery.forClient(d).queryBuilder().table('users').select(['*']).where('active', true),
      ).toSQL(),
  'schema/create-view-or-replace': (d) => _sb(d).createViewOrReplace(
        'active_users',
        KnexQuery.forClient(d).queryBuilder().table('users').select(['*']).where('active', true),
      ).toSQL(),
  'schema/drop-view': (d) => _sb(d).dropView('active_users').toSQL(),
  'schema/drop-view-if-exists': (d) =>
      _sb(d).dropViewIfExists('active_users').toSQL(),
  'schema/rename-view': (d) =>
      _sb(d).renameView('active_users', 'all_active_users').toSQL(),
  'schema/create-materialized-view': (d) => _sb(d).createMaterializedView(
        'active_users_mv',
        KnexQuery.forClient(d).queryBuilder().table('users').select(['*']).where('active', true),
      ).toSQL(),
  'schema/refresh-materialized-view': (d) =>
      _sb(d).refreshMaterializedView('active_users_mv').toSQL(),
  'schema/refresh-materialized-view-concurrently': (d) =>
      _sb(d).refreshMaterializedView('active_users_mv', true).toSQL(),

  // ── createTableIfNotExists, createTableLike, dropColumns-multi ────────
  'schema/create-table-if-not-exists': (d) =>
      _sb(d).createTableIfNotExists('users', (t) {
        t.increments('id');
        t.string('email');
      }).toSQL(),
  'schema/create-table-like': (d) =>
      _sb(d).createTableLike('users_copy', 'users').toSQL(),
  'schema/alter-table-drop-columns-multi': (d) =>
      _sb(d).alterTable('users', (t) {
        t.dropColumns(['nickname', 'avatar']);
      }).toSQL(),
};
