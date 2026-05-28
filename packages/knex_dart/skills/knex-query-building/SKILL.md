---
name: knex-query-building
description: Use when generating SQL with knex_dart query builders: filtering, joins, grouping, CTEs, unions, and SQL inspection.
metadata:
  knex_dart_version: 1.2.0
---

Prefer `KnexQuery` for portable, compile-only examples. It gives you dialect-correct SQL without requiring a live database connection.

```dart
import 'package:knex_dart/knex_dart.dart';

final q = KnexQuery.forDialect(KnexDialect.postgres);
```

## Basic Query Shape

```dart
final sql = q
    .from('users')
    .select(['id', 'email'])
    .where('active', '=', true)
    .orderBy('name')
    .limit(10)
    .toSQL();

print(sql.sql);
print(sql.bindings);  // [true]
```

Use `KnexQuery.forClient('mysql2')` or a different `KnexDialect` when you need another placeholder and quoting style.

## Filtering

```dart
final filtered = q
    .from('users')
    .where('status', '=', 'active')
    .whereIn('role', ['admin', 'moderator'])
    .whereNull('deleted_at')
    .toSQL();

final grouped = q
    .from('users')
    .where((inner) => inner.where('a', '=', 1).orWhere('b', '=', 2))
    .toSQL();

final compared = q
    .from('posts')
    .whereColumn('updated_at', '>', 'created_at')
    .toSQL();
```

Useful helpers:

- `where(...)`, `orWhere(...)`, `whereNot(...)`
- `whereIn(...)`, `whereNotIn(...)`
- `whereNull(...)`, `whereNotNull(...)`
- `whereBetween(...)`, `whereNotBetween(...)`
- `whereColumn(...)`, `orWhereColumn(...)`

## Joins

```dart
final joined = q
    .from('users')
    .leftJoin('orders', 'users.id', 'orders.user_id')
    .select(['users.id', 'orders.id'])
    .toSQL();

final callbackJoin = q
    .from('users')
    .join('orders', (j) {
      j.on('users.id', '=', 'orders.user_id')
       .andOnVal('orders.status', '=', 'completed');
    })
    .toSQL();
```

Prefer the callback form when you need `andOnVal`, `orOn`, `onIn`, or other complex `ON` conditions.

## Aggregation and Grouping

```dart
final grouped = q
    .from('orders')
    .select(['status'])
    .count('id')
    .groupBy('status')
    .havingRaw('count(*) > ?', [5])
    .toSQL();
```

For aliases inside aggregates, prefer raw fragments in the select list:

```dart
final totals = q
    .from('orders')
    .select([q.queryBuilder().client.raw('count(*) as total')])
    .toSQL();
```

## CTEs and Unions

Use `withQuery()` because `with` is a Dart reserved word.

```dart
final cte = q.queryBuilder()
    .withQuery(
      'active_users',
      q.from('users').select(['id', 'name']).where('active', '=', true),
    )
    .from('active_users')
    .select(['id', 'name'])
    .toSQL();

final unioned = q
    .from('employees')
    .select(['name'])
    .union([
      q.from('contractors').select(['name']),
    ])
    .toSQL();
```

`union(...)`, `unionAll(...)`, `intersect(...)`, and `except(...)` all take a list of queries.

## Inspect, Don’t Execute

This skill is about query-building patterns. End examples with `.toSQL()` unless you are using a driver-specific execution API in a separate context.

## Docs

- Where clauses: `https://docs.knex.mahawarkartikey.in/raw/query-building/where-clauses.md`
- Joins: `https://docs.knex.mahawarkartikey.in/raw/query-building/joins.md`
- Subqueries: `https://docs.knex.mahawarkartikey.in/raw/query-building/subqueries.md`
- CTEs: `https://docs.knex.mahawarkartikey.in/raw/query-building/ctes.md`
- Unions: `https://docs.knex.mahawarkartikey.in/raw/query-building/unions.md`
