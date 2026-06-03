---
name: knex-mutations
description: Use when writing INSERT, UPDATE, DELETE, or conflict-handling queries with knex_dart.
metadata:
  knex_dart_version: 1.2.1
---

This skill covers write operations. Use `KnexQuery.forDialect(...)` for compile-only examples, and a driver wrapper (`KnexPostgres`, `KnexSQLite`, etc.) when you need to execute against a real database.

## INSERT

```dart
final q = KnexQuery.forDialect(KnexDialect.postgres);

// Single row
final insert1 = q
    .from('users')
    .insert({'name': 'Alice', 'email': 'alice@example.com'})
    .toSQL();

// Bulk insert
final insert2 = q
    .from('users')
    .insert([
      {'name': 'Alice', 'email': 'alice@example.com'},
      {'name': 'Bob',   'email': 'bob@example.com'},
    ])
    .toSQL();

// RETURNING (PostgreSQL and SQLite only)
final insert3 = q
    .from('users')
    .insert({'name': 'Alice'})
    .returning(['id', 'name'])
    .toSQL();
```

## ON CONFLICT

Chain `.onConflict(...)` immediately after `.insert(...)`.

```dart
// Do nothing on conflict
final upsert1 = q
    .from('users')
    .insert({'email': 'alice@example.com', 'name': 'Alice'})
    .onConflict('email')
    .ignore()
    .toSQL();

// Upsert — update all non-conflict columns
final upsert2 = q
    .from('users')
    .insert({'email': 'alice@example.com', 'name': 'Alice'})
    .onConflict('email')
    .merge()
    .toSQL();

// Upsert — update specific columns only
final upsert3 = q
    .from('users')
    .insert({'email': 'alice@example.com', 'name': 'Alice'})
    .onConflict('email')
    .merge(['name'])
    .toSQL();

// Composite conflict target
final upsert4 = q
    .from('event_attendees')
    .insert({'event_id': 1, 'user_id': 42})
    .onConflict(['event_id', 'user_id'])
    .ignore()
    .toSQL();
```

## UPDATE

Always add a `.where(...)` clause unless you intend to update every row.

```dart
final update = q
    .from('users')
    .where('id', '=', 1)
    .update({'name': 'Alicia', 'updated_at': DateTime.now().toIso8601String()})
    .toSQL();

// UPDATE … RETURNING (PostgreSQL / SQLite)
final updateReturning = q
    .from('users')
    .where('active', '=', false)
    .update({'active': true})
    .returning(['id'])
    .toSQL();
```

## DELETE

```dart
final delete = q
    .from('users')
    .where('id', '=', 1)
    .delete()
    .toSQL();

// DELETE … RETURNING (PostgreSQL / SQLite)
final deleteReturning = q
    .from('sessions')
    .where('expired_at', '<', DateTime.now().toIso8601String())
    .delete()
    .returning(['id', 'user_id'])
    .toSQL();
```

## INCREMENT / DECREMENT

```dart
final inc = q
    .from('posts')
    .where('id', '=', 1)
    .increment('views')
    .toSQL(); // UPDATE posts SET views = views + 1 WHERE id = ?

final dec = q
    .from('inventory')
    .where('product_id', '=', 99)
    .decrement('stock', 5)
    .toSQL(); // UPDATE inventory SET stock = stock - 5 WHERE product_id = ?
```

## Executing with a Driver

Driver wrappers expose dedicated methods that return `List<Map<String, dynamic>>` (RETURNING rows or an empty list).

```dart
import 'package:knex_dart_postgres/knex_dart_postgres.dart';

final db = await KnexPostgres.connect(
  host: 'localhost', port: 5432,
  database: 'myapp', username: 'user', password: 'pass',
);

// Insert and retrieve returned id
final rows = await db.insert(
  db.queryBuilder()
    .table('users')
    .insert({'name': 'Alice', 'email': 'alice@example.com'})
    .returning(['id']),
);
final newId = rows.first['id'];

// Update
await db.update(
  db.queryBuilder()
    .table('users')
    .where('id', '=', newId)
    .update({'name': 'Alicia'}),
);

// Delete
await db.delete(
  db.queryBuilder()
    .table('users')
    .where('id', '=', newId)
    .delete(),
);
```

## Rules

- `.returning()` is PostgreSQL and SQLite only. Omit it for MySQL, MSSQL, BigQuery.
- `.onConflict()` requires PostgreSQL (`ON CONFLICT`) or SQLite (`ON CONFLICT` clause); not available on MySQL 5.x.
- Omitting `.where()` on an UPDATE or DELETE affects every row — do this intentionally, never accidentally.

## Docs

- Write operations: `https://docs.knex.mahawarkartikey.in/raw/query-building/write-operations.md`
- Schema builder: `https://docs.knex.mahawarkartikey.in/raw/query-building/schema-builder.md`
