/// Dialect-agnostic schema DDL corpus, shared by knex_dart's differential
/// parity harness (`schema_parity_test.dart`) and knex_dart_live_test's
/// live-execution framework.
///
/// Sibling to query_cases.dart. Split out because schema DDL's `.toSQL()`
/// returns a LIST of statements (not one) on both sides — see
/// `schema_parity_test.dart` for the comparison shape. Each entry returns
/// the [SchemaBuilder] itself (not compiled statements) — the parity
/// harness calls `.toSQL()` on it for text comparison; the live-execution
/// runner executes it directly (e.g. via a driver's `executeSchema()`).
///
/// Each entry mirrors — by the SAME id — a builder in
/// `tool/parity/run_js_schema.mjs`. To add coverage, add a case here AND
/// there under the same id, then regenerate the fixture.
library;

import 'package:knex_dart/knex_dart.dart';

SchemaBuilder _sb(String dialect) =>
    KnexQuery.forClient(dialect).schemaBuilder();

Raw _raw(String dialect, String sql, [dynamic bindings]) =>
    _sb(dialect).client.raw(sql, bindings);

/// The schema DDL corpus, keyed by stable id (matching the pre-reshape
/// `schemaParityCases` map shape). Unlike the query corpus, there is no
/// single "expected method" concept to validate here — `createTable`,
/// `alterTable`, `dropTable`, etc. are structurally distinct builder
/// methods, not a shared mutable method flag that could silently drift.
final Map<String, SchemaBuilder Function(String dialect)> schemaCorpusCases = {
  'schema/create-table-basic': (d) => _sb(d).createTable('users', (t) {
    t.increments('id');
    t.string('email');
    t.integer('age');
  }),

  'schema/create-table-primary-composite': (d) =>
      _sb(d).createTable('memberships', (t) {
        t.integer('user_id');
        t.integer('org_id');
        t.primary(['user_id', 'org_id']);
      }),

  'schema/create-table-primary-named': (d) =>
      _sb(d).createTable('memberships', (t) {
        t.integer('user_id');
        t.integer('org_id');
        t.primary(['user_id', 'org_id'], 'membership_pk');
      }),

  'schema/create-table-unique-column': (d) => _sb(d).createTable('users', (t) {
    t.increments('id');
    t.string('email').unique();
  }),

  'schema/create-table-unique-named': (d) => _sb(d).createTable('users', (t) {
    t.increments('id');
    t.string('email');
    t.unique(['email'], 'uq_users_email');
  }),

  'schema/create-table-foreign-column': (d) =>
      _sb(d).createTable('orders', (t) {
        t.increments('id');
        t.integer('user_id').references('id').inTable('users');
      }),

  'schema/create-table-foreign-fluent-cascade': (d) =>
      _sb(d).createTable('orders', (t) {
        t.increments('id');
        t.integer('user_id');
        t
            .foreign('user_id')
            .references('id')
            .inTable('users')
            .onDelete('cascade');
      }),

  'schema/create-table-foreign-onupdate': (d) => _sb(d).createTable('orders', (
    t,
  ) {
    t.increments('id');
    t.integer('user_id');
    t.foreign('user_id').references('id').inTable('users').onUpdate('cascade');
  }),

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
      }),

  'schema/default-string-embedded-quote': (d) =>
      _sb(d).alterTable('users', (t) {
        t.string('nickname').defaultTo("single 'quoted' value");
      }),

  'schema/default-null': (d) => _sb(d).alterTable('users', (t) {
    t.string('nickname').defaultTo(null);
  }),

  'schema/default-string-not-null': (d) => _sb(d).alterTable('users', (t) {
    t.string('nickname', 100).notNullable().defaultTo('guest');
  }),

  'schema/default-raw-current-timestamp': (d) => _sb(d).alterTable('users', (
    t,
  ) {
    t.timestamp('created_at').defaultTo(_raw(d, 'CURRENT_TIMESTAMP'));
  }),

  'schema/default-boolean-false': (d) => _sb(d).alterTable('users', (t) {
    t.boolean('enabled').defaultTo(false);
  }),

  'schema/default-json-object': (d) => _sb(d).alterTable('users', (t) {
    t.json('preferences').defaultTo({}).notNullable();
  }),

  'schema/default-jsonb-object': (d) => _sb(d).alterTable('users', (t) {
    t.jsonb('preferences').defaultTo({}).notNullable();
  }),

  'schema/create-table-column-primary': (d) => _sb(d).createTable('users', (t) {
    t.string('external_id').primary();
  }),

  'schema/create-table-unique-composite-named': (d) =>
      _sb(d).createTable('memberships', (t) {
        t.integer('user_id');
        t.integer('org_id');
        t.unique(['user_id', 'org_id'], 'uq_membership');
      }),

  'schema/alter-table-add-unique-composite': (d) =>
      _sb(d).alterTable('memberships', (t) {
        t.unique(['user_id', 'org_id']);
      }),

  'schema/alter-table-add-index-composite': (d) =>
      _sb(d).alterTable('memberships', (t) {
        t.index(['user_id', 'org_id']);
      }),

  'schema/alter-table-add-column-foreign': (d) =>
      _sb(d).alterTable('orders', (t) {
        t.integer('user_id').references('id').inTable('users');
      }),

  'schema/alter-table-add-column': (d) => _sb(d).alterTable('users', (t) {
    t.string('nickname');
  }),

  'schema/alter-table-drop-column': (d) => _sb(d).alterTable('users', (t) {
    t.dropColumn('nickname');
  }),

  'schema/alter-table-rename-column': (d) => _sb(d).alterTable('users', (t) {
    t.renameColumn('nickname', 'nick');
  }),

  'schema/alter-table-add-unique': (d) => _sb(d).alterTable('users', (t) {
    t.unique(['email']);
  }),

  'schema/alter-table-add-unique-named': (d) => _sb(d).alterTable('users', (t) {
    t.unique(['email'], 'uq_users_email');
  }),

  'schema/alter-table-add-index': (d) => _sb(d).alterTable('users', (t) {
    t.index(['email']);
  }),

  'schema/alter-table-add-index-named': (d) => _sb(d).alterTable('users', (t) {
    t.index(['email'], 'idx_users_email');
  }),

  'schema/alter-table-drop-unique': (d) => _sb(d).alterTable('users', (t) {
    t.dropUnique(['email']);
  }),

  'schema/alter-table-drop-unique-named': (d) =>
      _sb(d).alterTable('users', (t) {
        t.dropUnique(['email'], 'uq_users_email');
      }),

  'schema/alter-table-drop-index': (d) => _sb(d).alterTable('users', (t) {
    t.dropIndex(['email']);
  }),

  'schema/alter-table-drop-index-named': (d) => _sb(d).alterTable('users', (t) {
    t.dropIndex(['email'], 'idx_users_email');
  }),

  'schema/alter-table-drop-primary': (d) =>
      _sb(d).alterTable('memberships', (t) {
        t.dropPrimary();
      }),

  'schema/alter-table-drop-foreign': (d) => _sb(d).alterTable('orders', (t) {
    t.dropForeign(['user_id']);
  }),

  'schema/alter-table-primary': (d) => _sb(d).alterTable('memberships', (t) {
    t.primary(['user_id', 'org_id']);
  }),

  'schema/alter-table-foreign': (d) => _sb(d).alterTable('orders', (t) {
    t.foreign('user_id').references('id').inTable('users');
  }),
  'schema/alter-table-foreign-both-actions': (d) =>
      _sb(d).alterTable('orders', (t) {
        t
            .foreign('user_id')
            .references('id')
            .inTable('users')
            .onDelete('cascade')
            .onUpdate('cascade');
      }),

  'schema/alter-table-set-nullable': (d) => _sb(d).alterTable('users', (t) {
    t.setNullable('email');
  }),

  'schema/alter-table-drop-nullable': (d) => _sb(d).alterTable('users', (t) {
    t.dropNullable('email');
  }),

  'schema/drop-table': (d) => _sb(d).dropTable('users'),
  'schema/drop-table-if-exists': (d) =>
      _sb(d).dropTableIfExists('users'),
  'schema/rename-table': (d) => _sb(d).renameTable('users', 'accounts'),

  'schema/create-table-column-unsigned': (d) => _sb(d).createTable('t', (t) {
    t.integer('qty').unsigned();
  }),

  'schema/alter-table-column-unsigned': (d) => _sb(d).alterTable('t', (t) {
    t.integer('qty').unsigned();
  }),

  // ── Mined from knex.js test/unit/schema-builder/mysql.js ──────────────────
  'schema/create-table-like-basic': (d) =>
      _sb(d).createTableLike('users_like', 'users'),
  'schema/create-table-like-with-columns': (d) =>
      _sb(d).createTableLike('users_like', 'users', (t) {
        t.text('add_col');
        t.integer('numeric_col');
      }),

  'schema/create-table-primary-composite-with-increments': (d) =>
      _sb(d).createTable('users', (t) {
        t.primary(['userId', 'name']);
        t.increments('userId');
        t.string('name');
      }),

  'schema/view-create-basic': (d) => _sb(d)
      .createView(
        'adults',
        KnexQuery.forClient(
          d,
        ).from('users').select(['name']).where('age', '>', '18'),
      )
      ,
  'schema/view-create-raw': (d) => _sb(d)
      .createView('answer_view', _raw(d, 'select ? as answer', [42]))
      ,
  'schema/view-create-or-replace-raw': (d) => _sb(d)
      .createViewOrReplace(
        'answer_view',
        _raw(d, 'select ? as answer', [42]),
      )
      ,
  'schema/view-create-or-replace': (d) => _sb(d)
      .createViewOrReplace(
        'adults',
        KnexQuery.forClient(
          d,
        ).from('users').select(['name']).where('age', '>', '18'),
      )
      ,
  'schema/view-drop': (d) => _sb(d).dropView('users'),
  'schema/view-drop-with-schema': (d) =>
      _sb(d).withSchema('myschema').dropView('users'),
  'schema/view-rename': (d) =>
      _sb(d).renameView('old_view', 'new_view'),
  'schema/view-create-materialized': (d) => _sb(d)
      .createMaterializedView(
        'mat_view',
        KnexQuery.forClient(
          d,
        ).from('users').select(['name']).where('age', '>', '18'),
      )
      ,
  'schema/view-create-materialized-raw': (d) => _sb(d)
      .createMaterializedView(
        'answer_view',
        _raw(d, 'select ? as answer', [42]),
      )
      ,
  'schema/view-refresh-materialized': (d) =>
      _sb(d).refreshMaterializedView('view_to_refresh'),

  'schema/alter-table-add-json': (d) => _sb(d).alterTable('user', (t) {
    t.json('preferences');
  }),
  'schema/alter-table-add-jsonb': (d) => _sb(d).alterTable('user', (t) {
    t.jsonb('preferences');
  }),

  'schema/alter-table-drop-columns-multiple': (d) =>
      _sb(d).alterTable('users', (t) {
        t.dropColumns(['foo', 'bar']);
      }),

  'schema/alter-table-drop-unique-null-columns-named': (d) =>
      _sb(d).alterTable('users', (t) {
        t.dropUnique(null, 'foo');
      }),
  'schema/alter-table-drop-index-null-columns-named': (d) =>
      _sb(d).alterTable('users', (t) {
        t.dropIndex(null, 'foo');
      }),
  'schema/alter-table-drop-foreign-null-columns-named': (d) =>
      _sb(d).alterTable('users', (t) {
        t.dropForeign(null, 'foo');
      }),

  'schema/alter-table-drop-timestamps': (d) => _sb(d).alterTable('users', (t) {
    t.dropTimestamps();
  }),

  'schema/alter-table-primary-single-column': (d) =>
      _sb(d).alterTable('users', (t) {
        t.primary('foo', 'bar');
      }),
  'schema/alter-table-unique-single-column': (d) =>
      _sb(d).alterTable('users', (t) {
        t.unique('foo', 'bar');
      }),

  'schema/alter-table-primary-named': (d) => _sb(d).alterTable('users', (t) {
    t.primary(['test1', 'test2'], 'testconstraintname');
  }),

  'schema/alter-table-add-increments': (d) => _sb(d).alterTable('users', (t) {
    t.increments('id');
  }),
  'schema/alter-table-add-bigincrements': (d) =>
      _sb(d).alterTable('users', (t) {
        t.bigIncrements('id');
      }),

  'schema/alter-table-add-text': (d) => _sb(d).alterTable('users', (t) {
    t.text('foo');
  }),
  'schema/alter-table-add-biginteger': (d) => _sb(d).alterTable('users', (t) {
    t.bigInteger('foo');
  }),
  'schema/alter-table-add-boolean': (d) => _sb(d).alterTable('users', (t) {
    t.boolean('foo');
  }),
  'schema/alter-table-add-enum': (d) => _sb(d).alterTable('users', (t) {
    t.enu('foo', ['bar', 'baz']);
  }),
  'schema/alter-table-add-date': (d) => _sb(d).alterTable('users', (t) {
    t.date('foo');
  }),
  'schema/alter-table-add-datetime': (d) => _sb(d).alterTable('users', (t) {
    t.datetime('foo');
  }),
  'schema/alter-table-add-time': (d) => _sb(d).alterTable('users', (t) {
    t.time('foo');
  }),
  'schema/alter-table-add-timestamp': (d) => _sb(d).alterTable('users', (t) {
    t.timestamp('foo');
  }),
  'schema/alter-table-add-timestamps': (d) => _sb(d).alterTable('users', (t) {
    t.timestamps();
  }),
  'schema/alter-table-add-binary': (d) => _sb(d).alterTable('users', (t) {
    t.binary('foo');
  }),
  'schema/alter-table-add-uuid': (d) => _sb(d).alterTable('users', (t) {
    t.uuid('foo');
  }),
  'schema/alter-table-add-decimal': (d) => _sb(d).alterTable('users', (t) {
    t.decimal('foo', 5, 2);
  }),
  'schema/alter-table-add-double': (d) => _sb(d).alterTable('users', (t) {
    t.doublePrecision('foo');
  }),

  'schema/create-table-default-raw-timestamp': (d) =>
      _sb(d).createTable('default_raw_test', (t) {
        t
            .timestamp('created_at')
            .defaultTo(_raw(d, 'CURRENT_TIMESTAMP'));
      }),

  'schema/alter-table-drop-unique-composite': (d) =>
      _sb(d).alterTable('composite_key_test', (t) {
        t.dropUnique(['column_a', 'column_b']);
      }),

  'schema/alter-table-comment': (d) => _sb(d).alterTable('users', (t) {
    t.comment('Custom comment');
  }),
  'schema/create-table-comment': (d) => _sb(d).createTable('users', (t) {
    t.string('username');
    t.comment('Custom comment');
  }),

  // ── Mined from knex.js test/unit/schema-builder/redshift.js ──────────────
  // (schema DDL batch 4 — see tool/parity/README.md). Same ids/theming as
  // the mirror block in tool/parity/run_js_schema.mjs.

  // ── Column types (via alterTable, one column each) ────────────────────────
  'schema/column-increments': (d) => _sb(d).alterTable('users', (t) {
    t.increments('foo');
  }),
  'schema/column-bigincrements': (d) => _sb(d).alterTable('users', (t) {
    t.bigIncrements('foo');
  }),
  'schema/column-string-length': (d) => _sb(d).alterTable('users', (t) {
    t.string('foo', 100);
  }),
  'schema/column-string-default': (d) => _sb(d).alterTable('users', (t) {
    t.string('foo', 100).defaultTo('bar');
  }),
  'schema/column-text': (d) => _sb(d).alterTable('users', (t) {
    t.text('foo');
  }),
  'schema/column-biginteger': (d) => _sb(d).alterTable('users', (t) {
    t.bigInteger('foo');
  }),
  'schema/column-integer': (d) => _sb(d).alterTable('users', (t) {
    t.integer('foo');
  }),
  'schema/column-float': (d) => _sb(d).alterTable('users', (t) {
    t.float('foo');
  }),
  'schema/column-double': (d) => _sb(d).alterTable('users', (t) {
    t.doublePrecision('foo');
  }),
  'schema/column-decimal': (d) => _sb(d).alterTable('users', (t) {
    t.decimal('foo', 5, 2);
  }),
  'schema/column-boolean-default': (d) => _sb(d).alterTable('users', (t) {
    t.boolean('foo').defaultTo(false);
  }),
  'schema/column-enum': (d) => _sb(d).alterTable('users', (t) {
    t.enu('foo', ['bar', 'baz']);
  }),
  'schema/column-date': (d) => _sb(d).alterTable('users', (t) {
    t.date('foo');
  }),
  'schema/column-datetime': (d) => _sb(d).alterTable('users', (t) {
    t.datetime('foo');
  }),
  'schema/column-time': (d) => _sb(d).alterTable('users', (t) {
    t.time('foo');
  }),
  'schema/column-timestamp': (d) => _sb(d).alterTable('users', (t) {
    t.timestamp('foo');
  }),
  'schema/column-timestamps-basic': (d) => _sb(d).alterTable('users', (t) {
    t.timestamps();
  }),
  'schema/column-timestamps-defaults': (d) => _sb(d).alterTable('users', (t) {
    t.timestamps(false, true);
  }),
  'schema/column-binary': (d) => _sb(d).alterTable('users', (t) {
    t.binary('foo');
  }),
  'schema/column-jsonb': (d) => _sb(d).alterTable('users', (t) {
    t.jsonb('foo');
  }),
  'schema/column-uuid': (d) => _sb(d).alterTable('users', (t) {
    t.uuid('foo');
  }),
  'schema/column-json-default-notnull': (d) => _sb(d).alterTable('users', (t) {
    t.json('foo').defaultTo(<String, dynamic>{}).notNullable();
  }),
  'schema/column-specifictype-unique-notnull': (d) =>
      _sb(d).alterTable('users', (t) {
        t.specificType('foo', 'CITEXT').unique().notNullable();
      }),

  // ── Mined from knex.js test/unit/schema-builder/postgres.js ──────────────
  // (schema DDL batch 6). Same ids/theming as the mirror block in
  // tool/parity/run_js_schema.mjs.
  'schema/view-refresh-materialized-concurrently': (d) =>
      _sb(d).refreshMaterializedView('view_to_refresh', true),

  'schema/drop-table-with-schema': (d) =>
      _sb(d).withSchema('myschema').dropTable('users'),
  'schema/drop-table-if-exists-with-schema': (d) =>
      _sb(d).withSchema('myschema').dropTableIfExists('users'),

  'schema/alter-table-drop-index-with-schema': (d) =>
      _sb(d).withSchema('mySchema').alterTable('users', (t) {
        t.dropIndex('foo');
      }),

  'schema/alter-table-drop-primary-named': (d) =>
      _sb(d).alterTable('users', (t) {
        t.dropPrimary('testconstraintname');
      }),

  'schema/alter-table-primary-single-column-unnamed': (d) =>
      _sb(d).alterTable('users', (t) {
        t.primary('foo');
      }),

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
      }),

  'schema/alter-table-comment-empty': (d) => _sb(d).alterTable('user', (t) {
    t.comment('');
  }),

  'schema/create-extension': (d) => _sb(d).createExtension('test'),
  'schema/create-extension-if-not-exists': (d) =>
      _sb(d).createExtensionIfNotExists('test'),
  'schema/drop-extension': (d) => _sb(d).dropExtension('test'),
  'schema/drop-extension-if-exists': (d) =>
      _sb(d).dropExtensionIfExists('test'),

  'schema/alter-table-add-column-primary-fluent': (d) =>
      _sb(d).alterTable('users', (t) {
        t.string('test').primary();
      }),
  'schema/alter-table-add-column-primary-fluent-named': (d) =>
      _sb(d).alterTable('users', (t) {
        t.string('test').primary(constraintName: 'testname');
      }),

  'schema/create-table-primary-fluent-named': (d) =>
      _sb(d).createTable('users', (t) {
        t.string('test').primary(constraintName: 'testconstraintname');
      }),

  // Batch 6 — column-type dialect-dispatch + views + createTableLike +
  // createTableIfNotExists + dropColumns-multi. Mirrors run_js_schema.mjs
  // 1:1 by id. Dart's column-type dispatch goes through column_builder.dart's
  // `toSQL()`; views go through schema_compiler.dart's per-method dispatchers.

  // ── Column types (dialect-dispatch territory) ────────────────────────
  'schema/column-boolean': (d) => _sb(d).alterTable('users', (t) {
    t.boolean('enabled').defaultTo(false);
  }),
  'schema/column-uuid-bare': (d) => _sb(d).alterTable('users', (t) {
    t.uuid('external_id');
  }),
  'schema/column-enu': (d) => _sb(d).alterTable('users', (t) {
    t.enu('status', ['active', 'idle']);
  }),
  'schema/column-bigInteger': (d) => _sb(d).alterTable('users', (t) {
    t.bigInteger('big_count');
  }),
  'schema/column-bigIncrements': (d) => _sb(d).alterTable('users', (t) {
    t.bigIncrements('audit_id');
  }),

  // ── Views cluster ────────────────────────────────────────────────────
  'schema/create-view-bare': (d) => _sb(d)
      .createView(
        'active_users',
        KnexQuery.forClient(
          d,
        ).queryBuilder().table('users').select(['*']).where('active', true),
      )
      ,
  // create-view-or-replace, drop-view, rename-view, and create-materialized-view
  // were removed here — CodeRabbit-flagged as exact duplicates (same builder
  // methods, same shape, only the table name differed) of view-create-or-replace,
  // view-drop, view-rename, and view-create-materialized above. Kept: this
  // cluster's genuinely distinct cases (create-view-bare uses a differently-
  // shaped query than view-create-basic; drop-view-if-exists and
  // refresh-materialized-view aren't covered above at all).
  'schema/drop-view-if-exists': (d) =>
      _sb(d).dropViewIfExists('active_users'),
  'schema/refresh-materialized-view': (d) =>
      _sb(d).refreshMaterializedView('active_users_mv'),
  'schema/refresh-materialized-view-concurrently': (d) =>
      _sb(d).refreshMaterializedView('active_users_mv', true),

  // ── createTableIfNotExists, createTableLike, dropColumns-multi ────────
  'schema/create-table-if-not-exists': (d) =>
      _sb(d).createTableIfNotExists('users', (t) {
        t.increments('id');
        t.string('email');
      }),
  'schema/create-table-like': (d) =>
      _sb(d).createTableLike('users_copy', 'users'),
  'schema/alter-table-drop-columns-multi': (d) =>
      _sb(d).alterTable('users', (t) {
        t.dropColumns(['nickname', 'avatar']);
      }),

  // ── Batch 7: schema raw + pg-only materialized-view drops ────────────
  'schema/raw-with-binding': (d) =>
      _sb(d).raw('select ? as value', [1]),
  'schema/drop-materialized-view': (d) =>
      _sb(d).dropMaterializedView('active_users_mv'),
  'schema/drop-materialized-view-if-exists': (d) =>
      _sb(d).dropMaterializedViewIfExists('active_users_mv'),

  // ── Batch 8: pg-only CREATE/DROP SCHEMA family ────────────────────────
  'schema/create-schema': (d) => _sb(d).createSchema('billing'),
  'schema/create-schema-if-not-exists': (d) =>
      _sb(d).createSchemaIfNotExists('billing'),
  'schema/drop-schema': (d) => _sb(d).dropSchema('billing'),
  'schema/drop-schema-cascade': (d) =>
      _sb(d).dropSchema('billing', true),
  'schema/drop-schema-if-exists': (d) =>
      _sb(d).dropSchemaIfExists('billing'),
  'schema/drop-schema-if-exists-cascade': (d) =>
      _sb(d).dropSchemaIfExists('billing', true),

  // ── Batch 9: table() as an alterTable() alias ─────────────────────────
  'schema/table-alias': (d) => _sb(d).table('users', (t) {
    t.string('x');
  }),
};
