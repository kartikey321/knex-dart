---
title: Joins
description: Complete guide to all JOIN types and advanced ON clause conditions in Knex Dart
---

# Joins

Knex Dart supports all standard SQL JOIN types plus an advanced callback-based API for complex ON conditions.

```dart
final db = KnexQuery.forDialect(KnexDialect.postgres);
```

## Simple Join (INNER JOIN)

The simplest form: `join(table, leftColumn, rightColumn)`.

```dart
print(db.from('users').join('orders', 'users.id', 'orders.user_id').toSQL().sql);
// inner join "orders" on "users"."id" = "orders"."user_id"
```

You can also pass an explicit operator:

```dart
print(db.from('users').join('orders', 'users.id', '=', 'orders.user_id').toSQL().sql);
// inner join "orders" on "users"."id" = "orders"."user_id"
```

## LEFT JOIN

```dart
print(db.from('users').leftJoin('orders', 'users.id', 'orders.user_id').toSQL().sql);
// left join "orders" on "users"."id" = "orders"."user_id"
```

## RIGHT JOIN

```dart
print(db.from('orders').rightJoin('users', 'orders.user_id', 'users.id').toSQL().sql);
// right join "users" on "orders"."user_id" = "users"."id"
```

## FULL OUTER JOIN

```dart
print(db.from('users').fullOuterJoin('orders', 'users.id', 'orders.user_id').toSQL().sql);
// full outer join "orders" on "users"."id" = "orders"."user_id"
```

## CROSS JOIN

No ON condition — produces every combination of rows:

```dart
print(db.from('users').crossJoin('roles').toSQL().sql);
// cross join "roles"
```

---

## Lateral Joins

> **Dialect support:** PostgreSQL and MySQL 8+. **Not supported by SQLite.**
>
> Knex.js has no built-in lateral join API; this is a Knex Dart extension.

A lateral join lets the subquery reference columns from tables that appear **earlier** in the `FROM` clause — behaving like a correlated subquery that returns a full row set rather than a scalar. This unlocks patterns like "most recent N rows per group" without a self-join.

### joinLateral

Emits `JOIN LATERAL (…) AS alias ON true`. Rows from the left side that produce no matches in the lateral subquery are excluded.

```dart
final q = db.from('users').joinLateral('latest_order', (sub) {
  sub
    .table('orders')
    .where('orders.user_id', db.queryBuilder().client.raw('"users"."id"'))
    .orderBy('created_at', 'desc')
    .limit(1);
});
print(q.toSQL().sql);
// join lateral (
//   select * from "orders"
//   where "orders"."user_id" = "users"."id"
//   order by "created_at" desc limit 1
// ) as "latest_order" on true
```

### leftJoinLateral

Emits `LEFT JOIN LATERAL (…) AS alias ON true`. Rows from the left side that produce **no** lateral matches are preserved with `NULL` columns — equivalent to `LEFT JOIN` semantics.

```dart
final q = db.from('users').leftJoinLateral('recent_event', (sub) {
  sub
    .table('events')
    .where('events.user_id', db.queryBuilder().client.raw('"users"."id"'))
    .orderBy('occurred_at', 'desc')
    .limit(5);
});
print(q.toSQL().sql);
// left join lateral (...) as "recent_event" on true
```

### crossJoinLateral

Emits `CROSS JOIN LATERAL (…) AS alias` (no `ON` clause). In PostgreSQL this is equivalent to `JOIN LATERAL … ON true`.

```dart
final q = db.from('users').crossJoinLateral('agg', (sub) {
  sub
    .table('orders')
    .where('orders.user_id', db.queryBuilder().client.raw('"users"."id"'))
    .sum('amount as total');
});
print(q.toSQL().sql);
// cross join lateral (...) as "agg"
```

### Subquery forms

All three methods accept the same subquery types:

```dart
// 1. Callback (most common — new QueryBuilder created automatically)
print(db.from('users').joinLateral('lo', (sub) { sub.table('orders').limit(1); }).toSQL().sql);

// 2. Pre-built QueryBuilder
final sub = db.queryBuilder().table('orders').where('user_id', 1).limit(1);
print(db.from('users').joinLateral('lo', sub).toSQL().sql);

// 3. Raw SQL
print(db.from('users').joinLateral('lo', db.queryBuilder().client.raw('select 1 as n')).toSQL().sql);
```

### Parameter binding

Bindings inside the lateral subquery are collected correctly and parameter placeholders are renumbered to follow any outer bindings:

