---
title: CTEs (Common Table Expressions)
description: Use WITH clauses to simplify complex queries
---

# CTEs (Common Table Expressions)

Common Table Expressions (CTEs) allow you to break down complex queries into named, reusable subqueries.

## Basic CTE

```dart
final db = KnexQuery.forDialect(KnexDialect.postgres);

final q = db.queryBuilder()
    .withQuery('regional_sales',
      db.from('orders')
        .select(['region'])
        .sum('amount as total_sales')
        .groupBy('region')
    )
    .from('regional_sales')
    .select(['*'])
    .toSQL();
print(q.sql);
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
final q = db.queryBuilder()
    .withQuery('monthly_sales',
      db.from('orders')
        .select(['month', db.queryBuilder().client.raw('sum(amount) as total')])
        .groupBy('month')
    )
    .withQuery('avg_monthly',
      db.from('monthly_sales')
        .select([db.queryBuilder().client.raw('avg(total) as average')])
    )
    .from('monthly_sales')
    .crossJoin('avg_monthly')
    .select(['*'])
    .toSQL();
print(q.sql);
// with "monthly_sales" as (...),
//      "avg_monthly" as (...)
// select * from "monthly_sales" cross join "avg_monthly"
```

## Recursive CTE

For hierarchical data (trees, graphs, etc.):

```dart
final recursive = db.from('nodes')
    .select(['*'])
    .where('parent_id', '=', null)
    .union([
      db.from('nodes as n')
        .select(['n.*'])
        .join('tree as t', 'n.parent_id', 't.id')
    ]);

final q = db.queryBuilder()
    .withRecursive('tree', recursive)
    .from('tree')
    .select(['*'])
    .toSQL();
print(q.sql);
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
final q = db.queryBuilder()
    .withQuery('sales',
      db.queryBuilder().client.raw('select * from orders where status = ?', ['completed'])
    )
    .from('sales')
    .select(['*'])
    .toSQL();
print(q.sql);
```

## Using CTEs in WHERE

```dart
final q = db.queryBuilder()
    .withQuery('active_users',
      db.from('users').select(['*']).where('active', '=', true)
    )
    .from('active_users')
    .select(['id', 'name'])
    .where('role', '=', 'admin')
    .toSQL();
print(q.sql);
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
final q = db.from('users').whereIn('id',
  db.from('orders').whereIn('product_id',
    db.from('products').select(['id'])
  ).select(['user_id'])
).toSQL();
print(q.sql);

// Use CTEs for clarity:
final q2 = db.queryBuilder()
    .withQuery('electronics',
      db.from('products').select(['id']).where('category', '=', 'Electronics')
    )
    .withQuery('electronics_orders',
      db.from('orders').whereIn('product_id',
        db.from('electronics').select(['id'])
      )
    )
    .from('users')
    .select(['*'])
    .whereIn('id',
      db.from('electronics_orders').select(['user_id'])
    )
    .toSQL();
print(q2.sql);
```

### 2. Reusability
Reference the same CTE multiple times:

```dart
final q = db.queryBuilder()
    .withQuery('high_value_orders',
      db.from('orders').select(['*']).where('amount', '>', 1000)
    )
    .from('high_value_orders')
    .select([
      db.queryBuilder().client.raw('count(distinct user_id) as customers'),
      db.queryBuilder().client.raw('sum(amount) as revenue')
    ])
    .toSQL();
print(q.sql);
```

### 3. Performance
PostgreSQL can materialize CTEs for optimization.

## Recursive CTE Examples

### Organization Hierarchy

```dart
final recursive = db.from('employees')
    .select(['id', 'name', 'manager_id', db.queryBuilder().client.raw('1 as level')])
    .where('manager_id', '=', null)
    .union([
      db.from('employees as e')
        .select(['e.id', 'e.name', 'e.manager_id', db.queryBuilder().client.raw('o.level + 1')])
        .join('org_tree as o', 'e.manager_id', 'o.id')
    ]);

final q = db.queryBuilder()
    .withRecursive('org_tree', recursive)
    .from('org_tree')
    .select(['*'])
    .orderBy('level')
    .toSQL();
print(q.sql);
```

### Graph Traversal

```dart
final paths = db.from('edges')
    .select(['source', 'target', db.queryBuilder().client.raw('ARRAY[source, target] as path')])
    .where('source', '=', startNode)
    .union([
      db.from('edges as e')
        .select(['e.source', 'e.target', db.queryBuilder().client.raw('p.path || e.target')])
        .join('paths as p', 'p.target', 'e.source')
        .where(db.queryBuilder().client.raw('NOT e.target = ANY(p.path)'))  // Avoid cycles
    ]);

final q = db.queryBuilder()
    .withRecursive('paths', paths)
    .from('paths')
    .select(['*'])
    .toSQL();
print(q.sql);
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
