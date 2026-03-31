---
title: Quick Start
description: Connect to a database and build your first queries with Knex Dart
---

# Quick Start

Learn the basics of Knex Dart in a few minutes.

## Query Builder Only (No Connection)

If you only need SQL generation — for testing, logging, or ORM layers — use `KnexQuery` from the core package. No driver required.

```bash
dart pub add knex_dart
```

```dart
import 'package:knex_dart/knex_dart.dart';
import 'package:knex_dart_capabilities/knex_dart_capabilities.dart';

// Target any dialect — produces dialect-correct SQL without a live connection
final q = KnexQuery.forDialect(KnexDialect.postgres);

final result = q.from('users')
    .select(['id', 'email'])
    .where('active', '=', true)
    .orderBy('name')
    .toSQL();

print(result.sql);       // select "id", "email" from "users" where "active" = $1 order by "name" asc
print(result.bindings);  // [true]
```

Or by driver name (knex.js-style):

```dart
final q = KnexQuery.forClient('mysql2');

final result = q.from('orders')
    .where('status', '=', 'open')
    .toSQL();

print(result.sql);  // select * from `orders` where `status` = ?
```

Supported dialect strings: `pg`, `postgres`, `mysql`, `mysql2`, `sqlite3`, `mariadb`, `duckdb`, `snowflake`, `bigquery`, `turso`, `d1`, `redshift`.

---

## 1) Connect to a Database

Each database has its own driver package with a typed connect factory.

### SQLite (no server required)

```dart
import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';

final db = await KnexSQLite.connect(filename: ':memory:');
```

### PostgreSQL

```dart
import 'package:knex_dart_postgres/knex_dart_postgres.dart';

final db = await KnexPostgres.connect(
  host: 'localhost',
  port: 5432,
  database: 'myapp',
  username: 'user',
  password: 'pass',
);
```

### MySQL

```dart
import 'package:knex_dart_mysql/knex_dart_mysql.dart';

final db = await KnexMySQL.connect(
  host: 'localhost',
  port: 3306,
  database: 'myapp',
  user: 'user',
  password: 'pass',
);
```

### DuckDB (OLAP / Analytics)

```dart
import 'package:knex_dart_duckdb/knex_dart_duckdb.dart';

// In-memory (no server required)
final db = await KnexDuckDB.memory();

// Or file-backed
final db = await KnexDuckDB.file('/path/to/analytics.db');
```

DuckDB also runs in the **browser via WASM** — the same API works on native and web platforms.

See [Database Support](/database-support) for all 9 supported databases.

---

## 2) Build and Execute Queries

```dart
// SELECT
final users = await db.select(
  db('users')
    .select(['id', 'name', 'email'])
    .where('active', '=', true)
    .orderBy('name')
    .limit(10),
);

// INSERT
await db.insert(
  db('users').insert({'name': 'Alice', 'email': 'alice@example.com'}),
);

// UPDATE
await db.update(
  db('users').where('id', '=', 1).update({'name': 'Bob'}),
);

// DELETE
await db.delete(
  db('users').where('id', '=', 1).delete(),
);
```

## 3) Inspect Generated SQL

Call `.toSQL()` on any query builder to see the SQL and bindings without executing:

```dart
final q = db('users')
    .select(['id', 'name'])
    .where('active', '=', true)
    .orderBy('name')
    .limit(10);

print(q.toSQL().sql);
// select "id", "name" from "users" where "active" = ? order by "name" asc limit ?

print(q.toSQL().bindings);
// [true, 10]
```

## 4) Joins

```dart
db('users').join('orders', (j) {
  j.on('users.id', '=', 'orders.user_id')
   .andOnVal('orders.status', '=', 'completed')
   .andOnIn('orders.type', ['online', 'retail'])
   .orOnNull('orders.deleted_at');
});
```

## 5) Schema Builder

```dart
await db.executeSchema(
  db.schema.createTable('users', (t) {
    t.increments('id');
    t.string('name').notNullable();
    t.string('email').unique();
    t.boolean('active').defaultTo(true);
    t.timestamps();
  }),
);
```

## 6) Transactions

```dart
await db.trx((trx) async {
  final id = await trx.insert(
    trx('accounts').insert({'owner': 'Alice', 'balance': 500}),
  );
  await trx.update(
    trx('ledger').insert({'account_id': id, 'amount': 500}),
  );
});
```

## 7) Cleanup

```dart
await db.destroy();
```

## Next Steps

- [Database Support](/database-support) — Connection examples for all 9 databases
- [WHERE Clauses](/query-building/where-clauses) — All 29 filtering methods
- [Joins](/query-building/joins) — INNER, LEFT, RIGHT, FULL OUTER, LATERAL
- [Transactions](/query-building/transactions) — Atomic operations and nested savepoints
- [Streaming](/connections/streaming) — Memory-efficient large result sets
- [Examples](/examples/basic-queries)
