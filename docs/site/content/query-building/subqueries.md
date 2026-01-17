---
title: Subqueries
description: Use subqueries in WHERE, FROM, and SELECT clauses
---

# Subqueries

Knex Dart supports subqueries in multiple locations, just like Knex.js.

## WHERE IN Subquery

Use a query as the value for `whereIn`:

```dart
knex('users').whereIn('id',
  knex('orders')
    .select(['user_id'])
    .where('total', '>', 1000)
);
// select * from "users" where "id" in 
// (select "user_id" from "orders" where "total" > $1)
```

## WHERE NOT IN Subquery

```dart
knex('users').whereNotIn('id',
  knex('banned_users').select(['user_id'])
);
// select * from "users" where "id" not in 
// (select "user_id" from "banned_users")
```

## FROM Subquery

Use a subquery as a table source:

```dart
final subquery = knex('orders')
  .groupBy('user_id')
  .select(['user_id', client.raw('count(*) as order_count')])
  .as('grouped');

knex.from(subquery)
  .select(['*']);
// select * from (
//   select "user_id", count(*) as order_count 
//   from "orders" group by "user_id"
// ) as "grouped"
```

## SELECT Subquery

Include a subquery in the select list:

```dart
final orderCount = knex('orders')
  .count('* as count')
  .whereColumn('orders.user_id', '=', 'users.id')
  .as('order_count');

knex('users')
  .select(['name', orderCount]);
// select "name", (
//   select count(*) as "count" from "orders" 
//   where "orders"."user_id" = "users"."id"
// ) as "order_count" from "users"
```

## Nested Subqueries

Subqueries can be nested:

```dart
knex('users').whereIn('id',
  knex('orders')
    .select(['user_id'])
    .whereIn('product_id',
      knex('products')
        .select(['id'])
        .where('category', '=', 'Electronics')
    )
);
// select * from "users" where "id" in (
//   select "user_id" from "orders" where "product_id" in (
//     select "id" from "products" where "category" = $1
//   )
// )
```

## Subquery with Aggregates

```dart
knex('users')
  .select(['name'])
  .where('id', '=',
    knex('orders')
      .select(['user_id'])
      .sum('amount as total')
      .groupBy('user_id')
      .orderBy('total', 'desc')
      .limit(1)
  );
```

## Aliasing Subqueries

Always alias subqueries in FROM and SELECT:

```dart
// FROM subquery - must have alias
final sub = knex('orders').select(['*']).as('sub');
knex.from(sub).select(['*']);

// SELECT subquery - must have alias
final count = knex('orders').count('*').as('count');
knex('users').select(['name', count]);
```

## Complete Example

```dart
// Find users who have spent more than average
final avgSpending = knex('orders')
  .avg('amount as average')
  .as('avg_order');

final subquery = knex('orders')
  .select(['user_id'])
  .sum('amount as total')
  .groupBy('user_id')
  .having(client.raw('sum(amount) > ?', [
    knex.raw('(select average from avg_order)')
  ]))
  .as('big_spenders');

knex('users')
  .with('avg_order', avgSpending)
  .whereIn('id', knex.from(subquery).select(['user_id']));
```

## Parameter Handling

Knex Dart automatically:
- ✅ Renumbers parameters in nested queries
- ✅ Merges bindings from all levels
- ✅ Maintains correct parameter sequence

```dart
// Automatic parameter renumbering
knex('users')
  .where('active', '=', true)  // $1
  .whereIn('id',
    knex('orders')
      .select(['user_id'])
      .where('status', '=', 'completed')  // $2 (not $1!)
  );
// Bindings: [true, 'completed']
```

## Next Steps

- [CTEs](/query-building/ctes) - Alternative to complex subqueries
- [UNION](/query-building/unions) - Combine query results
- [Examples](/examples/basic-queries) - Real-world subquery patterns
