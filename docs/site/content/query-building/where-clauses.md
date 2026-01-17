---
title: WHERE Clauses
description: Complete guide to all WHERE clause variants in Knex Dart
---

# WHERE Clauses

Knex Dart supports all 16 WHERE clause variants from Knex.js.

## Basic WHERE

```dart
// Simple equality
knex('users').where('name', '=', 'John');
// where "name" = $1

// Multiple WHERE (AND)
knex('users')
  .where('active', '=', true)
  .where('role', '=', 'admin');
// where "active" = $1 and "role" = $2
```

## OR WHERE

```dart
knex('users')
  .where('role', '=', 'admin')
  .orWhere('role', '=', 'moderator');
// where "role" = $1 or "role" = $2
```

## WHERE IN

```dart
// List of values
knex('users').whereIn('id', [1, 2, 3]);
// where "id" in ($1, $2, $3)

// Subquery
knex('users').whereIn('id',
  knex('orders').select(['user_id'])
);
// where "id" in (select "user_id" from "orders")
```

## WHERE NOT IN

```dart
knex('users').whereNotIn('status', ['banned', 'deleted']);
// where "status" not in ($1, $2)

knex('users').orWhereNotIn('id', [1, 2, 3]);
// or "id" not in ($1, $2, $3)
```

## WHERE NULL

```dart
knex('users').whereNull('deleted_at');
// where "deleted_at" is null

knex('users').whereNotNull('email');
// where "email" is not null

knex('users').orWhereNull('middle_name');
// or "middle_name" is null
```

## WHERE BETWEEN

```dart
knex('users').whereBetween('age', [18, 65]);
// where "age" between $1 and $2

knex('users').whereNotBetween('score', [0, 50]);
// where "score" not between $1 and $2

knex('users').orWhereBetween('created_at', ['2024-01-01', '2024-12-31']);
// or "created_at" between $1 and $2
```

## WHERE COLUMN

Compare two columns:

```dart
knex('users').whereColumn('updated_at', '>', 'created_at');
// where "updated_at" > "created_at"

knex('users').orWhereColumn('first_name', '=', 'last_name');
// or "first_name" = "last_name"
```

## WHERE NOT

```dart
knex('users').whereNot('status', '=', 'deleted');
// where not "status" = $1

knex('users').orWhereNot('active', '=', false);
// or not "active" = $1
```

## WHERE EXISTS

Check for existence of subquery results:

```dart
knex('users').whereExists(
  knex('orders')
    .select([client.raw('1')])
    .whereColumn('orders.user_id', '=', 'users.id')
);
// where exists (select 1 from "orders" where "orders"."user_id" = "users"."id")

knex('users').whereNotExists(
  knex('orders').select([client.raw('1')])
);
// where not exists (select 1 from "orders")
```

## WHERE WRAPPED

Group conditions:

```dart
knex('users').whereWrapped((qb) {
  qb.where('role', '=', 'admin')
    .orWhere('role', '=', 'moderator');
}).where('active', '=', true);
// where ("role" = $1 or "role" = $2) and "active" = $3
```

## Operators

Supported operators:
- `=` - Equals
- `!=` - Not equals
- `<>` - Not equals (SQL standard)
- `<` - Less than
- `<=` - Less than or equal
- `>` - Greater than
- `>=` - Greater than or equal
- `like` - Pattern matching
- `ilike` - Case-insensitive pattern matching (PostgreSQL)

```dart
knex('users').where('email', 'like', '%@gmail.com');
// where "email" like $1
```

## All WHERE Methods

| Method | Description |
|--------|-------------|
| `where()` | Basic WHERE |
| `orWhere()` | OR condition |
| `whereIn()` | IN list/subquery |
| `whereNotIn()` | NOT IN |
| `orWhereIn()` | OR IN |
| `orWhereNotIn()` | OR NOT IN |
| `whereNull()` | IS NULL |
| `whereNotNull()` | IS NOT NULL |
| `orWhereNull()` | OR IS NULL |
| `orWhereNotNull()` | OR IS NOT NULL |
| `whereBetween()` | BETWEEN |
| `whereNotBetween()` | NOT BETWEEN |
| `orWhereBetween()` | OR BETWEEN |
| `orWhereNotBetween()` | OR NOT BETWEEN |
| `whereColumn()` | Compare columns |
| `orWhereColumn()` | OR column comparison |
| `whereNot()` | NOT condition |
| `orWhereNot()` | OR NOT |
| `whereExists()` | EXISTS subquery |
| `whereNotExists()` | NOT EXISTS |
| `orWhereExists()` | OR EXISTS |
| `orWhereNotExists()` | OR NOT EXISTS |
| `whereWrapped()` | Grouped conditions |

**Total: 23 WHERE methods** providing complete flexibility for query filtering.
