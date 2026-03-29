USE knex_test;
GO

DELETE FROM dbo.orders;
DELETE FROM dbo.users;
GO

INSERT INTO dbo.users (name, email, role, score, active) VALUES
  (N'Alice', N'alice@example.com', N'admin', 91.2, 1),
  (N'Bob', N'bob@example.com', N'user', 72.4, 1),
  (N'Carol', N'carol@example.com', N'user', 63.8, 0);
GO

INSERT INTO dbo.orders (user_id, amount, status) VALUES
  (1, 120.50, N'open'),
  (2, 42.00, N'closed'),
  (1, 9.99, N'pending');
GO
