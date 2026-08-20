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

SchemaBuilder _sb(String dialect) =>
    KnexQuery.forClient(dialect).schemaBuilder();

typedef SchemaParityCase = List<Map<String, dynamic>> Function(String dialect);

final Map<String, SchemaParityCase> schemaParityCases = {
  'schema/create-table-basic': (d) => _sb(d).createTable('users', (t) {
    t.increments('id');
    t.string('email');
    t.integer('age');
  }).toSQL(),

  'schema/create-table-primary-composite': (d) =>
      _sb(d).createTable('memberships', (t) {
        t.integer('user_id');
        t.integer('org_id');
        t.primary(['user_id', 'org_id']);
      }).toSQL(),

  'schema/create-table-primary-named': (d) =>
      _sb(d).createTable('memberships', (t) {
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

  'schema/create-table-foreign-column': (d) =>
      _sb(d).createTable('orders', (t) {
        t.increments('id');
        t.integer('user_id').references('id').inTable('users');
      }).toSQL(),

  'schema/create-table-foreign-fluent-cascade': (d) =>
      _sb(d).createTable('orders', (t) {
        t.increments('id');
        t.integer('user_id');
        t
            .foreign('user_id')
            .references('id')
            .inTable('users')
            .onDelete('cascade');
      }).toSQL(),

  'schema/create-table-foreign-onupdate': (d) => _sb(d).createTable('orders', (
    t,
  ) {
    t.increments('id');
    t.integer('user_id');
    t.foreign('user_id').references('id').inTable('users').onUpdate('cascade');
  }).toSQL(),

  'schema/create-table-foreign-both-actions': (d) =>
      _sb(d).createTable('orders', (t) {
        t.increments('id');
        t.integer('user_id');
        t
            .foreign('user_id')
            .references('id')
            .inTable('users')
            .onDelete('cascade')
            .onUpdate('set null');
      }).toSQL(),

  'schema/default-string-embedded-quote': (d) =>
      _sb(d).alterTable('users', (t) {
        t.string('nickname').defaultTo("single 'quoted' value");
      }).toSQL(),

  'schema/default-null': (d) => _sb(d).alterTable('users', (t) {
    t.string('nickname').defaultTo(null);
  }).toSQL(),

  'schema/default-string-not-null': (d) => _sb(d).alterTable('users', (t) {
    t.string('nickname', 100).notNullable().defaultTo('guest');
  }).toSQL(),

  'schema/default-raw-current-timestamp': (d) => _sb(d).alterTable('users', (
    t,
  ) {
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

  'schema/create-table-unique-composite-named': (d) =>
      _sb(d).createTable('memberships', (t) {
        t.integer('user_id');
        t.integer('org_id');
        t.unique(['user_id', 'org_id'], 'uq_membership');
      }).toSQL(),

  'schema/alter-table-add-unique-composite': (d) =>
      _sb(d).alterTable('memberships', (t) {
        t.unique(['user_id', 'org_id']);
      }).toSQL(),

  'schema/alter-table-add-index-composite': (d) =>
      _sb(d).alterTable('memberships', (t) {
        t.index(['user_id', 'org_id']);
      }).toSQL(),

  'schema/alter-table-add-column-foreign': (d) =>
      _sb(d).alterTable('orders', (t) {
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

  'schema/alter-table-drop-unique-named': (d) =>
      _sb(d).alterTable('users', (t) {
        t.dropUnique(['email'], 'uq_users_email');
      }).toSQL(),

  'schema/alter-table-drop-index': (d) => _sb(d).alterTable('users', (t) {
    t.dropIndex(['email']);
  }).toSQL(),

  'schema/alter-table-drop-index-named': (d) => _sb(d).alterTable('users', (t) {
    t.dropIndex(['email'], 'idx_users_email');
  }).toSQL(),

  'schema/alter-table-drop-primary': (d) =>
      _sb(d).alterTable('memberships', (t) {
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
  'schema/drop-table-if-exists': (d) =>
      _sb(d).dropTableIfExists('users').toSQL(),
  'schema/rename-table': (d) => _sb(d).renameTable('users', 'accounts').toSQL(),

  'schema/create-table-column-unsigned': (d) => _sb(d).createTable('t', (t) {
    t.integer('qty').unsigned();
  }).toSQL(),

  'schema/alter-table-column-unsigned': (d) => _sb(d).alterTable('t', (t) {
    t.integer('qty').unsigned();
  }).toSQL(),

  // ── Mined from knex.js test/unit/schema-builder/mysql.js ──────────────────
  'schema/create-table-like-basic': (d) =>
      _sb(d).createTableLike('users_like', 'users').toSQL(),
  'schema/create-table-like-with-columns': (d) =>
      _sb(d).createTableLike('users_like', 'users', (t) {
        t.text('add_col');
        t.integer('numeric_col');
      }).toSQL(),

  'schema/create-table-primary-composite-with-increments': (d) =>
      _sb(d).createTable('users', (t) {
        t.primary(['userId', 'name']);
        t.increments('userId');
        t.string('name');
      }).toSQL(),

  'schema/view-create-basic': (d) => _sb(d)
      .createView(
        'adults',
        KnexQuery.forClient(
          d,
        ).from('users').select(['name']).where('age', '>', '18'),
      )
      .toSQL(),
  'schema/view-create-or-replace': (d) => _sb(d)
      .createViewOrReplace(
        'adults',
        KnexQuery.forClient(
          d,
        ).from('users').select(['name']).where('age', '>', '18'),
      )
      .toSQL(),
  'schema/view-drop': (d) => _sb(d).dropView('users').toSQL(),
  'schema/view-drop-with-schema': (d) =>
      _sb(d).withSchema('myschema').dropView('users').toSQL(),
  'schema/view-rename': (d) =>
      _sb(d).renameView('old_view', 'new_view').toSQL(),
  'schema/view-create-materialized': (d) => _sb(d)
      .createMaterializedView(
        'mat_view',
        KnexQuery.forClient(
          d,
        ).from('users').select(['name']).where('age', '>', '18'),
      )
      .toSQL(),
  'schema/view-refresh-materialized': (d) =>
      _sb(d).refreshMaterializedView('view_to_refresh').toSQL(),

  'schema/alter-table-add-json': (d) => _sb(d).alterTable('user', (t) {
    t.json('preferences');
  }).toSQL(),
  'schema/alter-table-add-jsonb': (d) => _sb(d).alterTable('user', (t) {
    t.jsonb('preferences');
  }).toSQL(),

  'schema/alter-table-drop-columns-multiple': (d) =>
      _sb(d).alterTable('users', (t) {
        t.dropColumns(['foo', 'bar']);
      }).toSQL(),

  'schema/alter-table-drop-unique-null-columns-named': (d) =>
      _sb(d).alterTable('users', (t) {
        t.dropUnique(null, 'foo');
      }).toSQL(),
  'schema/alter-table-drop-index-null-columns-named': (d) =>
      _sb(d).alterTable('users', (t) {
        t.dropIndex(null, 'foo');
      }).toSQL(),
  'schema/alter-table-drop-foreign-null-columns-named': (d) =>
      _sb(d).alterTable('users', (t) {
        t.dropForeign(null, 'foo');
      }).toSQL(),

  'schema/alter-table-drop-timestamps': (d) => _sb(d).alterTable('users', (t) {
    t.dropTimestamps();
  }).toSQL(),

  'schema/alter-table-primary-single-column': (d) =>
      _sb(d).alterTable('users', (t) {
        t.primary('foo', 'bar');
      }).toSQL(),
  'schema/alter-table-unique-single-column': (d) =>
      _sb(d).alterTable('users', (t) {
        t.unique('foo', 'bar');
      }).toSQL(),

  'schema/alter-table-primary-named': (d) => _sb(d).alterTable('users', (t) {
    t.primary(['test1', 'test2'], 'testconstraintname');
  }).toSQL(),

  'schema/alter-table-add-increments': (d) => _sb(d).alterTable('users', (t) {
    t.increments('id');
  }).toSQL(),
  'schema/alter-table-add-bigincrements': (d) =>
      _sb(d).alterTable('users', (t) {
        t.bigIncrements('id');
      }).toSQL(),

  'schema/alter-table-add-text': (d) => _sb(d).alterTable('users', (t) {
    t.text('foo');
  }).toSQL(),
  'schema/alter-table-add-biginteger': (d) => _sb(d).alterTable('users', (t) {
    t.bigInteger('foo');
  }).toSQL(),
  'schema/alter-table-add-boolean': (d) => _sb(d).alterTable('users', (t) {
    t.boolean('foo');
  }).toSQL(),
  'schema/alter-table-add-enum': (d) => _sb(d).alterTable('users', (t) {
    t.enu('foo', ['bar', 'baz']);
  }).toSQL(),
  'schema/alter-table-add-date': (d) => _sb(d).alterTable('users', (t) {
    t.date('foo');
  }).toSQL(),
  'schema/alter-table-add-datetime': (d) => _sb(d).alterTable('users', (t) {
    t.datetime('foo');
  }).toSQL(),
  'schema/alter-table-add-time': (d) => _sb(d).alterTable('users', (t) {
    t.time('foo');
  }).toSQL(),
  'schema/alter-table-add-timestamp': (d) => _sb(d).alterTable('users', (t) {
    t.timestamp('foo');
  }).toSQL(),
  'schema/alter-table-add-timestamps': (d) => _sb(d).alterTable('users', (t) {
    t.timestamps();
  }).toSQL(),
  'schema/alter-table-add-binary': (d) => _sb(d).alterTable('users', (t) {
    t.binary('foo');
  }).toSQL(),
  'schema/alter-table-add-uuid': (d) => _sb(d).alterTable('users', (t) {
    t.uuid('foo');
  }).toSQL(),
  'schema/alter-table-add-decimal': (d) => _sb(d).alterTable('users', (t) {
    t.decimal('foo', 5, 2);
  }).toSQL(),
  'schema/alter-table-add-double': (d) => _sb(d).alterTable('users', (t) {
    t.doublePrecision('foo');
  }).toSQL(),

  'schema/create-table-default-raw-timestamp': (d) =>
      _sb(d).createTable('default_raw_test', (t) {
        t
            .timestamp('created_at')
            .defaultTo(_sb(d).client.raw('CURRENT_TIMESTAMP'));
      }).toSQL(),

  'schema/alter-table-drop-unique-composite': (d) =>
      _sb(d).alterTable('composite_key_test', (t) {
        t.dropUnique(['column_a', 'column_b']);
      }).toSQL(),

  'schema/alter-table-comment': (d) => _sb(d).alterTable('users', (t) {
    t.comment('Custom comment');
  }).toSQL(),
  'schema/create-table-comment': (d) => _sb(d).createTable('users', (t) {
    t.string('username');
    t.comment('Custom comment');
  }).toSQL(),

  // ── Mined from knex.js test/unit/schema-builder/redshift.js ──────────────
  // (schema DDL batch 4 — see tool/parity/README.md). Same ids/theming as
  // the mirror block in tool/parity/run_js_schema.mjs.

  // ── Column types (via alterTable, one column each) ────────────────────────
  'schema/column-increments': (d) => _sb(d).alterTable('users', (t) {
    t.increments('foo');
  }).toSQL(),
  'schema/column-bigincrements': (d) => _sb(d).alterTable('users', (t) {
    t.bigIncrements('foo');
  }).toSQL(),
  'schema/column-string-length': (d) => _sb(d).alterTable('users', (t) {
    t.string('foo', 100);
  }).toSQL(),
  'schema/column-string-default': (d) => _sb(d).alterTable('users', (t) {
    t.string('foo', 100).defaultTo('bar');
  }).toSQL(),
  'schema/column-text': (d) => _sb(d).alterTable('users', (t) {
    t.text('foo');
  }).toSQL(),
  'schema/column-biginteger': (d) => _sb(d).alterTable('users', (t) {
    t.bigInteger('foo');
  }).toSQL(),
  'schema/column-integer': (d) => _sb(d).alterTable('users', (t) {
    t.integer('foo');
  }).toSQL(),
  'schema/column-float': (d) => _sb(d).alterTable('users', (t) {
    t.float('foo');
  }).toSQL(),
  'schema/column-double': (d) => _sb(d).alterTable('users', (t) {
    t.doublePrecision('foo');
  }).toSQL(),
  'schema/column-decimal': (d) => _sb(d).alterTable('users', (t) {
    t.decimal('foo', 5, 2);
  }).toSQL(),
  'schema/column-boolean-default': (d) => _sb(d).alterTable('users', (t) {
    t.boolean('foo').defaultTo(false);
  }).toSQL(),
  'schema/column-enum': (d) => _sb(d).alterTable('users', (t) {
    t.enu('foo', ['bar', 'baz']);
  }).toSQL(),
  'schema/column-date': (d) => _sb(d).alterTable('users', (t) {
    t.date('foo');
  }).toSQL(),
  'schema/column-datetime': (d) => _sb(d).alterTable('users', (t) {
    t.datetime('foo');
  }).toSQL(),
  'schema/column-time': (d) => _sb(d).alterTable('users', (t) {
    t.time('foo');
  }).toSQL(),
  'schema/column-timestamp': (d) => _sb(d).alterTable('users', (t) {
    t.timestamp('foo');
  }).toSQL(),
  'schema/column-timestamps-basic': (d) => _sb(d).alterTable('users', (t) {
    t.timestamps();
  }).toSQL(),
  'schema/column-timestamps-defaults': (d) => _sb(d).alterTable('users', (t) {
    t.timestamps(false, true);
  }).toSQL(),
  'schema/column-binary': (d) => _sb(d).alterTable('users', (t) {
    t.binary('foo');
  }).toSQL(),
  'schema/column-jsonb': (d) => _sb(d).alterTable('users', (t) {
    t.jsonb('foo');
  }).toSQL(),
  'schema/column-uuid': (d) => _sb(d).alterTable('users', (t) {
    t.uuid('foo');
  }).toSQL(),
  'schema/column-json-default-notnull': (d) => _sb(d).alterTable('users', (t) {
    t.json('foo').defaultTo(<String, dynamic>{}).notNullable();
  }).toSQL(),
  'schema/column-specifictype-unique-notnull': (d) =>
      _sb(d).alterTable('users', (t) {
        t.specificType('foo', 'CITEXT').unique().notNullable();
      }).toSQL(),

  // ── Mined from knex.js test/unit/schema-builder/postgres.js ──────────────
  // (schema DDL batch 6). Same ids/theming as the mirror block in
  // tool/parity/run_js_schema.mjs.
  'schema/view-refresh-materialized-concurrently': (d) =>
      _sb(d).refreshMaterializedView('view_to_refresh', true).toSQL(),

  'schema/drop-table-with-schema': (d) =>
      _sb(d).withSchema('myschema').dropTable('users').toSQL(),
  'schema/drop-table-if-exists-with-schema': (d) =>
      _sb(d).withSchema('myschema').dropTableIfExists('users').toSQL(),

  'schema/alter-table-drop-index-with-schema': (d) =>
      _sb(d).withSchema('mySchema').alterTable('users', (t) {
        t.dropIndex('foo');
      }).toSQL(),

  'schema/alter-table-drop-primary-named': (d) =>
      _sb(d).alterTable('users', (t) {
        t.dropPrimary('testconstraintname');
      }).toSQL(),

  'schema/alter-table-primary-single-column-unnamed': (d) =>
      _sb(d).alterTable('users', (t) {
        t.primary('foo');
      }).toSQL(),

  'schema/create-table-foreign-mixed-actions': (d) =>
      _sb(d).createTable('person', (t) {
        t
            .integer('user_id')
            .notNullable()
            .references('users.id')
            .onDelete('SET NULL');
        t
            .integer('account_id')
            .notNullable()
            .references('id')
            .inTable('accounts')
            .onUpdate('cascade');
      }).toSQL(),

  'schema/alter-table-comment-empty': (d) => _sb(d).alterTable('user', (t) {
    t.comment('');
  }).toSQL(),

  'schema/create-extension': (d) => _sb(d).createExtension('test').toSQL(),
  'schema/create-extension-if-not-exists': (d) =>
      _sb(d).createExtensionIfNotExists('test').toSQL(),
  'schema/drop-extension': (d) => _sb(d).dropExtension('test').toSQL(),
  'schema/drop-extension-if-exists': (d) =>
      _sb(d).dropExtensionIfExists('test').toSQL(),

  'schema/alter-table-add-column-primary-fluent': (d) =>
      _sb(d).alterTable('users', (t) {
        t.string('test').primary();
      }).toSQL(),
  'schema/alter-table-add-column-primary-fluent-named': (d) =>
      _sb(d).alterTable('users', (t) {
        t.string('test').primary(constraintName: 'testname');
      }).toSQL(),

  'schema/create-table-primary-fluent-named': (d) =>
      _sb(d).createTable('users', (t) {
        t.string('test').primary(constraintName: 'testconstraintname');
      }).toSQL(),

  // Batch 6 — column-type dialect-dispatch + views + createTableLike +
  // createTableIfNotExists + dropColumns-multi. Mirrors run_js_schema.mjs
  // 1:1 by id. Dart's column-type dispatch goes through column_builder.dart's
  // `toSQL()`; views go through schema_compiler.dart's per-method dispatchers.

  // ── Column types (dialect-dispatch territory) ────────────────────────
  'schema/column-boolean': (d) => _sb(d).alterTable('users', (t) {
    t.boolean('enabled').defaultTo(false);
  }).toSQL(),
  'schema/column-uuid-bare': (d) => _sb(d).alterTable('users', (t) {
    t.uuid('external_id');
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
  'schema/create-view-bare': (d) => _sb(d)
      .createView(
        'active_users',
        KnexQuery.forClient(
          d,
        ).queryBuilder().table('users').select(['*']).where('active', true),
      )
      .toSQL(),
  'schema/create-view-or-replace': (d) => _sb(d)
      .createViewOrReplace(
        'active_users',
        KnexQuery.forClient(
          d,
        ).queryBuilder().table('users').select(['*']).where('active', true),
      )
      .toSQL(),
  'schema/drop-view': (d) => _sb(d).dropView('active_users').toSQL(),
  'schema/drop-view-if-exists': (d) =>
      _sb(d).dropViewIfExists('active_users').toSQL(),
  'schema/rename-view': (d) =>
      _sb(d).renameView('active_users', 'all_active_users').toSQL(),
  'schema/create-materialized-view': (d) => _sb(d)
      .createMaterializedView(
        'active_users_mv',
        KnexQuery.forClient(
          d,
        ).queryBuilder().table('users').select(['*']).where('active', true),
      )
      .toSQL(),
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

  // ── Batch 7: schema raw + pg-only materialized-view drops ────────────
  'schema/raw-with-binding': (d) =>
      _sb(d).raw('select ? as value', [1]).toSQL(),
  'schema/drop-materialized-view': (d) =>
      _sb(d).dropMaterializedView('active_users_mv').toSQL(),
  'schema/drop-materialized-view-if-exists': (d) =>
      _sb(d).dropMaterializedViewIfExists('active_users_mv').toSQL(),

  // ── Batch 8: pg-only CREATE/DROP SCHEMA family ────────────────────────
  'schema/create-schema': (d) => _sb(d).createSchema('billing').toSQL(),
  'schema/create-schema-if-not-exists': (d) =>
      _sb(d).createSchemaIfNotExists('billing').toSQL(),
  'schema/drop-schema': (d) => _sb(d).dropSchema('billing').toSQL(),
  'schema/drop-schema-cascade': (d) =>
      _sb(d).dropSchema('billing', true).toSQL(),
  'schema/drop-schema-if-exists': (d) =>
      _sb(d).dropSchemaIfExists('billing').toSQL(),
  'schema/drop-schema-if-exists-cascade': (d) =>
      _sb(d).dropSchemaIfExists('billing', true).toSQL(),
};
