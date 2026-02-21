---
title: Quick Start
description: Build your first queries with Knex Dart
---

# Quick Start

Learn the basics of Knex Dart in a few minutes.

## 1) Build SQL with QueryBuilder

```dart
import 'package:knex_dart/knex_dart.dart';

void main() {
  final knex = Knex(KnexConfig(
    client: 'sqlite3',
    connection: {'filename': ':memory:'},
  ));

  final query = knex('users')
      .select(['id', 'name', 'email'])
      .where('active', true)
      .orderBy('name')
      .limit(10);

  final sql = query.toSQL();
  print(sql.sql);
  print(sql.bindings);
}
```

## 2) Useful Query Methods

```dart
// first()
knex('users').first('id');

// pluck()
knex('users').pluck('email');

// Lock/wait modes
knex('users').forUpdate().skipLocked();
knex('users').forShare().noWait();
```

## 3) JOINs (including advanced callback clauses)

```dart
knex('users').join('orders', (j) {
  j.on('users.id', 'orders.user_id')
   .andOnVal('orders.status', '=', 'completed')
   .andOnIn('orders.type', ['online', 'retail'])
   .orOnNull('orders.deleted_at');
});
```

## 4) Execute Against a Real Database

Use async wrappers for runtime execution.

### PostgreSQL

```dart
final db = await Knex.postgres(
  host: 'localhost',
  database: 'app',
  username: 'user',
  password: 'pass',
);

final rows = await db.select(
  db.table('users').where('active', true),
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
  db.table('users').where('active', true),
);

await db.close();
```

### SQLite

```dart
final db = await Knex.sqlite(filename: 'app.db');

final rows = await db.select(
  db.queryBuilder().table('users').where('active', true),
);

await db.close();
```

## Next Steps

- [WHERE Clauses](/query-building/where-clauses)
- [Subqueries](/query-building/subqueries)
- [CTEs (WITH)](/query-building/ctes)
- [UNION](/query-building/unions)
- [Examples](/examples/basic-queries)
