---
title: Quick Start
description: Connect to a database and build your first queries with Knex Dart
---

# Quick Start

Learn the basics of Knex Dart in a few minutes.

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

## 2) Build and Execute Queries

`db` is a callable — `db('table')` returns a `QueryBuilder`.

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

## 3) Generate SQL Without Executing

Call `.toSQL()` on any query builder to inspect the SQL and bindings:

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

- [WHERE Clauses](/query-building/where-clauses)
- [Subqueries](/query-building/subqueries)
- [CTEs (WITH)](/query-building/ctes)
- [UNION / INTERSECT / EXCEPT](/query-building/unions)
- [Examples](/examples/basic-queries)
