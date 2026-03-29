---
title: Aggregation
description: GROUP BY, HAVING, and aggregate expressions in Knex Dart
---

# Aggregation

Use `groupBy`, `groupByRaw`, `having`, and `havingRaw` to build grouped queries.

> SQL output below uses PostgreSQL-style quoting/placeholders for readability.

## `groupBy(column)`

```dart
final q = db
    .queryBuilder()
    .table('orders')
    .select(['customer_id'])
    .select(db.raw('count(*) as order_count'))
    .groupBy('customer_id');

final sql = q.toSQL();
```

```sql
select "customer_id", count(*) as order_count from "orders" group by "customer_id"
```

## `groupByRaw(sql, [bindings])`

Use this for expressions/functions that should not be wrapped as identifiers.

```dart
final q = db
    .queryBuilder()
    .table('orders')
    .select([
      db.raw("date_trunc('month', created_at) as month_bucket"),
    ])
    .select(db.raw('sum(amount) as revenue'))
    .groupByRaw("date_trunc('month', created_at)")
    .orderBy('month_bucket');
```

```sql
select date_trunc('month', created_at) as month_bucket, sum(amount) as revenue from "orders" group by date_trunc('month', created_at) order by "month_bucket" asc
```

## `having(column, opOrValue, [value])`

`having` supports two forms:
- `having(column, value)` (defaults operator to `=`)
- `having(column, operator, value)`

```dart
final q = db
    .queryBuilder()
    .table('orders')
    .select(['customer_id'])
    .select(db.raw('count(*) as order_count'))
    .groupBy('customer_id')
    .having('customer_id', '>', 1000);
```

```sql
select "customer_id", count(*) as order_count from "orders" group by "customer_id" having "customer_id" > $1
```

Bindings:

```dart
[1000]
```

## `havingRaw(sql, [bindings])`

Use `havingRaw` for aggregate expressions:

```dart
final q = db
    .queryBuilder()
    .table('orders')
    .select(['customer_id'])
    .select(db.raw('sum(amount) as revenue'))
    .groupBy('customer_id')
    .havingRaw('sum(amount) > ?', [1000]);
```

```sql
select "customer_id", sum(amount) as revenue from "orders" group by "customer_id" having sum(amount) > $1
```

## Common Aggregate Expressions in `select(raw(...))`

```dart
final q = db
    .queryBuilder()
    .table('payments')
    .select([
      'status',
      db.raw('count(*) as total_rows'),
      db.raw('sum(amount) as total_amount'),
      db.raw('avg(amount) as avg_amount'),
      db.raw('min(amount) as min_amount'),
      db.raw('max(amount) as max_amount'),
    ])
    .groupBy('status');
```

```sql
select "status", count(*) as total_rows, sum(amount) as total_amount, avg(amount) as avg_amount, min(amount) as min_amount, max(amount) as max_amount from "payments" group by "status"
```

## GROUP BY + HAVING + ORDER BY Together

```dart
final q = db
    .queryBuilder()
    .table('orders')
    .select(['customer_id'])
    .select(db.raw('count(*) as order_count'))
    .select(db.raw('sum(amount) as revenue'))
    .groupBy('customer_id')
    .havingRaw('count(*) >= ?', [5])
    .havingRaw('sum(amount) > ?', [1000])
    .orderBy('revenue', 'desc');

final sql = q.toSQL();
```

```sql
select "customer_id", count(*) as order_count, sum(amount) as revenue from "orders" group by "customer_id" having count(*) >= $1 and sum(amount) > $2 order by "revenue" desc
```

Bindings:

```dart
[5, 1000]
```

## Dialect Notes

- Placeholder style is dialect-specific (`$1` for PostgreSQL/DuckDB, `?` for MySQL/SQLite/MSSQL).
- Identifier quoting is dialect-specific (`"col"` vs `` `col` ``).
- On MSSQL, alias aggregate expressions (for example `count(*) as total`) so result keys are predictable instead of SQL Server's default unnamed column label.

