---
title: Database Support
description: Current database support and runtime limitations
---

# Database Support

Knex Dart supports both:

- SQL generation via query builder/compiler
- query execution through current PostgreSQL, MySQL, and SQLite wrappers

## Current Runtime Status

| Database | Status | Entry Point |
|---------|--------|-------------|
| PostgreSQL | Available | `await Knex.postgres(...)` |
| MySQL | Available | `await Knex.mysql(...)` |
| SQLite | Available | `await Knex.sqlite(filename: ...)` |

## Query Builder (Compile-Only Mode)

```dart
final knex = Knex(KnexConfig(
  client: 'sqlite3',
  connection: {'filename': ':memory:'},
));

final sql = knex('users')
  .select(['id', 'name'])
  .where('active', '=', true)
  .toSQL();

// sql.sql: select "id", "name" from "users" where "active" = $1
// sql.bindings: [true]
```

Use this mode for parity tests, SQL snapshots, and compiler verification.

## Executing Queries (Runtime Wrappers)

### PostgreSQL

```dart
final db = await Knex.postgres(
  host: 'localhost',
  database: 'app',
  username: 'user',
  password: 'pass',
);

final rows = await db.select(
  db.table('users').where('active', '=', true),
);

await db.close();
```

### MySQL

```dart
final db = await Knex.mysql(
  host: 'localhost',
  user: 'root',
  password: 'pass',
  database: 'app',
);

final rows = await db.select(
  db.table('users').where('active', '=', true),
);

await db.close();
```

### SQLite

```dart
final db = await Knex.sqlite(filename: 'app.db');

final rows = await db.select(
  db.queryBuilder().table('users').where('active', '=', true),
);

await db.close();
```

## Important Limitations (Current)

- Connection pooling is not implemented yet.
- Runtime wrappers are separate from `Knex(KnexConfig)` for PostgreSQL/MySQL.
  - `Knex(KnexConfig)` is currently wired for SQLite dialect creation path.
- Transaction APIs exist, but advanced parity features (nested/savepoint semantics) are still in progress.
- Some advanced Knex.js APIs are still being ported.

## Additional Databases (Not Implemented Yet)

### CockroachDB

**Status:** Under consideration  
**Compatibility:** PostgreSQL protocol

CockroachDB uses the PostgreSQL wire protocol. Support expected through PostgreSQL driver.

### Amazon Redshift

**Status:** Under consideration  
**Compatibility:** PostgreSQL-based

Redshift compatibility expected through PostgreSQL driver with potential dialect adjustments.

### Microsoft SQL Server

**Status:** Not currently planned  
**Package:** No production-ready driver available

MSSQL support blocked by lack of stable Dart drivers. Experimental packages exist but are not production-ready.

Technical limitations:
- No mature pure Dart driver
- FFI-based drivers require native dependencies
- TDS protocol implementation incomplete

Alternative:
- Generate SQL with query builder, execute with custom driver implementation.

### Oracle Database

**Status:** Evaluation phase  
**Package:** `oraffi` (new package, requires testing)

Oracle support depends on `oraffi` package maturity.

Current status:
- New Oracle driver package available
- Integration complexity assessment needed
- Production readiness to be determined

Next steps:
- Evaluate `oraffi` stability
- Test query compatibility
- Assess enterprise requirements

## Practical Recommendation

- Use query-builder mode for compile/parity tests.
- Use `Knex.postgres`, `Knex.mysql`, `Knex.sqlite` for execution.
- Treat runtime layer as active but still evolving.
