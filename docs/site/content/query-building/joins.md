---
title: Joins
description: Complete guide to all JOIN types and advanced ON clause conditions in Knex Dart
---

# Joins

Knex Dart supports all standard SQL JOIN types plus an advanced callback-based API for complex ON conditions.

## Simple Join (INNER JOIN)

The simplest form: `join(table, leftColumn, rightColumn)`.

```dart
db('users').join('orders', 'users.id', 'orders.user_id');
// inner join "orders" on "users"."id" = "orders"."user_id"
```

You can also pass an explicit operator:

```dart
db('users').join('orders', 'users.id', '=', 'orders.user_id');
```

## LEFT JOIN

```dart
db('users').leftJoin('orders', 'users.id', 'orders.user_id');
// left join "orders" on "users"."id" = "orders"."user_id"
```

## RIGHT JOIN

```dart
db('orders').rightJoin('users', 'orders.user_id', 'users.id');
// right join "users" on "orders"."user_id" = "users"."id"
```

## FULL OUTER JOIN

```dart
db('users').fullOuterJoin('orders', 'users.id', 'orders.user_id');
// full outer join "orders" on "users"."id" = "orders"."user_id"
```

## CROSS JOIN

No ON condition — produces every combination of rows:

```dart
db('users').crossJoin('roles');
// cross join "roles"
```

## Multiple Joins

Chain as many joins as needed:

```dart
db('orders')
  .join('users', 'orders.user_id', 'users.id')
  .join('products', 'orders.product_id', 'products.id')
  .select(['orders.id', 'users.name', 'products.name as product']);
```

---

## Callback-Based Joins

Pass a callback to build complex ON conditions. The callback receives a `JoinClause` object.

### Basic callback

```dart
db('users').join('orders', (j) {
  j.on('users.id', '=', 'orders.user_id');
});
// inner join "orders" on "users"."id" = "orders"."user_id"
```

### AND ON / OR ON

```dart
db('users').join('orders', (j) {
  j.on('users.id', '=', 'orders.user_id')
   .andOn('users.region', '=', 'orders.region');   // AND
});

db('users').leftJoin('orders', (j) {
  j.on('users.id', '=', 'orders.user_id')
   .orOn('users.backup_id', '=', 'orders.user_id'); // OR
});
```

### onVal — bind a literal value

`on()` compares two columns. Use `onVal()` when the right side is a value, not a column:

```dart
db('users').join('orders', (j) {
  j.on('users.id', '=', 'orders.user_id')
   .andOnVal('orders.status', '=', 'completed');
});
// inner join "orders" on "users"."id" = "orders"."user_id"
//   and "orders"."status" = $1   (binding: 'completed')
```

Available variants: `onVal`, `andOnVal`, `orOnVal`.

### onIn / onNotIn

```dart
db('users').join('orders', (j) {
  j.on('users.id', '=', 'orders.user_id')
   .andOnIn('orders.status', ['completed', 'shipped']);
});
// and "orders"."status" in ($1, $2)
```

Available variants: `onIn`, `andOnIn`, `orOnIn`, `onNotIn`, `andOnNotIn`, `orOnNotIn`.

### onNull / onNotNull

```dart
db('users').leftJoin('orders', (j) {
  j.on('users.id', '=', 'orders.user_id')
   .andOnNull('orders.deleted_at');
});
// and "orders"."deleted_at" is null
```

Available variants: `onNull`, `andOnNull`, `orOnNull`, `onNotNull`, `andOnNotNull`, `orOnNotNull`.

### onBetween / onNotBetween

```dart
db('users').join('orders', (j) {
  j.on('users.id', '=', 'orders.user_id')
   .andOnBetween('orders.amount', [100, 1000]);
});
// and "orders"."amount" between $1 and $2
```

Available variants: `onBetween`, `andOnBetween`, `orOnBetween`, `onNotBetween`.

### onExists

```dart
db('users').join('accounts', (j) {
  j.on('users.id', '=', 'accounts.user_id')
   .andOnExists((qb) {
     qb.select(['1']).from('subscriptions')
       .whereColumn('subscriptions.account_id', '=', 'accounts.id');
   });
});
```

Available variants: `onExists`, `andOnExists`, `orOnExists`, `onNotExists`.

### USING clause

When both tables share the same column name:

```dart
db('orders').join('users', (j) => j.using(['user_id']));
// inner join "users" using ("user_id")
```

### onJsonPathEquals (PostgreSQL)

Join on matching JSON path values:

```dart
db('users').join('settings', (j) {
  j.onJsonPathEquals('users.meta', r'$.region', 'settings.meta', r'$.region');
});
```

---

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
final results = await db.select(
  db('users')
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
final results = await db.select(
  db('orders')
    .select(['orders.id', 'orders.amount', 'products.name', 'products.category'])
    .join('products', (j) {
      j.on('orders.product_id', '=', 'products.id')
       .andOnVal('products.category', '=', 'Electronics');
    }),
);
```

### Aggregate with LEFT JOIN (count orders per user)

```dart
final usersWithOrders = await db.select(
  db('users')
    .select(['users.id', 'users.name'])
    .select([db.raw('count(orders.id) as order_count')])
    .leftJoin('orders', 'users.id', 'orders.user_id')
    .groupBy(['users.id', 'users.name'])
    .orderBy('order_count', 'desc'),
);
```

## Next Steps

- [WHERE Clauses](/query-building/where-clauses) — Filtering joined results
- [Subqueries](/query-building/subqueries) — Nested queries in joins
- [CTEs](/query-building/ctes) — Common table expressions
