/// SQLite-specific DDL/seed SQL text for each [FixtureProfileRef] known to
/// `knex_dart_live_test`. Mirrors the *shape* of
/// `drivers/knex_dart_postgres/test/live_execution/postgres_fixture_profiles.dart`
/// under the same profile ids (a [FixtureProfileRef] id is dialect-agnostic
/// identity — the DDL/seed text is inherently dialect-specific), but is not
/// a text copy: SQLite has no `SERIAL`/`JSONB`/native boolean type, so every
/// column type below was translated deliberately:
///   - `SERIAL PRIMARY KEY`      -> `INTEGER PRIMARY KEY AUTOINCREMENT`
///   - `VARCHAR(n)`              -> `TEXT`
///   - `BOOLEAN` / `DEFAULT true`-> `INTEGER` / `DEFAULT 1` (0/1, no native bool)
///   - `DECIMAL(10, 2)`          -> `NUMERIC`
///   - `TIMESTAMP`               -> `TEXT` (SQLite has no native datetime type)
///   - `JSONB`                   -> `TEXT` (JSON columns are just TEXT; use
///     `json_*()` functions, not a native json/jsonb type)
library;

/// canonical_seed_v2 (sqlite): same table/column/row shape as postgres's
/// `canonical_seed_v2`, translated to SQLite types, under the same id since
/// [FixtureProfileRef] identity is dialect-agnostic. Additionally a strict
/// superset of postgres's column list on `users` —
/// `meta`/`admin`/`contact_id`/`user_id`/`tenant_id` — added empirically
/// during the sqlite dry-run pass for the `on/*` (JoinClause) family
/// (`onJsonPathEquals`, `orOn`/`.on()` map comparisons against
/// `contacts.admin`, `joinRaw` against `contacts.id = users.contact_id`,
/// `.using(['user_id', 'tenant_id'])` requiring both sides to share those
/// column names). Safe to widen here (unlike postgres's frozen v1->v2
/// history) because no sqlite case was linked to this profile before these
/// columns were added — this is still the first pass.
const canonicalSeedV2Ddl = <String>[
  '''
CREATE TABLE users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT,
  email TEXT UNIQUE,
  active INTEGER DEFAULT 1,
  role TEXT,
  created_at TEXT DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
  a INTEGER,
  b INTEGER,
  c INTEGER,
  bar TEXT,
  qux TEXT,
  boom TEXT,
  org TEXT,
  foo TEXT,
  baz TEXT,
  foo_email TEXT,
  user_foo TEXT,
  user_bar TEXT,
  address TEXT,
  age INTEGER,
  status TEXT,
  deleted_at TEXT,
  activated INTEGER,
  "otherId" INTEGER,
  value TEXT,
  account_id INTEGER,
  meta TEXT,
  admin INTEGER,
  contact_id INTEGER,
  user_id INTEGER,
  tenant_id INTEGER
)''',
  '''
CREATE TABLE orders (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
  product_id INTEGER,
  amount NUMERIC NOT NULL,
  status TEXT DEFAULT 'pending',
  created_at TEXT DEFAULT CURRENT_TIMESTAMP,
  total INTEGER
)''',
  '''
CREATE TABLE products (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  category TEXT,
  price NUMERIC NOT NULL
)''',
  'CREATE INDEX idx_users_email ON users(email)',
  'CREATE INDEX idx_users_active ON users(active)',
  'CREATE INDEX idx_orders_user_id ON orders(user_id)',
  'CREATE INDEX idx_orders_status ON orders(status)',
  // dml/onconflict-composite-ignore targets a composite (org, email) conflict.
  'CREATE UNIQUE INDEX idx_users_org_email ON users(org, email)',
  // dml/onconflict-raw-target targets a raw "(value) WHERE deleted_at IS NULL".
  'CREATE UNIQUE INDEX idx_users_value_active ON users(value) '
      'WHERE deleted_at IS NULL',
];

const canonicalSeedV2Seed = <String>[
  '''
INSERT INTO users (name, email, active, role, age, status) VALUES
  ('Alice Johnson', 'alice@example.com', 1, 'admin', 30, 'active'),
  ('Bob Smith', 'bob@example.com', 1, 'user', 45, 'active'),
  ('Charlie Brown', 'charlie@example.com', 0, 'user', 22, 'inactive'),
  ('Diana Prince', 'diana@example.com', 1, 'moderator', 38, 'active'),
  ('Eve Davis', 'eve@example.com', 1, 'user', 51, 'active')''',
  '''
INSERT INTO products (name, category, price) VALUES
  ('Laptop', 'Electronics', 999.99),
  ('Mouse', 'Electronics', 29.99),
  ('Desk Chair', 'Furniture', 199.99),
  ('Monitor', 'Electronics', 299.99),
  ('Keyboard', 'Electronics', 79.99)''',
  // Exactly one row has total > 100, mirroring postgres's canonical_seed_v2:
  // select/alias-map-subquery uses an uncorrelated scalar subquery as a
  // select-map value, which breaks if it can return more than one row.
  '''
INSERT INTO orders (user_id, product_id, amount, status, total) VALUES
  (1, 1, 999.99, 'completed', 150),
  (1, 2, 29.99, 'completed', 50),
  (2, 3, 199.99, 'pending', 50),
  (2, 4, 299.99, 'completed', 50),
  (4, 1, 999.99, 'completed', 50),
  (4, 5, 79.99, 'completed', 50),
  (5, 2, 29.99, 'cancelled', 50)''',
];

