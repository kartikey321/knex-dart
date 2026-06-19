# knex_dart

A faithful port of [Knex.js](https://knexjs.org/) to Dart — a powerful, fluent SQL query builder supporting 9 databases.

[![Pub Version](https://img.shields.io/pub/v/knex_dart)](https://pub.dev/packages/knex_dart)
[![codecov](https://codecov.io/gh/kartikey321/knex-dart/branch/main/graph/badge.svg)](https://codecov.io/gh/kartikey321/knex-dart)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

## Packages

| Package | Description | Version |
|---|---|---|
| [knex_dart](https://pub.dev/packages/knex_dart) | Core query builder (this package) | [![pub](https://img.shields.io/pub/v/knex_dart)](https://pub.dev/packages/knex_dart) |
| [knex_dart_postgres](https://pub.dev/packages/knex_dart_postgres) | PostgreSQL driver | [![pub](https://img.shields.io/pub/v/knex_dart_postgres)](https://pub.dev/packages/knex_dart_postgres) |
| [knex_dart_mysql](https://pub.dev/packages/knex_dart_mysql) | MySQL driver | [![pub](https://img.shields.io/pub/v/knex_dart_mysql)](https://pub.dev/packages/knex_dart_mysql) |
| [knex_dart_sqlite](https://pub.dev/packages/knex_dart_sqlite) | SQLite driver | [![pub](https://img.shields.io/pub/v/knex_dart_sqlite)](https://pub.dev/packages/knex_dart_sqlite) |
| [knex_dart_duckdb](https://pub.dev/packages/knex_dart_duckdb) | DuckDB driver (OLAP + WASM) | [![pub](https://img.shields.io/pub/v/knex_dart_duckdb)](https://pub.dev/packages/knex_dart_duckdb) |
| [knex_dart_mssql](https://pub.dev/packages/knex_dart_mssql) | Microsoft SQL Server driver | [![pub](https://img.shields.io/pub/v/knex_dart_mssql)](https://pub.dev/packages/knex_dart_mssql) |
| [knex_dart_bigquery](https://pub.dev/packages/knex_dart_bigquery) | Google BigQuery driver | [![pub](https://img.shields.io/pub/v/knex_dart_bigquery)](https://pub.dev/packages/knex_dart_bigquery) |
| [knex_dart_snowflake](https://pub.dev/packages/knex_dart_snowflake) | Snowflake driver | [![pub](https://img.shields.io/pub/v/knex_dart_snowflake)](https://pub.dev/packages/knex_dart_snowflake) |
| [knex_dart_turso](https://pub.dev/packages/knex_dart_turso) | Turso (libSQL) driver | [![pub](https://img.shields.io/pub/v/knex_dart_turso)](https://pub.dev/packages/knex_dart_turso) |
| [knex_dart_d1](https://pub.dev/packages/knex_dart_d1) | Cloudflare D1 driver | [![pub](https://img.shields.io/pub/v/knex_dart_d1)](https://pub.dev/packages/knex_dart_d1) |
| [knex_dart_capabilities](https://pub.dev/packages/knex_dart_capabilities) | Shared dialect capability matrix | [![pub](https://img.shields.io/pub/v/knex_dart_capabilities)](https://pub.dev/packages/knex_dart_capabilities) |
| [knex_dart_lint](https://pub.dev/packages/knex_dart_lint) | Optional static dialect lint plugin | [![pub](https://img.shields.io/pub/v/knex_dart_lint)](https://pub.dev/packages/knex_dart_lint) |
| [knex_dart_otel](https://pub.dev/packages/knex_dart_otel) | OpenTelemetry query instrumentation | [![pub](https://img.shields.io/pub/v/knex_dart_otel)](https://pub.dev/packages/knex_dart_otel) |

`knex_dart` is the core package — query builder, schema builder, and compiler with no database connectivity. Add the driver for your database.

## Documentation

Full documentation: **https://docs.knex.mahawarkartikey.in/**

Try queries in the browser playground: **https://playground.knex.mahawarkartikey.in/**

- [Database Support](https://docs.knex.mahawarkartikey.in/database-support) — all 9 databases with connection examples
- [WHERE Clauses](https://docs.knex.mahawarkartikey.in/query-building/where-clauses) — 29 filtering methods
- [Joins](https://docs.knex.mahawarkartikey.in/query-building/joins) — INNER, LEFT, RIGHT, FULL OUTER, LATERAL
- [Window Functions](https://docs.knex.mahawarkartikey.in/query-building/window-functions) — RANK, LEAD, LAG, frame clauses
- [Transactions](https://docs.knex.mahawarkartikey.in/query-building/transactions) — atomic operations + nested savepoints
- [Streaming](https://docs.knex.mahawarkartikey.in/connections/streaming) — memory-efficient large result sets
- [Migrations](https://docs.knex.mahawarkartikey.in/migration/migrations) — code-first and SQL-directory sources
- [Dialect Lint](https://docs.knex.mahawarkartikey.in/tooling/dialect-lint) — optional static analysis plugin
- [OpenTelemetry](https://docs.knex.mahawarkartikey.in/tooling/opentelemetry) — query spans and DB client duration metrics

## Installation

Add the driver for your database — it pulls in `knex_dart` automatically:

```yaml
dependencies:
  knex_dart_postgres: ^0.3.1   # PostgreSQL
  # knex_dart_mysql: ^0.3.1    # MySQL
  # knex_dart_sqlite: ^0.4.0   # SQLite
  # knex_dart_duckdb: ^0.2.1   # DuckDB (OLAP / browser WASM)
```

For SQL generation only (no live connection):

```yaml
dependencies:
  knex_dart: ^1.3.0
  knex_dart_capabilities: ^0.3.0
```

## Quick Start

### PostgreSQL

```dart
import 'package:knex_dart_postgres/knex_dart_postgres.dart';

final db = await KnexPostgres.connect(
  host: 'localhost',
  database: 'mydb',
  username: 'user',
  password: 'pass',
);

final users = await db.select(
  db('users').where('active', '=', true).limit(10),
);

await db.destroy();
```

### SQLite

<!-- doc:run scope=local expect_stdout='Alice' -->
```dart
import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';

final db = await KnexSQLite.connect(filename: ':memory:');

await db.executeSchema(
  (schema) {
    schema.createTable('users', (t) {
      t.increments('id');
      t.string('name');
    });
  },
);

await db.insert(db('users').insert({'name': 'Alice'}));
final rows = await db.select(db('users').select(['name']));
print(rows.first['name']);
await db.close();
```

### DuckDB (OLAP / Browser WASM)

```dart
import 'package:knex_dart_duckdb/knex_dart_duckdb.dart';

final db = await KnexDuckDB.memory();  // or KnexDuckDB.file('path.db')

final result = await db.select(
  db.queryBuilder()
    .from('sales')
    .sum('amount as total')
    .groupBy('region'),
);

await db.close();
```

DuckDB runs natively on macOS/Linux/Windows and in the **browser via WASM** — same API on both platforms.

### Query Builder Only (No Connection)

Generate dialect-correct SQL without any driver installed:

```dart
import 'package:knex_dart/knex_dart.dart';
import 'package:knex_dart_capabilities/knex_dart_capabilities.dart';

// PostgreSQL — double-quoted identifiers, $1 placeholders
final q = KnexQuery.forDialect(KnexDialect.postgres);
print(q.from('users').where('active', '=', true).toSQL().sql);
// select * from "users" where "active" = $1

// MySQL — backtick identifiers, ? placeholders
final q2 = KnexQuery.forClient('mysql2');
print(q2.from('users').where('active', '=', true).toSQL().sql);
// select * from `users` where `active` = ?
```

Supported dialects: `pg`, `mysql2`, `sqlite3`, `duckdb`, `snowflake`, `bigquery`, `turso`, `d1`, `mariadb`, `redshift`.

## Query Builder

### SELECT

```dart
db('users').select(['id', 'name']).where('active', '=', true);

// Joins
db('users')
  .join('orders', 'users.id', '=', 'orders.user_id')
  .select(['users.name', 'orders.total'])
  .where('orders.status', '=', 'completed');

// Aggregates
db('sales')
  .count('* as total')
  .sum('amount as revenue')
  .where('status', '=', 'completed');

// LATERAL join (PostgreSQL / MySQL 8+)
db('users').leftJoinLateral('latest', (sub) {
  sub.table('orders')
    .where('orders.user_id', db.queryBuilder().client.raw('"users"."id"'))
    .orderBy('created_at', 'desc')
    .limit(1);
});
```

### INSERT / UPDATE / DELETE

```dart
db('users').insert({'name': 'Alice', 'email': 'alice@example.com'});

db('users').where('id', '=', 1).update({'name': 'Bob'});

db('users').where('id', '=', 1).delete();

// Upsert
db('users')
  .insert({'email': 'alice@example.com', 'name': 'Alice'})
  .onConflict('email')
  .merge();
```

### Advanced

```dart
// CTEs
db('active_users')
  .withRecursive('active_users', db('users').where('active', '=', true))
  .select(['*']);

// Window functions
db.queryBuilder()
  .table('employees')
  .select(['id', 'department', 'salary'])
  .rowNumber('row_num', (a) => a.partitionBy('department').orderBy('salary', 'desc'))
  .lead('next_salary', 'salary', 'salary', 'department');

// Raw SQL execution on driver wrappers
await db.rawSql('select * from users where id = ?', [1]);
```

### Schema Builder

```dart
await db.executeSchema(
  (schema) {
    schema.createTable('posts', (t) {
      t.increments('id');
      t.string('title').notNullable();
      t.text('body');
      t.integer('user_id').references('id').inTable('users');
      t.timestamps();
    });
  },
);
```

### Transactions

```dart
await db.trx((trx) async {
  await trx.insert(trx('accounts').insert({'balance': 100}));
  await trx.update(trx('accounts').where('id', '=', 1).update({'balance': 0}));
});
```

Nested transactions use savepoints automatically:

```dart
await db.trx((outer) async {
  await outer.insert(outer('accounts').insert({'owner': 'Alice', 'balance': 1000}));

  try {
    await outer.trx((inner) async {
      await inner.insert(inner('accounts').insert({'owner': 'Bob', 'balance': 500}));
      throw Exception('rollback inner only');
    });
  } catch (_) {}

  // Alice's row committed; Bob's row rolled back
});
```

### Streaming

```dart
final stream = db.streamQuery(
  db('events').where('processed', '=', false).orderBy('id'),
);

await for (final row in stream) {
  await handleEvent(row);
}
```

Supported on PostgreSQL, MySQL, SQLite, and DuckDB.

### Migrations

```dart
// Code-first
await db.migrate.fromCode([
  const SqlMigration(
    name: '001_create_users',
    upSql: ['create table users (id integer primary key, email varchar(255))'],
    downSql: ['drop table users'],
  ),
]).latest();

// SQL directory (*.up.sql / *.down.sql files)
await db.migrate.fromSqlDir('./migrations').latest();
```

### Optional Dialect Lint Plugin

`knex_dart_lint` provides static diagnostics for dialect-incompatible API usage:

```yaml
dev_dependencies:
  custom_lint: ^0.8.1
  knex_dart_lint: ^0.3.0
```

```yaml
# analysis_options.yaml
analyzer:
  plugins:
    - custom_lint
```

Catches: `.returning()` on MySQL/SQLite, `fullOuterJoin()` on MySQL/SQLite, `joinLateral()` on SQLite, `.onConflict().merge()` on unsupported dialects.

## Features

- SELECT, INSERT, UPDATE, DELETE
- 29 WHERE methods — basic, IN, NULL, BETWEEN, EXISTS, OR, JSON, full-text
- JOINs — INNER, LEFT, RIGHT, FULL OUTER, CROSS, LATERAL
- Aggregates — COUNT, SUM, AVG, MIN, MAX with DISTINCT variants
- Window functions — `rowNumber`, `rank`, `denseRank`, `lead`, `lag`, `firstValue`, `lastValue`, `nthValue` + frame clauses
- CTEs — `WITH` and `WITH RECURSIVE`
- UNION, INTERSECT, EXCEPT (with ALL variants)
- Subqueries in WHERE IN, FROM, and SELECT
- Upserts — `onConflict().merge()`
- Schema builder — createTable, alterTable, dropTable, foreign keys, indexes
- Transactions + nested savepoints on PostgreSQL, MySQL, SQLite, DuckDB
- Streaming — `streamQuery()` for memory-efficient large result sets
- Connection pooling — `PoolConfig` for PostgreSQL and MySQL
- Migrations — code-first, SQL-directory, and JSON-schema sources
- OpenTelemetry instrumentation — driver wrapper query spans, stream spans, transaction query spans, and `db.client.operation.duration`
- Dialect-aware SQL — correct quoting and placeholders per database
- `KnexQuery.forDialect()` — generate SQL for any dialect without a driver
- Browser playground — Dart LSP diagnostics, hover, auto-import, embedded PostgreSQL/SQLite execution
- Web/WASM — DuckDB runs in Chrome/headless browser
- 591+ tests, >85% line coverage

## Side-by-Side: Knex.js vs knex_dart

**Knex.js**
```javascript
knex('users')
  .select('name', 'email')
  .where('age', '>', 18)
  .orderBy('created_at', 'desc')
  .limit(10);
```

**knex_dart**
```dart
db('users')
  .select(['name', 'email'])
  .where('age', '>', 18)
  .orderBy('created_at', 'desc')
  .limit(10);
```

## Acknowledgments

This project is a port of [Knex.js](https://knexjs.org/), created by Tim Griesser and contributors.

## License

MIT — see [LICENSE](LICENSE).