```dart
final q = db.from('users')
  .select(['users.id', 'lo.amount'])
  .leftJoinLateral('lo', (sub) {
    sub.table('orders').where('user_id', 99).orderBy('amount', 'desc').limit(1);
  });
print(q.toSQL().sql);
// Bindings: [99, 1]  (subquery bindings; outer WHERE would follow after)
```

---

## Multiple Joins

Chain as many joins as needed:

```dart
final q = db.from('orders')
  .join('users', 'orders.user_id', 'users.id')
  .join('products', 'orders.product_id', 'products.id')
  .select(['orders.id', 'users.name', 'products.name as product']);
print(q.toSQL().sql);
// select "orders"."id", "users"."name", "products"."name" as "product"
// from "orders"
// inner join "users" on "orders"."user_id" = "users"."id"
// inner join "products" on "orders"."product_id" = "products"."id"
```

---

## Callback-Based Joins

Pass a callback to build complex ON conditions. The callback receives a `JoinClause` object.

### Basic callback

```dart
print(db.from('users').join('orders', (j) {
  j.on('users.id', '=', 'orders.user_id');
}).toSQL().sql);
// inner join "orders" on "users"."id" = "orders"."user_id"
```

### AND ON / OR ON

```dart
print(db.from('users').join('orders', (j) {
  j.on('users.id', '=', 'orders.user_id')
   .andOn('users.region', '=', 'orders.region');   // AND
}).toSQL().sql);

print(db.from('users').leftJoin('orders', (j) {
  j.on('users.id', '=', 'orders.user_id')
   .orOn('users.backup_id', '=', 'orders.user_id'); // OR
}).toSQL().sql);
```

### onVal — bind a literal value

`on()` compares two columns. Use `onVal()` when the right side is a value, not a column:

```dart
print(db.from('users').join('orders', (j) {
  j.on('users.id', '=', 'orders.user_id')
   .andOnVal('orders.status', '=', 'completed');
}).toSQL().sql);
// inner join "orders" on "users"."id" = "orders"."user_id"
//   and "orders"."status" = $1   (binding: 'completed')
```

Available variants: `onVal`, `andOnVal`, `orOnVal`.

### onIn / onNotIn

```dart
print(db.from('users').join('orders', (j) {
  j.on('users.id', '=', 'orders.user_id')
   .andOnIn('orders.status', ['completed', 'shipped']);
}).toSQL().sql);
// and "orders"."status" in ($1, $2)
```

Available variants: `onIn`, `andOnIn`, `orOnIn`, `onNotIn`, `andOnNotIn`, `orOnNotIn`.

### onNull / onNotNull

```dart
print(db.from('users').leftJoin('orders', (j) {
  j.on('users.id', '=', 'orders.user_id')
   .andOnNull('orders.deleted_at');
}).toSQL().sql);
// and "orders"."deleted_at" is null
```

Available variants: `onNull`, `andOnNull`, `orOnNull`, `onNotNull`, `andOnNotNull`, `orOnNotNull`.

### onBetween / onNotBetween

```dart
print(db.from('users').join('orders', (j) {
  j.on('users.id', '=', 'orders.user_id')
   .andOnBetween('orders.amount', [100, 1000]);
}).toSQL().sql);
// and "orders"."amount" between $1 and $2
```

Available variants: `onBetween`, `andOnBetween`, `orOnBetween`, `onNotBetween`.

### onExists

```dart
print(db.from('users').join('accounts', (j) {
  j.on('users.id', '=', 'accounts.user_id')
   .andOnExists((qb) {
     qb.select(['1']).from('subscriptions')
       .whereColumn('subscriptions.account_id', '=', 'accounts.id');
   });
}).toSQL().sql);
```

Available variants: `onExists`, `andOnExists`, `orOnExists`, `onNotExists`.

### USING clause

When both tables share the same column name:

```dart
print(db.from('orders').join('users', (j) => j.using(['user_id'])).toSQL().sql);
// inner join "users" using ("user_id")
```

### onJsonPathEquals (PostgreSQL)

Join on matching JSON path values:

```dart
print(db.from('users').join('settings', (j) {
  j.onJsonPathEquals('users.meta', r'$.region', 'settings.meta', r'$.region');
}).toSQL().sql);
```

---

## Join Type Reference

