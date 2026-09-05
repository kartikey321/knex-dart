/// Postgres-specific DDL/seed SQL text for each [FixtureProfileRef] known
/// to `knex_dart_live_test`. Hand-authored here rather than read from
/// `test/integration/sql/postgres_*.sql` at runtime — those files belong to
/// the older hand-written suite; this is the versioned artifact for the
/// live-execution framework, even though the shape currently matches.
library;

const canonicalSeedV1Ddl = <String>[
  '''
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  email VARCHAR(100) UNIQUE NOT NULL,
  active BOOLEAN DEFAULT true,
  role VARCHAR(50),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)''',
  '''
CREATE TABLE orders (
  id SERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
  product_id INTEGER,
  amount DECIMAL(10, 2) NOT NULL,
  status VARCHAR(50) DEFAULT 'pending',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
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
];

const canonicalSeedV1Seed = <String>[
  '''
INSERT INTO users (name, email, active, role) VALUES
  ('Alice Johnson', 'alice@example.com', true, 'admin'),
  ('Bob Smith', 'bob@example.com', true, 'user'),
  ('Charlie Brown', 'charlie@example.com', false, 'user'),
  ('Diana Prince', 'diana@example.com', true, 'moderator'),
  ('Eve Davis', 'eve@example.com', true, 'user')''',
  '''
INSERT INTO products (name, category, price) VALUES
  ('Laptop', 'Electronics', 999.99),
  ('Mouse', 'Electronics', 29.99),
  ('Desk Chair', 'Furniture', 199.99),
  ('Monitor', 'Electronics', 299.99),
  ('Keyboard', 'Electronics', 79.99)''',
  '''
INSERT INTO orders (user_id, product_id, amount, status) VALUES
  (1, 1, 999.99, 'completed'),
  (1, 2, 29.99, 'completed'),
  (2, 3, 199.99, 'pending'),
  (2, 4, 299.99, 'completed'),
  (4, 1, 999.99, 'completed'),
  (4, 5, 79.99, 'completed'),
  (5, 2, 29.99, 'cancelled')''',
];

const ddlEmptyV1Ddl = canonicalSeedV1Ddl;
const ddlEmptyV1Seed = <String>[];

const Map<String, ({List<String> ddl, List<String> seed})> postgresFixtureProfiles = {
  'canonical_seed_v1': (ddl: canonicalSeedV1Ddl, seed: canonicalSeedV1Seed),
  'ddl_empty_v1': (ddl: ddlEmptyV1Ddl, seed: ddlEmptyV1Seed),
};
