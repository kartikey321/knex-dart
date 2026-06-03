---
title: WHERE Clauses
description: Complete guide to all WHERE clause variants in Knex Dart
---

# WHERE Clauses

Knex Dart supports 23 WHERE methods covering the major Knex.js WHERE variants.

## Basic WHERE

```dart
// Simple equality
final db = KnexQuery.forDialect(KnexDialect.postgres);

print(db.from('users').where('name', '=', 'John').toSQL().sql);
// select * from "users" where "name" = $1

// Multiple WHERE (AND)
print(
  db.from('users')
    .where('active', '=', true)
    .where('role', '=', 'admin')
    .toSQL().sql
);
// select * from "users" where "active" = $1 and "role" = $2
```

## OR WHERE

```dart
print(
  db.from('users')
    .where('role', '=', 'admin')
    .orWhere('role', '=', 'moderator')
    .toSQL().sql
);
// select * from "users" where "role" = $1 or "role" = $2
```

## WHERE IN

```dart
// List of values
print(db.from('users').whereIn('id', [1, 2, 3]).toSQL().sql);
// select * from "users" where "id" in ($1, $2, $3)

// Subquery
print(
  db.from('users').whereIn('id',
    db.from('orders').select(['user_id'])
  ).toSQL().sql
);
// select * from "users" where "id" in (select "user_id" from "orders")
```

## WHERE NOT IN

```dart
print(db.from('users').whereNotIn('status', ['banned', 'deleted']).toSQL().sql);
// select * from "users" where "status" not in ($1, $2)

print(db.from('users').where('active', '=', true).orWhereNotIn('id', [1, 2, 3]).toSQL().sql);
// select * from "users" where "active" = $1 or "id" not in ($2, $3, $4)
```

## WHERE NULL

```dart
print(db.from('users').whereNull('deleted_at').toSQL().sql);
// select * from "users" where "deleted_at" is null

print(db.from('users').whereNotNull('email').toSQL().sql);
// select * from "users" where "email" is not null

print(db.from('users').whereNotNull('email').orWhereNull('middle_name').toSQL().sql);
// select * from "users" where "email" is not null or "middle_name" is null
```

## WHERE BETWEEN

```dart
final q = db.from('users').whereBetween('age', [18, 65]).toSQL();
print(q.sql);       // select * from "users" where "age" between $1 and $2
print(q.bindings);  // [18, 65]

print(db.from('users').whereNotBetween('score', [0, 50]).toSQL().sql);
// select * from "users" where "score" not between $1 and $2

print(
  db.from('users')
    .orWhereBetween('created_at', ['2024-01-01', '2024-12-31'])
    .toSQL().sql
);
// select * from "users" or "created_at" between $1 and $2
```

## WHERE COLUMN

Compare two columns:

```dart
print(db.from('users').whereColumn('updated_at', '>', 'created_at').toSQL().sql);
// select * from "users" where "updated_at" > "created_at"

print(db.from('users').orWhereColumn('first_name', '=', 'last_name').toSQL().sql);
// select * from "users" or "first_name" = "last_name"
```

## WHERE NOT

```dart
print(db.from('users').whereNot('status', '=', 'deleted').toSQL().sql);
// select * from "users" where not "status" = $1

print(db.from('users').orWhereNot('active', '=', false).toSQL().sql);
// select * from "users" or not "active" = $1
```

## WHERE EXISTS

Check for existence of subquery results:

```dart
print(
  db.from('users').whereExists(
    db.from('orders')
      .select([db.queryBuilder().client.raw('1')])
      .whereColumn('orders.user_id', '=', 'users.id')
  ).toSQL().sql
);
// select * from "users" where exists (select 1 from "orders" where "orders"."user_id" = "users"."id")

print(
  db.from('users').whereNotExists(
    db.from('orders').select([db.queryBuilder().client.raw('1')])
  ).toSQL().sql
);
// select * from "users" where not exists (select 1 from "orders")
```

## WHERE WRAPPED

Group conditions:

```dart
print(
  db.from('users').whereWrapped((qb) {
    qb.where('role', '=', 'admin')
      .orWhere('role', '=', 'moderator');
  }).where('active', '=', true).toSQL().sql
);
// select * from "users" where ("role" = $1 or "role" = $2) and "active" = $3
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
print(db.from('users').where('email', 'like', '%@gmail.com').toSQL().sql);
// select * from "users" where "email" like $1
```

## Full-Text Search (whereFullText)

Cross-dialect full text search. Compiles down to `to_tsvector` in PostgreSQL, `MATCH AGAINST` in MySQL, and `MATCH` in SQLite.

```dart
print(db.from('articles').whereFullText(['title', 'body'], 'flutter dart').toSQL().sql);
// PG: select * from "articles" where to_tsvector("title" || ' ' || "body") @@ to_tsquery($1)
// MySQL: select * from "articles" where match("title", "body") against($1)
// SQLite: select * from "articles" where "articles" match $1
```

## JSON Operators (PostgreSQL)

If using the PostgresClient, you can use Native JSON operators:

```dart
print(db.from('users').whereJsonObject('metadata', {'theme': 'dark'}).toSQL().sql);
// select * from "users" where "metadata" @> $1::jsonb AND "metadata" <@ $1::jsonb

print(db.from('users').whereJsonPath('metadata', r'$.name', 'John').toSQL().sql);
// select * from "users" where jsonb_path_query_first("metadata", $1) = $2

print(db.from('users').whereJsonSupersetOf('roles', ['admin', 'user']).toSQL().sql);
// select * from "users" where "roles" @> $1::jsonb

print(db.from('users').whereJsonSubsetOf('roles', ['superadmin', 'admin', 'user']).toSQL().sql);
// select * from "users" where "roles" <@ $1::jsonb
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
| `whereFullText()` | Full-Text search match |
| `orWhereFullText()` | OR Full-Text search |
| `whereJsonObject()` | Match JSON object exactly |
| `whereJsonPath()` | Query JSON by path |
| `whereJsonSupersetOf()` | JSON Superset (`@>`) |
| `whereJsonSubsetOf()` | JSON Subset (`<@`) |

**Total: 29 WHERE methods** providing complete flexibility for query filtering.
