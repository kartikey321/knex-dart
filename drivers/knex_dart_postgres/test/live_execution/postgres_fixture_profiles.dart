/// Postgres-specific DDL/seed SQL text for each [FixtureProfileRef] known
/// to `knex_dart_live_test`. Hand-authored here rather than read from
/// `test/integration/sql/postgres_*.sql` at runtime — those files belong to
/// the older hand-written suite; this is the versioned artifact for the
/// live-execution framework, even though the shape currently matches.
library;

/// canonical_seed_v2 supersedes canonical_seed_v1 (retired — see git history
/// at commit 6f7e419/9a66b49 for its exact prior content). v1's users/orders
/// shape turned out too narrow for a large cluster of where/having/select/
/// json/onconflict cases discovered in the next dry-run pass; since a
/// fixture profile's DDL is a versioned artifact that must never be
/// silently mutated once cases are linked against it, this is a new version
/// rather than an in-place edit. It is a strict additive superset of v1
/// (same tables/columns/rows, `name`/`email` loosened from NOT NULL, plus
/// new nullable columns and two extra unique indexes — a NULL `email` can't
/// violate its own UNIQUE constraint since Postgres never treats two NULLs
/// as equal) — re-verified empirically that every case previously linked to
/// v1 also executes clean under v2 before v1 was retired and all links
/// moved over.
const canonicalSeedV2Ddl = <String>[
  '''
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100),
  email VARCHAR(100) UNIQUE,
  active BOOLEAN DEFAULT true,
  role VARCHAR(50),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  a INTEGER,
  b INTEGER,
  c INTEGER,
  bar VARCHAR(100),
  qux VARCHAR(100),
  boom VARCHAR(100),
  org VARCHAR(100),
  foo VARCHAR(100),
  baz VARCHAR(100),
  foo_email VARCHAR(100),
  user_foo VARCHAR(100),
  user_bar VARCHAR(100),
  address JSONB,
  age INTEGER,
  status VARCHAR(50),
  deleted_at TIMESTAMP,
  activated BOOLEAN,
  "otherId" INTEGER,
  value VARCHAR(100),
  account_id INTEGER
)''',
  '''
CREATE TABLE orders (
  id SERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
  product_id INTEGER,
  amount DECIMAL(10, 2) NOT NULL,
  status VARCHAR(50) DEFAULT 'pending',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  total INTEGER
)''',
  '''
CREATE TABLE products (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  category VARCHAR(50),
  price DECIMAL(10, 2) NOT NULL
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
  ('Alice Johnson', 'alice@example.com', true, 'admin', 30, 'active'),
  ('Bob Smith', 'bob@example.com', true, 'user', 45, 'active'),
  ('Charlie Brown', 'charlie@example.com', false, 'user', 22, 'inactive'),
  ('Diana Prince', 'diana@example.com', true, 'moderator', 38, 'active'),
  ('Eve Davis', 'eve@example.com', true, 'user', 51, 'active')''',
  '''
INSERT INTO products (name, category, price) VALUES
  ('Laptop', 'Electronics', 999.99),
  ('Mouse', 'Electronics', 29.99),
  ('Desk Chair', 'Furniture', 199.99),
  ('Monitor', 'Electronics', 299.99),
  ('Keyboard', 'Electronics', 79.99)''',
  // Exactly one row has total > 100: select/alias-map-subquery uses an
  // uncorrelated scalar subquery ("select id from orders where total > 100")
  // as a select-map value, which Postgres rejects if it can return more
  // than one row — found empirically when 3 matching rows broke it.
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

/// Generic join/set-op tables — the corpus's `a`/`b`/`c` cases (union,
/// intersect, except, join predicates) reference these by bare name with
/// no fixed shape of their own. All three share one identical column set
/// (the union of every column any such case references, found by grep, not
/// guessed from a category name) deliberately — several cases do
/// `select(['*'])` on one and UNION/INTERSECT/EXCEPT it against another,
/// which Postgres requires to have matching column counts; giving them
/// different shapes broke exactly that (caught empirically: intersect/basic
/// failed with "each INTERSECT query must have the same number of columns"
/// until a/b were unified). Seeded so `where('x',1)` on a, `where('y',2)`
/// on b, and `where('z',3)` on c each match exactly one row — sets
/// genuinely overlap/differ rather than the query executing against empty
/// results.
const _abcColumns = '''
  id SERIAL PRIMARY KEY,
  a_id INTEGER,
  name VARCHAR(100),
  x INTEGER,
  y INTEGER,
  z INTEGER,
  status VARCHAR(50)
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

/// Generic aggregate/where/having kitchen-sink table — the corpus's `t`
/// cases (agg/*, having/*, where/*, on/*, window/*, jsonb/*) reference a
/// bare `t` with no fixed shape; columns here are the union of every
/// column any such case references. `src` and `inner_t` are two more
/// single-purpose tables referenced by one CTE case and one nested-subquery
/// case respectively.
const syntheticAggregateV1Ddl = <String>[
  '''
CREATE TABLE t (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100),
  amount DECIMAL(10, 2),
  lo INTEGER,
  hi INTEGER,
  cat VARCHAR(50),
  cnt INTEGER,
  views INTEGER,
  score INTEGER,
  age INTEGER,
  a INTEGER,
  b INTEGER,
  c INTEGER,
  d INTEGER,
  x INTEGER,
  status VARCHAR(50),
  email VARCHAR(100),
  deleted_at TIMESTAMP,
  archived_at TIMESTAMP,
  author_id INTEGER,
  category VARCHAR(50),
  tags JSONB
)''',
  '''
CREATE TABLE src (
  id SERIAL PRIMARY KEY,
  flag BOOLEAN
)''',
  '''
CREATE TABLE inner_t (
  id SERIAL PRIMARY KEY,
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
  (true),
  (false)''',
  '''
INSERT INTO inner_t (x) VALUES
  (1),
  (2)''',
];

/// Window-function batch's `accounts` table — every column referenced by
/// any `.table('accounts')` case (found by reading all 16 case bodies, not
/// guessed), plus `user_id` for delete/join-oncallback-where's join against
/// canonical_seed_v2's `users.account_id` (this case needs both profiles
/// applied together). `firstName`/`lastName` are quoted in the DDL to match
/// the camelCase identifiers knex-dart emits verbatim (Postgres folds
/// unquoted identifiers to lowercase, which would otherwise silently
/// resolve to a different, nonexistent column).
const accountsWindowV1Ddl = <String>[
  '''
CREATE TABLE accounts (
  id SERIAL PRIMARY KEY,
  user_id INTEGER,
  email VARCHAR(100),
  "firstName" VARCHAR(100),
  "lastName" VARCHAR(100),
  address VARCHAR(200),
  phone VARCHAR(50),
  salary DECIMAL(10, 2),
  dept VARCHAR(50),
  name VARCHAR(100)
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

const Map<String, ({List<String> ddl, List<String> seed})> postgresFixtureProfiles = {
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
};
