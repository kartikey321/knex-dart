/// Postgres prerequisite DDL for the schema-DDL corpus's live-execution
/// linking, one profile per distinct prerequisite shape a cluster of
/// `schema/*` cases actually needs.
///
/// Unlike the query corpus's profiles (`postgres_fixture_profiles.dart`,
/// applied once and shared across an entire run), every one of these is
/// applied fresh into its own case's private ephemeral schema — see
/// `postgres_schema_live_execution_test.dart`, which calls
/// `adapter.setUpRun()`/`tearDownRun()` around EACH case individually,
/// unlike the query test's single shared setUpAll. This is required, not
/// stylistic: DDL cases routinely need OPPOSITE starting states for the
/// exact same table/column/constraint name (e.g. `alter-table-add-unique`
/// needs `users.email` NOT yet uniquely constrained by knex-dart's own
/// default-computed constraint name, while `alter-table-drop-unique` needs
/// that exact same default-named constraint to already exist) — a shared
/// per-run schema could never satisfy both. Per-case schemas make every
/// profile below trivially self-consistent instead: it only has to agree
/// with the ONE case (or handful of identically-shaped cases) linked to it,
/// never with every other schema case in the corpus.
///
/// Every DDL block here was verified by an actual dry run against real
/// Postgres (see PR description / commit message for the harness), not
/// hand-derived from reading the compiler source alone — Postgres's exact
/// default constraint/index-naming rules (`<table>_<cols>_unique`,
/// `<table>_<cols>_index`, `<table>_<cols>_foreign`, `<table>_pkey`) had to
/// match knex-dart's OWN computed defaults exactly for drop-type cases to
/// find what they're dropping.
library;

