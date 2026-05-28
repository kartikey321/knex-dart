---
title: Write Operations
description: Guide to Insert, Update, Delete and Upsert (ON CONFLICT) in Knex Dart
---

# Write Operations

Knex Dart supports standard ANSI SQL write operations along with dialect-specific extensions like PostgreSQL's `RETURNING` clause and Upsert (`ON CONFLICT`).

## Insert

```dart
// Basic Insert
final db = KnexQuery.forDialect(KnexDialect.postgres);

final insert = db.from('users').insert({
  'name': 'John',
  'email': 'john@example.com'
}).toSQL();
print(insert.sql);
// insert into "users" ("name", "email") values ($1, $2)
print(insert.bindings);
// [John, john@example.com]

// Batch Insert
print(
  db.from('users').insert([
    {'name': 'Alice'},
    {'name': 'Bob'}
  ]).toSQL().sql
);
// insert into "users" ("name") values ($1), ($2)
```

## Update

```dart
final update = db.from('users')
  .where('id', '=', 1)
  .update({'name': 'Jane'})
  .toSQL();
print(update.sql);
// update "users" set "name" = $1 where "id" = $2
print(update.bindings);
// [Jane, 1]
```

## Delete

```dart
print(
  db.from('users')
    .where('status', '=', 'banned')
    .delete()
    .toSQL().sql
);
// delete from "users" where "status" = $1
```

## Returning (PostgreSQL)

You can chain `.returning()` to get back the inserted/updated rows in PostgreSQL.

```dart
print(
  db.from('users')
    .insert({'name': 'John'})
    .returning(['id', 'name'])
    .toSQL().sql
);
// insert into "users" ("name") values ($1) returning "id", "name"
```

## Upsert (ON CONFLICT)

Knex Dart provides `onConflict()` to handle insert collisions elegantly natively.

```dart
// ON CONFLICT (email) DO UPDATE SET name = EXCLUDED.name
print(
  db.from('users')
    .insert({
      'name': 'Updated Name',
      'email': 'john@example.com'
    })
    .onConflict('email')
    .merge(['name'])
    .toSQL().sql
);
// insert into "users" ("name", "email") values ($1, $2) on conflict ("email") do update set "name" = excluded."name"

// ON CONFLICT (email) DO NOTHING
print(
  db.from('users')
    .insert({
      'name': 'Duplicate',
      'email': 'john@example.com'
    })
    .onConflict('email')
    .ignore()
    .toSQL().sql
);
// insert into "users" ("name", "email") values ($1, $2) on conflict ("email") do nothing
```

*Note: The generated SQL automatically adapts to dialect equivalents, e.g. `ON DUPLICATE KEY UPDATE` for MySQL.*
