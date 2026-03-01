---
title: Write Operations
description: Guide to Insert, Update, Delete and Upsert (ON CONFLICT) in Knex Dart
---

# Write Operations

Knex Dart supports standard ANSI SQL write operations along with dialect-specific extensions like PostgreSQL's `RETURNING` clause and Upsert (`ON CONFLICT`).

## Insert

```dart
// Basic Insert
knex('users').insert({
  'name': 'John',
  'email': 'john@example.com'
});
// insert into "users" ("name", "email") values ($1, $2)

// Batch Insert
knex('users').insert([
  {'name': 'Alice'},
  {'name': 'Bob'}
]);
// insert into "users" ("name") values ($1), ($2)
```

## Update

```dart
knex('users')
  .where('id', '=', 1)
  .update({'name': 'Jane'});
// update "users" set "name" = $1 where "id" = $2
```

## Delete

```dart
knex('users')
  .where('status', '=', 'banned')
  .delete();
// delete from "users" where "status" = $1
```

## Returning (PostgreSQL)

You can chain `.returning()` to get back the inserted/updated rows in PostgreSQL.

```dart
knex('users')
  .insert({'name': 'John'})
  .returning(['id', 'name']);
// insert into "users" ("name") values ($1) returning "id", "name"
```

## Upsert (ON CONFLICT)

Knex Dart provides `onConflict()` to handle insert collisions elegantly natively.

```dart
// ON CONFLICT (email) DO UPDATE SET name = EXCLUDED.name
knex('users')
  .insert({
    'name': 'Updated Name',
    'email': 'john@example.com'
  })
  .onConflict('email')
  .merge(['name']);

// ON CONFLICT (email) DO NOTHING
knex('users')
  .insert({
    'name': 'Duplicate',
    'email': 'john@example.com'
  })
  .onConflict('email')
  .ignore();
```

*Note: The generated SQL automatically adapts to dialect equivalents, e.g. `ON DUPLICATE KEY UPDATE` for MySQL.*