const ddlEmptyV1Ddl = canonicalSeedV2Ddl;
const ddlEmptyV1Seed = <String>[];

/// Generic join/set-op tables — same shape as postgres's `synthetic_join_v1`
/// (`a`/`b`/`c`, identical columns so UNION/INTERSECT/EXCEPT column counts
/// match), translated to SQLite types.
const _abcColumns = '''
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  a_id INTEGER,
  name TEXT,
  x INTEGER,
  y INTEGER,
  z INTEGER,
  status TEXT
''';

const syntheticJoinV1Ddl = <String>[
  'CREATE TABLE a (\n$_abcColumns\n)',
  'CREATE TABLE b (\n$_abcColumns\n)',
  'CREATE TABLE c (\n$_abcColumns\n)',
];

const syntheticJoinV1Seed = <String>[
  '''
INSERT INTO a (name, x, status) VALUES
  ('A One', 1, 'active'),
  ('A Two', 2, 'inactive')''',
  '''
INSERT INTO b (a_id, name, x, y, status) VALUES
  (1, 'B One', 10, 2, 'active'),
  (2, 'B Two', 20, 99, 'inactive')''',
  '''
INSERT INTO c (a_id, name, z, status) VALUES
  (1, 'C One', 3, 'active'),
  (2, 'C Two', 99, 'inactive')''',
];

/// Generic aggregate/where/having kitchen-sink table — same shape as
/// postgres's `synthetic_aggregate_v1`, translated to SQLite types. `tags`
/// is TEXT (SQLite has no native json/jsonb type); the seeded values are
/// plain JSON-looking text, sufficient for cases that don't invoke a
/// jsonb-only operator.
const syntheticAggregateV1Ddl = <String>[
  '''
CREATE TABLE t (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT,
  amount NUMERIC,
  lo INTEGER,
  hi INTEGER,
  cat TEXT,
  cnt INTEGER,
  views INTEGER,
  score INTEGER,
  age INTEGER,
  a INTEGER,
  b INTEGER,
  c INTEGER,
  d INTEGER,
  x INTEGER,
  status TEXT,
  email TEXT,
  deleted_at TEXT,
  archived_at TEXT,
  author_id INTEGER,
  category TEXT,
  tags TEXT
)''',
  '''
CREATE TABLE src (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  flag INTEGER
)''',
  '''
CREATE TABLE inner_t (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  x INTEGER
)''',
];

const syntheticAggregateV1Seed = <String>[
  '''
INSERT INTO t (
  name, amount, lo, hi, cat, cnt, views, score, age,
  a, b, c, d, x, status, email, deleted_at, archived_at,
  author_id, category, tags
) VALUES
  ('Alpha', 100.00, 5, 50, 'A', 3, 10, 80, 25,
   1, 2, NULL, NULL, 1, 'active', 'alpha@example.com', NULL, NULL,
   1, 'cat1', '{"urgent": true}'),
  ('Beta', 200.00, 10, 60, 'A', 5, 20, 90, 30,
   3, NULL, 4, NULL, 1, 'banned', 'beta@example.com', NULL, NULL,
   1, 'cat2', '{}'),
  ('Gamma', 300.00, 2, 70, 'B', 1, 30, 70, 40,
   NULL, NULL, NULL, NULL, 2, 'active', 'gamma@example.com',
   '2024-01-01', '2024-02-01', 2, 'cat1', '{}')''',
  '''
INSERT INTO src (flag) VALUES
  (1),
  (0)''',
  '''
INSERT INTO inner_t (x) VALUES
  (1),
  (2)''',
];

/// Window-function batch's `accounts` table — same shape as postgres's
/// `accounts_window_v1`, translated to SQLite types. Unlike postgres,
/// SQLite folds nothing by case for double-quoted identifiers either way,
/// but the `"firstName"`/`"lastName"` quoting is kept to match exactly what
/// knex-dart emits for camelCase identifiers.
const accountsWindowV1Ddl = <String>[
  '''
CREATE TABLE accounts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER,
  email TEXT,
  "firstName" TEXT,
  "lastName" TEXT,
  address TEXT,
  phone TEXT,
  salary NUMERIC,
  dept TEXT,
  name TEXT
)''',
];

const accountsWindowV1Seed = <String>[
  '''
INSERT INTO accounts (
  email, "firstName", "lastName", address, phone, salary, dept, name
) VALUES
  ('alice@example.com', 'Alice', 'Anderson', '123 Main St', '555-0001',
   90000.00, 'eng', 'Alice Anderson'),
  ('bob@example.com', 'Bob', 'Brown', '456 Oak Ave', '555-0002',
   85000.00, 'eng', 'Bob Brown'),
  ('carol@example.com', 'Carol', 'Clark', '789 Pine Rd', '555-0003',
   95000.00, 'sales', 'Carol Clark')''',
];

