---
title: Quick Start
description: Build your first queries with Knex Dart
---

# Quick Start

Learn the basics of Knex Dart in 5 minutes.

## Basic SELECT

```dart
import 'package:knex_dart/knex_dart.dart';

void main() {
  final knex = Knex(client: MockClient());
  
  // Simple SELECT
  final query = knex('users').select(['id', 'name', 'email']);
  
  print(query.toSQL().sql);
  // select "id", "name", "email" from "users"
}
```

## WHERE Clauses

```dart
// Basic WHERE
knex('users')
  .select(['*'])
  .where('active', '=', true)
  .where('role', '=', 'admin');
// select * from "users" where "active" = $1 and "role" = $2

// WHERE IN
knex('users')
  .select(['*'])
  .whereIn('id', [1, 2, 3]);
// select * from "users" where "id" in ($1, $2, $3)

// WHERE BETWEEN
knex('users')
  .select(['*'])
  .whereBetween('age', [18, 65]);
// select * from "users" where "age" between $1 and $2
```

## JOINs

```dart
// INNER JOIN
knex('users')
  .select(['users.*', 'orders.total'])
  .join('orders', 'users.id', 'orders.user_id');
// select "users".*, "orders"."total" from "users" 
// inner join "orders" on "users"."id" = "orders"."user_id"

// LEFT JOIN
knex('users')
  .select(['*'])
  .leftJoin('orders', 'users.id', 'orders.user_id');
```

## INSERT

```dart
// Single row
knex('users').insert({
  'name': 'John Doe',
  'email': 'john@example.com',
  'age': 30
});
// insert into "users" ("name", "email", "age") values ($1, $2, $3)

// Multiple rows
knex('users').insert([
  {'name': 'John', 'age': 30},
  {'name': 'Jane', 'age': 25}
]);
// insert into "users" ("name", "age") values ($1, $2), ($3, $4)

// With RETURNING (PostgreSQL)
knex('users').insert({'name': 'John'}).returning(['id', 'name']);
// insert into "users" ("name") values ($1) returning "id", "name"
```

## UPDATE

```dart
knex('users')
  .update({'name': 'Jane Doe'})
  .where('id', '=', 1);
// update "users" set "name" = $1 where "id" = $2

// Increment
knex('users')
  .increment('login_count', 1)
  .where('id', '=', 1);
// update "users" set "login_count" = "login_count" + $1 where "id" = $2
```

## DELETE

```dart
knex('users')
  .delete()
  .where('active', '=', false);
// delete from "users" where "active" = $1
```

## Aggregates

```dart
knex('orders')
  .count('* as total')
  .sum('amount as revenue')
  .groupBy('status');
// select count(*) as "total", sum("amount") as "revenue" 
// from "orders" group by "status"
```

## Subqueries

```dart
// WHERE IN subquery
knex('users').whereIn('id',
  knex('orders').select(['user_id']).where('total', '>', 1000)
);
// select * from "users" where "id" in 
// (select "user_id" from "orders" where "total" > $1)
```

## Next Steps

- [WHERE Clauses](/query-building/where-clauses) - All 23 methods
- [Subqueries](/query-building/subqueries) - Complex nested queries
- [CTEs (WITH)](/query-building/ctes) - WITH clauses
- [UNION](/query-building/unions) - Combine queries
- [Examples](/examples/basic-queries) - Real-world examples
