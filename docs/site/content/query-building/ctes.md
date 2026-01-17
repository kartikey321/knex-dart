---
title: CTEs (Common Table Expressions)
description: Use WITH clauses to simplify complex queries
---

# CTEs (Common Table Expressions)

Common Table Expressions (CTEs) allow you to break down complex queries into named, reusable subqueries.

## Basic CTE

```dart
knex.withQuery('regional_sales',
  knex('orders')
    .select(['region'])
    .sum('amount as total_sales')
    .groupBy('region')
)
.select(['*'])
.from('regional_sales');
// with "regional_sales" as (
//   select "region", sum("amount") as "total_sales" 
//   from "orders" group by "region"
// )
// select * from "regional_sales"
```

> **Note:** Dart uses `withQuery()` instead of `with()` because `with` is a reserved keyword.

## Multiple CTEs

Chain multiple `withQuery()` calls:

```dart
knex
  .withQuery('monthly_sales',
    knex('orders')
      .select(['month', 'sum(amount) as total'])
      .groupBy('month')
  )
  .withQuery('avg_monthly',
    knex('monthly_sales')
      .select(['avg(total) as average'])
  )
  .select(['*'])
  .from('monthly_sales')
  .crossJoin('avg_monthly');
// with "monthly_sales" as (...),
//      "avg_monthly" as (...)
// select * from "monthly_sales" cross join "avg_monthly"
```

## Recursive CTE

For hierarchical data (trees, graphs, etc.):

```dart
final recursive = knex('nodes')
  .select(['*'])
  .where('parent_id', '=', null)
  .union([
    knex('nodes as n')
      .select(['n.*'])
      .join('tree as t', 'n.parent_id', 't.id')
  ]);

knex.withRecursive('tree', recursive)
  .select(['*'])
  .from('tree');
// with recursive "tree" as (
//   select * from "nodes" where "parent_id" is null
//   union
//   select "n".* from "nodes" as "n" 
//   inner join "tree" as "t" on "n"."parent_id" = "t"."id"
// )
// select * from "tree"
```

## CTE with Raw SQL

```dart
knex.withQuery('sales',
  client.raw('select * from orders where status = ?', ['completed'])
)
.select(['*'])
.from('sales');
```

## Using CTEs in WHERE

```dart
knex
  .withQuery('active_users',
    knex('users').select(['*']).where('active', '=', true)
  )
  .select(['id', 'name'])
  .from('active_users')
  .where('role', '=', 'admin');
// with "active_users" as (
//   select * from "users" where "active" = $1
// )
// select "id", "name" from "active_users" where "role" = $2
```

## Benefits of CTEs

### 1. Readability
Break complex queries into logical steps:

```dart
// Instead of nested subqueries...
knex('users').whereIn('id',
  knex('orders').whereIn('product_id',
    knex('products').select(['id'])
  ).select(['user_id'])
);

// Use CTEs for clarity:
knex
  .withQuery('electronics',
    knex('products').select(['id']).where('category', '=', 'Electronics')
  )
  .withQuery('electronics_orders',
    knex('orders').whereIn('product_id',
      knex.from('electronics').select(['id'])
    )
  )
  .select(['*'])
  .from('users')
  .whereIn('id',
    knex.from('electronics_orders').select(['user_id'])
  );
```

### 2. Reusability
Reference the same CTE multiple times:

```dart
knex
  .withQuery('high_value_orders',
    knex('orders').select(['*']).where('amount', '>', 1000)
  )
  .select([
    client.raw('count(distinct user_id) as customers'),
    client.raw('sum(amount) as revenue')
  ])
  .from('high_value_orders');
```

### 3. Performance
PostgreSQL can materialize CTEs for optimization.

## Recursive CTE Examples

### Organization Hierarchy

```dart
final recursive = knex('employees')
  .select(['id', 'name', 'manager_id', client.raw('1 as level')])
  .where('manager_id', '=', null)
  .union([
    knex('employees as e')
      .select(['e.id', 'e.name', 'e.manager_id', client.raw('o.level + 1')])
      .join('org_tree as o', 'e.manager_id', 'o.id')
  ]);

knex.withRecursive('org_tree', recursive)
  .select(['*'])
  .from('org_tree')
  .orderBy('level');
```

### Graph Traversal

```dart
final paths = knex('edges')
  .select(['source', 'target', client.raw('ARRAY[source, target] as path')])
  .where('source', '=', startNode)
  .union([
    knex('edges as e')
      .select(['e.source', 'e.target', client.raw('p.path || e.target')])
      .join('paths as p', 'p.target', 'e.source')
      .where(client.raw('NOT e.target = ANY(p.path)'))  // Avoid cycles
  ]);

knex.withRecursive('paths', paths)
  .select(['*'])
  .from('paths');
```

## CTE vs Subqueries

| Feature | CTE | Subquery |
|---------|-----|----------|
| Readability | ✅ Excellent | ⚠️ Can be complex |
| Reusability | ✅ Yes | ❌ No |
| Recursive | ✅ Yes | ❌ No |
| Performance | ≈ Similar | ≈ Similar |

Choose CTEs for:
- Complex queries with multiple steps
- Queries that reference the same data multiple times
- Recursive operations

Choose subqueries for:
- Simple, one-time use
- Single-level nesting

## Next Steps

- [UNION](/query-building/unions) - Combine results
- [Subqueries](/query-building/subqueries) - Nested queries
- [Examples](/examples/basic-queries) - Real-world CTE patterns
