# knex_dart

`knex_dart` is the core query builder/compiler. It can generate dialect-correct SQL by itself, but live execution requires a driver package such as `knex_dart_postgres`, `knex_dart_sqlite`, or `knex_dart_mysql`.

## Choose a Mode

### SQL Generation Only

Use `KnexQuery` when you want SQL output without a live database connection:

```dart
import 'package:knex_dart/knex_dart.dart';

final q = KnexQuery.forDialect(KnexDialect.postgres);
final sql = q
    .from('users')
    .select(['id', 'email'])
    .where('active', '=', true)
    .orderBy('name')
    .toSQL();
```

You can also select a dialect by driver name with `KnexQuery.forClient('pg')`, `KnexQuery.forClient('mysql2')`, `KnexQuery.forClient('sqlite3')`, and similar aliases.

### Live Database Execution

Install a driver package and use its typed wrapper:

```dart
import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';

final db = await KnexSQLite.connect(filename: ':memory:');
final rows = await db.select(
  db.queryBuilder()
      .table('users')
      .select(['id', 'name'])
      .where('active', '=', true),
);
```

Supported driver packages:

- `knex_dart_postgres`
- `knex_dart_mysql`
- `knex_dart_sqlite`
- `knex_dart_duckdb`
- `knex_dart_mssql`
- `knex_dart_turso`
- `knex_dart_bigquery`
- `knex_dart_d1`
- `knex_dart_snowflake`

## Safe Cross-Driver Patterns

- Build queries with `queryBuilder().table('...')` or SQL-only `KnexQuery.from('...')`
- Execute writes with `insert`, `update`, `delete`, and reads with `select`
- Use `executeSchema((schema) { ... })` for DDL
- Use `trx(...)` for transactions on live drivers
- Use `.toSQL()` to inspect generated SQL and bindings without executing

If you already have a low-level `Client`, wrap it in `Knex(client)` to use the callable `db('users')` style.

## Raw SQL and Observability

- `db.raw(...)` creates raw SQL fragments across the API surface
- Direct raw execution is driver-specific; check the driver wrapper for the exact method (`raw`, `rawSql`, or both)
- The underlying `Client` exposes `onQuery`, `onQueryError`, and `onQueryResponse` streams for instrumentation

## Installed Skills

This package ships user-facing AI skills. Install them into your workspace with:

```bash
dart run knex_dart:install_skills --agent claude-code
```

Supported agent names currently mirror the Jaspr installer pattern: `claude-code`, `cursor`, `codex`, `cline`, `continue`, `windsurf`, `antigravity`, `copilot`, `command-code`, `opencode`, and `general`.

## Docs

- Main docs: `https://docs.knex.mahawarkartikey.in/`
- AI index: `https://docs.knex.mahawarkartikey.in/llms.txt`
- Raw markdown mirror: `https://docs.knex.mahawarkartikey.in/raw/`

## Common Gotchas

- `knex_dart` itself does not open database connections
- The SQL-only `KnexQuery` APIs are for compilation, not execution
- Transaction APIs live on the driver wrappers as `trx(...)`
- Raw execution method names are not perfectly uniform across all drivers
