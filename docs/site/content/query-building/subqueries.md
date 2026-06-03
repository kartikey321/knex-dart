---
title: Subqueries
description: Use subqueries in WHERE, FROM, and SELECT clauses
---

# Subqueries

Knex Dart supports subqueries in multiple locations, just like Knex.js.

```dart
final db = KnexQuery.forDialect(KnexDialect.postgres);
```

## WHERE IN Subquery

Use a query as the value for `whereIn`:

```dart
final q = db.from('users').whereIn('id',
  db.from('orders')
    .select(['user_id'])
    .where('total', '>', 1000)
);
print(q.toSQL().sql);
// select * from "users" where "id" in
// (select "user_id" from "orders" where "total" > $1)
```

## WHERE NOT IN Subquery

```dart
final q = db.from('users').whereNotIn('id',
  db.from('banned_users').select(['user_id'])
);
print(q.toSQL().sql);
// select * from "users" where "id" not in
// (select "user_id" from "banned_users")
```

## FROM Subquery

Use a subquery as a table source:

```dart
final sub = db.from('orders')
    .groupBy('user_id')
    .select(['user_id', db.queryBuilder().client.raw('count(*) as order_count')])
    .as('grouped');

print(db.queryBuilder().from(sub).select(['*']).toSQL().sql);
// select * from (
//   select "user_id", count(*) as order_count
//   from "orders" group by "user_id"
// ) as "grouped"
```

## SELECT Subquery

Include a subquery in the select list:

```dart
final orderCount = db.from('orders')
    .count('* as count')
    .whereColumn('orders.user_id', '=', 'users.id')
    .as('order_count');

print(db.from('users').select(['name', orderCount]).toSQL().sql);
// select "name", (
//   select count(*) as "count" from "orders"
//   where "orders"."user_id" = "users"."id"
// ) as "order_count" from "users"
```

## Nested Subqueries

Subqueries can be nested:

```dart
final q = db.from('users').whereIn('id',
  db.from('orders')
    .select(['user_id'])
    .whereIn('product_id',
      db.from('products')
        .select(['id'])
        .where('category', '=', 'Electronics')
    )
);
print(q.toSQL().sql);
// select * from "users" where "id" in (
//   select "user_id" from "orders" where "product_id" in (
//     select "id" from "products" where "category" = $1
//   )
// )
```

## Subquery with Aggregates

```dart
final q = db.from('users')
  .select(['name'])
  .where('id', '=',
    db.from('orders')
      .select(['user_id'])
      .sum('amount as total')
      .groupBy('user_id')
      .orderBy('total', 'desc')
      .limit(1)
  );
print(q.toSQL().sql);
```

## Aliasing Subqueries

Always alias subqueries in FROM and SELECT:

```dart
// FROM subquery - must have alias
final sub = db.from('orders').select(['*']).as('sub');
print(db.queryBuilder().from(sub).select(['*']).toSQL().sql);

// SELECT subquery - must have alias
final count = db.from('orders').count('*').as('count');
print(db.from('users').select(['name', count]).toSQL().sql);
```

## Parameter Handling

Knex Dart automatically:
- Renumbers parameters in nested queries
- Merges bindings from all levels
- Maintains correct parameter sequence

```dart
// Automatic parameter renumbering
final q = db.from('users')
  .where('active', '=', true)  // $1
  .whereIn('id',
    db.from('orders')
      .select(['user_id'])
      .where('status', '=', 'completed')  // $2 (not $1!)
  );
print(q.toSQL().sql);
// Bindings: [true, 'completed']
```

## Next Steps

- [CTEs](/query-building/ctes) - Alternative to complex subqueries
- [UNION](/query-building/unions) - Combine query results
- [Examples](/examples/basic-queries) - Real-world subquery patterns
