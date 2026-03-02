---
title: Database Support
description: Supported databases and how to connect to each
---

# Database Support

Each database is a separate driver package. Install only what you need.

## Supported Databases

| Database | Package | Version | Status |
|---|---|---|---|
| PostgreSQL | `knex_dart_postgres` | `^0.1.0` | Available |
| MySQL | `knex_dart_mysql` | `^0.1.0` | Available |
| SQLite | `knex_dart_sqlite` | `^0.1.0` | Available |

## PostgreSQL

```dart
import 'package:knex_dart_postgres/knex_dart_postgres.dart';

final db = await KnexPostgres.connect(
  host: 'localhost',
  port: 5432,
  database: 'myapp',
  username: 'user',
  password: 'pass',
);

final rows = await db.select(
  db('users').where('active', '=', true),
);

await db.destroy();
```

**PostgreSQL-specific features:**
- `$1, $2, ...` positional placeholders
- `RETURNING` clause support
- JSON operators (`whereJsonPath`, `whereJsonSupersetOf`, `whereJsonSubsetOf`)
- Full-text search with language option

## MySQL

```dart
import 'package:knex_dart_mysql/knex_dart_mysql.dart';

final db = await KnexMySQL.connect(
  host: 'localhost',
  port: 3306,
  database: 'myapp',
  user: 'user',
  password: 'pass',
);

final rows = await db.select(
  db('users').where('active', '=', true),
);

await db.destroy();
```

**MySQL-specific features:**
- `?` positional placeholders
- Backtick identifier quoting
- Full-text search with `IN BOOLEAN MODE` / `IN NATURAL LANGUAGE MODE`

## SQLite

```dart
import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';

// File-based
final db = await KnexSQLite.connect(filename: 'app.db');

// In-memory
final db = await KnexSQLite.connect(filename: ':memory:');

final rows = await db.select(
  db('users').where('active', '=', true),
);

await db.destroy();
```

**SQLite-specific features:**
- `?` positional placeholders
- Double-quoted identifier quoting
- In-memory database support
- JSON via `json_extract()`

## Query Builder Only (No Connection)

Use `knex_dart` directly when you only need SQL generation — no driver required:

```dart
import 'package:knex_dart/knex_dart.dart';

final db = Knex(MockClient());

final result = db('users')
  .select(['id', 'name'])
  .where('active', '=', true)
  .toSQL();

print(result.sql);       // select "id", "name" from "users" where "active" = ?
print(result.bindings);  // [true]
```

Useful for testing, SQL snapshots, and compiler verification.

## Limitations (Current)

- Connection pooling is implemented for PostgreSQL and MySQL drivers.
- Nested/savepoint transaction semantics are implemented across PostgreSQL, MySQL, and SQLite.

## Additional Databases (Not Yet Supported)

### CockroachDB
**Status:** Under consideration — uses the PostgreSQL wire protocol, so support may come through the PostgreSQL driver with minimal changes.

### Microsoft SQL Server
**Status:** Blocked — no mature pure-Dart TDS driver exists. You can still generate MSSQL-dialect SQL with the query builder and execute it through a custom client.

### Oracle
**Status:** Evaluation phase — depends on `oraffi` package maturity.