| Method | SQL emitted | Dialect |
|---|---|---|
| `join(table, col1, col2)` | `INNER JOIN … ON col1 = col2` | All |
| `leftJoin(table, col1, col2)` | `LEFT JOIN … ON col1 = col2` | All |
| `rightJoin(table, col1, col2)` | `RIGHT JOIN … ON col1 = col2` | All |
| `fullOuterJoin(table, col1, col2)` | `FULL OUTER JOIN … ON col1 = col2` | PG, MySQL |
| `crossJoin(table)` | `CROSS JOIN table` | All |
| `joinRaw(sql, bindings)` | Raw SQL join fragment | All |
| `joinLateral(alias, sub)` | `JOIN LATERAL (…) AS alias ON true` | PG, MySQL 8+ |
| `leftJoinLateral(alias, sub)` | `LEFT JOIN LATERAL (…) AS alias ON true` | PG, MySQL 8+ |
| `crossJoinLateral(alias, sub)` | `CROSS JOIN LATERAL (…) AS alias` | PG, MySQL 8+ |

## Complete ON Clause Method Reference

| Method | Description |
|---|---|
| `on(col1, col2)` | AND column = column |
| `andOn(col1, col2)` | AND (alias for `on`) |
| `orOn(col1, col2)` | OR column = column |
| `onVal(col, val)` | AND column = value |
| `andOnVal(col, val)` | AND (alias for `onVal`) |
| `orOnVal(col, val)` | OR column = value |
| `onIn(col, values)` | AND column IN (...) |
| `andOnIn(col, values)` | AND (alias) |
| `orOnIn(col, values)` | OR column IN (...) |
| `onNotIn(col, values)` | AND column NOT IN (...) |
| `onNull(col)` | AND column IS NULL |
| `andOnNull(col)` | AND (alias) |
| `orOnNull(col)` | OR column IS NULL |
| `onNotNull(col)` | AND column IS NOT NULL |
| `onBetween(col, [lo, hi])` | AND column BETWEEN |
| `onNotBetween(col, [lo, hi])` | AND column NOT BETWEEN |
| `onExists(callback)` | AND EXISTS (subquery) |
| `onNotExists(callback)` | AND NOT EXISTS (subquery) |
| `using(columns)` | USING clause |
| `onJsonPathEquals(...)` | JSON path equality |

---

## Real-World Examples

### Users with their latest order

```dart
// Requires a connected driver (e.g. KnexPostgres)
final results = await db.select(
  db.from('users')
    .select(['users.id', 'users.name', 'orders.amount', 'orders.created_at'])
    .leftJoin('orders', (j) {
      j.on('users.id', '=', 'orders.user_id')
       .andOnNull('orders.deleted_at');
    })
    .orderBy('orders.created_at', 'desc'),
);
```

### Products with category filter in join

```dart
// Requires a connected driver (e.g. KnexPostgres)
final results = await db.select(
  db.from('orders')
    .select(['orders.id', 'orders.amount', 'products.name', 'products.category'])
    .join('products', (j) {
      j.on('orders.product_id', '=', 'products.id')
       .andOnVal('products.category', '=', 'Electronics');
    }),
);
```

### Aggregate with LEFT JOIN (count orders per user)

```dart
// Requires a connected driver (e.g. KnexPostgres)
final usersWithOrders = await db.select(
  db.from('users')
    .select(['users.id', 'users.name'])
    .select([db.queryBuilder().client.raw('count(orders.id) as order_count')])
    .leftJoin('orders', 'users.id', 'orders.user_id')
    .groupBy(['users.id', 'users.name'])
    .orderBy('order_count', 'desc'),
);
```

### Most-recent order per user (lateral join)

A lateral subquery is the cleanest way to fetch exactly one correlated row per outer row — no window functions, no subquery in SELECT:

```dart
// PostgreSQL / MySQL 8+
// Requires a connected driver (e.g. KnexPostgres)
final usersWithLatest = await pgClient.select(
  db.from('users')
    .select(['users.id', 'users.name', 'lo.amount', 'lo.created_at'])
    .leftJoinLateral('lo', (sub) {
      sub
        .table('orders')
        .where('orders.user_id', db.queryBuilder().client.raw('"users"."id"'))
        .orderBy('created_at', 'desc')
        .limit(1);
    })
    .orderBy('users.id'),
);
// Equivalent SQL:
// select "users"."id", "users"."name", "lo"."amount", "lo"."created_at"
// from "users"
// left join lateral (
//   select * from "orders"
//   where "orders"."user_id" = "users"."id"
//   order by "created_at" desc
//   limit 1
// ) as "lo" on true
// order by "users"."id" asc
```

Users with no orders still appear in the result (with `null` for `lo.amount` and `lo.created_at`) because of `leftJoinLateral`. Use `joinLateral` to exclude them.

## Next Steps

- [WHERE Clauses](/query-building/where-clauses) — Filtering joined results
- [Subqueries](/query-building/subqueries) — Nested queries in joins
- [CTEs](/query-building/ctes) — Common table expressions