/// Join-target and one-off tables — same shape as postgres's
/// `join_targets_v1`, translated to SQLite types. Reserved-word
/// (`"group"`, `"user"`, `"table"`, `"column"`) and camelCase
/// (`"PersonId"`, `"City"`, `"DataId"`) identifiers are quoted to match
/// exactly what knex-dart emits — unlike postgres, unquoted SQLite
/// identifiers are NOT case-folded, but the quoting is kept anyway so the
/// DDL text stays a faithful structural mirror of the postgres profile.
const joinTargetsV1Ddl = <String>[
  '''
CREATE TABLE contacts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER,
  tenant_id INTEGER,
  kind INTEGER,
  state INTEGER,
  score INTEGER,
  status TEXT,
  role TEXT,
  active INTEGER,
  admin INTEGER,
  address TEXT,
  phone TEXT,
  email TEXT,
  deleted_at TEXT,
  meta TEXT
)''',
  'CREATE TABLE phones (id INTEGER PRIMARY KEY AUTOINCREMENT, contact_id INTEGER, active INTEGER)',
  'CREATE TABLE photos (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT)',
  'CREATE TABLE docs (id INTEGER PRIMARY KEY AUTOINCREMENT)',
  'CREATE TABLE emails (id INTEGER PRIMARY KEY AUTOINCREMENT, verified INTEGER)',
  'CREATE TABLE blocks (id INTEGER PRIMARY KEY AUTOINCREMENT, blocked INTEGER)',
  'CREATE TABLE contracts (id INTEGER PRIMARY KEY AUTOINCREMENT)',
  'CREATE TABLE admins (id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER, enabled INTEGER)',
  '''
CREATE TABLE "group" (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  group_id INTEGER,
  group_name TEXT
)''',
  'CREATE TABLE "user" (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, group_id INTEGER)',
  'CREATE TABLE order_meta (id INTEGER PRIMARY KEY AUTOINCREMENT, order_id INTEGER, value TEXT)',
  'CREATE TABLE refunds (id INTEGER PRIMARY KEY AUTOINCREMENT, order_id INTEGER)',
  'CREATE TABLE entries (id INTEGER PRIMARY KEY AUTOINCREMENT, secret INTEGER, sequence INTEGER)',
  'CREATE TABLE "table" (id INTEGER PRIMARY KEY AUTOINCREMENT, a INTEGER, b INTEGER, c INTEGER)',
  '''
CREATE TABLE sometable (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  "column" TEXT,
  one TEXT,
  two TEXT
)''',
  'CREATE TABLE someothertable (id INTEGER PRIMARY KEY AUTOINCREMENT, someothercolumn TEXT)',
  'CREATE TABLE foo (id INTEGER PRIMARY KEY AUTOINCREMENT)',
  'CREATE TABLE baz (id INTEGER PRIMARY KEY AUTOINCREMENT, foo_id INTEGER)',
  'CREATE TABLE bars (id INTEGER PRIMARY KEY AUTOINCREMENT)',
  'CREATE TABLE foos (id INTEGER PRIMARY KEY AUTOINCREMENT, foo_id INTEGER, bar_id INTEGER)',
  '''
CREATE TABLE "tblPerson" (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  "PersonId" INTEGER,
  "City" TEXT
)''',
  '''
CREATE TABLE "tblPersonData" (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  "PersonId" INTEGER,
  "DataId" INTEGER
)''',
  'CREATE TABLE tbl (foo TEXT)',
  'CREATE TABLE testtable (is_active INTEGER)',
  '''
CREATE TABLE employee (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  lastname TEXT,
  salary NUMERIC,
  dept_no INTEGER
)''',
];

const joinTargetsV1Seed = <String>[
  '''
INSERT INTO employee (lastname, salary, dept_no) VALUES
  ('Smith', 60000.00, 1),
  ('Jones', 65000.00, 1),
  ('Lee', 70000.00, 2)''',
];

/// dialect-agnostic identity for each profile lives in
/// `fixture_profile.dart`; DDL/seed content is sqlite-specific here.
const Map<String, ({List<String> ddl, List<String> seed})>
sqliteFixtureProfiles = {
  'canonical_seed_v2': (ddl: canonicalSeedV2Ddl, seed: canonicalSeedV2Seed),
  'ddl_empty_v1': (ddl: ddlEmptyV1Ddl, seed: ddlEmptyV1Seed),
  'synthetic_join_v1': (ddl: syntheticJoinV1Ddl, seed: syntheticJoinV1Seed),
  'synthetic_aggregate_v1': (
    ddl: syntheticAggregateV1Ddl,
    seed: syntheticAggregateV1Seed,
  ),
  'accounts_window_v1': (
    ddl: accountsWindowV1Ddl,
    seed: accountsWindowV1Seed,
  ),
  'join_targets_v1': (ddl: joinTargetsV1Ddl, seed: joinTargetsV1Seed),
};