const Map<String, List<String>> postgresSchemaDdlProfiles = {
  // No prerequisite at all — self-contained CREATE-type cases.
  'schema_ddl_empty_v1': [],

  // Bare `users` table with zero columns — safe starting point for any
  // case that only ADDS a new column/constraint under a name nothing here
  // already uses (verified: none of the linked cases' target names collide
  // with each other, since each runs in its own private schema anyway).
  'schema_ddl_users_bare_v1': ['CREATE TABLE users ()'],

  // `users(foo, test1, test2, email)` — pre-existing plain columns for
  // cases that ADD a new constraint over an EXISTING column (unique/index/
  // primary), with no constraint of that shape already present.
  'schema_ddl_users_constraints_v1': [
    'CREATE TABLE users (foo varchar(100), test1 varchar(100), '
        'test2 varchar(100), email varchar(100))',
  ],

  // The three cases targeting `alterTable('user', ...)` — literally
  // singular, a distinct table from `users`.
  'schema_ddl_user_singular_v1': ['CREATE TABLE "user" (id serial primary key)'],

  // `users.nickname` pre-existing, nothing else — for
  // alter-table-drop-column/alter-table-rename-column, which need it
  // present (the ADD-column cluster above needs it ABSENT, hence separate
  // profiles even though both just concern "a nickname column").
  'schema_ddl_users_nickname_v1': ['CREATE TABLE users (nickname varchar(100))'],

  'schema_ddl_users_foo_bar_v1': [
    'CREATE TABLE users (foo varchar(100), bar varchar(100))',
  ],
  'schema_ddl_users_nickname_avatar_v1': [
    'CREATE TABLE users (nickname varchar(100), avatar varchar(100))',
  ],
  'schema_ddl_users_timestamps_v1': [
    'CREATE TABLE users (created_at timestamp, updated_at timestamp)',
  ],
  'schema_ddl_users_email_v1': ['CREATE TABLE users (email varchar(100))'],

  // Default-named unique/index constraints on `users.email` — the exact
  // name knex-dart's own dropUnique/dropIndex compute when called
  // unnamed/named, per schema_compiler.dart's `${tableName}_${cols}_unique`
  // / `_index` convention.
  'schema_ddl_users_unique_default_v1': [
    'CREATE TABLE users (email varchar(100))',
    'ALTER TABLE users ADD CONSTRAINT users_email_unique UNIQUE (email)',
  ],
  'schema_ddl_users_unique_named_v1': [
    'CREATE TABLE users (email varchar(100))',
    'ALTER TABLE users ADD CONSTRAINT uq_users_email UNIQUE (email)',
  ],
  'schema_ddl_users_index_default_v1': [
    'CREATE TABLE users (email varchar(100))',
    'CREATE INDEX users_email_index ON users(email)',
  ],
  'schema_ddl_users_index_named_v1': [
    'CREATE TABLE users (email varchar(100))',
    'CREATE INDEX idx_users_email ON users(email)',
  ],

  // dropUnique(null, 'foo') / dropIndex(null, 'foo') / dropForeign(null,
  // 'foo') compile to "drop constraint/index 'foo'" regardless of the
  // (null) columns argument — each needs an object of the matching type
  // literally named 'foo' pre-existing.
  'schema_ddl_users_unique_foo_v1': [
    'CREATE TABLE users (x varchar(100))',
    'ALTER TABLE users ADD CONSTRAINT foo UNIQUE (x)',
  ],
  'schema_ddl_users_index_foo_v1': [
    'CREATE TABLE users (x varchar(100))',
    'CREATE INDEX foo ON users(x)',
  ],
  'schema_ddl_users_foreign_foo_v1': [
    'CREATE TABLE ref_t (id serial primary key)',
    'CREATE TABLE users (ref_id integer)',
    'ALTER TABLE users ADD CONSTRAINT foo FOREIGN KEY (ref_id) REFERENCES ref_t(id)',
  ],
  'schema_ddl_users_primary_named_v1': [
    'CREATE TABLE users (id integer)',
    'ALTER TABLE users ADD CONSTRAINT testconstraintname PRIMARY KEY (id)',
  ],

  // `memberships(user_id, org_id)` — with vs. without a pre-existing
  // composite PK, matching whichever a case ADDs vs. DROPs.
  'schema_ddl_memberships_bare_v1': [
    'CREATE TABLE memberships (user_id integer, org_id integer)',
  ],
  'schema_ddl_memberships_pk_v1': [
    'CREATE TABLE memberships (user_id integer, org_id integer, '
        'CONSTRAINT memberships_pkey PRIMARY KEY (user_id, org_id))',
  ],

  // `orders`/`users` FK-target variants.
  'schema_ddl_orders_bare_v1': [
    'CREATE TABLE users (id serial primary key)',
    'CREATE TABLE orders (id serial primary key)',
  ],
  'schema_ddl_orders_fk_v1': [
    'CREATE TABLE users (id serial primary key)',
    'CREATE TABLE orders (id serial primary key, user_id integer)',
    'ALTER TABLE orders ADD CONSTRAINT orders_user_id_foreign '
        'FOREIGN KEY (user_id) REFERENCES users(id)',
  ],
  'schema_ddl_orders_user_id_v1': [
    'CREATE TABLE users (id serial primary key)',
    'CREATE TABLE orders (id serial primary key, user_id integer)',
  ],

  'schema_ddl_t_bare_v1': ['CREATE TABLE t (id serial primary key)'],

  'schema_ddl_composite_key_test_v1': [
    'CREATE TABLE composite_key_test (column_a varchar(100), column_b varchar(100))',
    'ALTER TABLE composite_key_test ADD CONSTRAINT '
        'composite_key_test_column_a_column_b_unique UNIQUE (column_a, column_b)',
  ],

  // Reference-only `users` shapes for CREATE-type cases (FK target, view
  // source, createTableLike source) — these only READ the shape, so many
  // otherwise-unrelated cases can safely share one.
  'schema_ddl_users_ref_v1': ['CREATE TABLE users (id serial primary key)'],
  'schema_ddl_users_accounts_ref_v1': [
    'CREATE TABLE users (id serial primary key)',
    'CREATE TABLE accounts (id serial primary key)',
  ],
  'schema_ddl_users_name_ref_v1': [
    'CREATE TABLE users (id serial primary key, name varchar(100))',
  ],
  'schema_ddl_users_active_ref_v1': [
    'CREATE TABLE users (id serial primary key, name varchar(100), active boolean)',
  ],
  'schema_ddl_users_age_ref_v1': [
    'CREATE TABLE users (id serial primary key, name varchar(100), age integer)',
  ],

  'schema_ddl_billing_schema_v1': ['CREATE SCHEMA billing'],

  'schema_ddl_active_users_mv_v1': [
    'CREATE TABLE t (x integer)',
    'CREATE MATERIALIZED VIEW active_users_mv AS SELECT * FROM t',
  ],
  'schema_ddl_active_users_mv_concurrent_v1': [
    'CREATE TABLE t (x integer)',
    'CREATE UNIQUE INDEX active_users_mv_x ON t (x)',
    'CREATE MATERIALIZED VIEW active_users_mv AS SELECT * FROM t',
    'CREATE UNIQUE INDEX active_users_mv_idx ON active_users_mv (x)',
  ],
  'schema_ddl_view_to_refresh_v1': [
    'CREATE TABLE t (x integer)',
    'CREATE MATERIALIZED VIEW view_to_refresh AS SELECT * FROM t',
  ],
  'schema_ddl_view_to_refresh_concurrent_v1': [
    'CREATE TABLE t (x integer)',
    'CREATE UNIQUE INDEX view_to_refresh_x ON t (x)',
    'CREATE MATERIALIZED VIEW view_to_refresh AS SELECT * FROM t',
    'CREATE UNIQUE INDEX view_to_refresh_idx ON view_to_refresh (x)',
  ],
  'schema_ddl_view_users_v1': ['CREATE VIEW users AS SELECT 1 AS x'],
  'schema_ddl_view_old_v1': ['CREATE VIEW old_view AS SELECT 1 AS x'],
  'schema_ddl_view_active_users_v1': ['CREATE VIEW active_users AS SELECT 1 AS x'],

  // withSchema('myschema'/'mySchema') cases — these are DATABASE-level
  // schemas, siblings of (not nested inside) each case's own ephemeral
  // wrapper schema, so the adapter must explicitly drop them too (see
  // PostgresLiveAdapter's schema-DDL-specific cleanup).
  'schema_ddl_myschema_users_table_v1': [
    'CREATE SCHEMA myschema',
    'CREATE TABLE myschema.users (id serial primary key)',
  ],
  'schema_ddl_myschema_users_view_v1': [
    'CREATE SCHEMA myschema',
    'CREATE VIEW myschema.users AS SELECT 1 AS x',
  ],
  'schema_ddl_myschema_cap_users_index_v1': [
    'CREATE SCHEMA "mySchema"',
    'CREATE TABLE "mySchema".users (foo varchar(100))',
    'CREATE INDEX users_foo_index ON "mySchema".users(foo)',
  ],

  // CREATE EXTENSION with no explicit SCHEMA clause installs into whatever
  // schema is first in search_path (verified directly against real
  // Postgres) — since the adapter always points search_path at this case's
  // own ephemeral schema first, this never touches (or depends on)
  // "public".
  'schema_ddl_citext_users_v1': [
    'CREATE EXTENSION IF NOT EXISTS citext',
    'CREATE TABLE users ()',
  ],
};

/// Database-level schema names some profiles above create via
/// `CREATE SCHEMA` for `withSchema(...)` cases — cleaned up explicitly
/// after every schema-DDL case run (success or failure) since they live
/// alongside, not inside, each case's own ephemeral wrapper schema.
const List<String> postgresSchemaDdlNamedSchemasToClean = [
  'myschema',
  'mySchema',
  'billing',
];
