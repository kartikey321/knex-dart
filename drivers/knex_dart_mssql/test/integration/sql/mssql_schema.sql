IF DB_ID(N'knex_test') IS NULL
BEGIN
  CREATE DATABASE knex_test;
END
GO

USE knex_test;
GO

IF OBJECT_ID(N'dbo.orders', N'U') IS NOT NULL
  DROP TABLE dbo.orders;
GO

IF OBJECT_ID(N'dbo.users', N'U') IS NOT NULL
  DROP TABLE dbo.users;
GO

CREATE TABLE dbo.users (
  id INT IDENTITY(1,1) PRIMARY KEY,
  name NVARCHAR(255) NOT NULL,
  email NVARCHAR(255),
  role NVARCHAR(50) DEFAULT 'user',
  score FLOAT,
  active BIT DEFAULT 1
);
GO

CREATE TABLE dbo.orders (
  id INT IDENTITY(1,1) PRIMARY KEY,
  user_id INT,
  amount FLOAT,
  status NVARCHAR(50)
);
GO
