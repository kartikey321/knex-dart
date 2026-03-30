-- Test data for PostgreSQL integration tests

-- Insert users
INSERT INTO users (name, email, active, role) VALUES
  ('Alice Johnson', 'alice@example.com', true, 'admin'),
  ('Bob Smith', 'bob@example.com', true, 'user'),
  ('Charlie Brown', 'charlie@example.com', false, 'user'),
  ('Diana Prince', 'diana@example.com', true, 'moderator'),
  ('Eve Davis', 'eve@example.com', true, 'user');

-- Insert products
INSERT INTO products (name, category, price) VALUES
  ('Laptop', 'Electronics', 999.99),
  ('Mouse', 'Electronics', 29.99),
  ('Desk Chair', 'Furniture', 199.99),
  ('Monitor', 'Electronics', 299.99),
  ('Keyboard', 'Electronics', 79.99);

-- Insert orders
INSERT INTO orders (user_id, product_id, amount, status) VALUES
  (1, 1, 999.99, 'completed'),
  (1, 2, 29.99, 'completed'),
  (2, 3, 199.99, 'pending'),
  (2, 4, 299.99, 'completed'),
  (4, 1, 999.99, 'completed'),
  (4, 5, 79.99, 'completed'),
  (5, 2, 29.99, 'cancelled');
