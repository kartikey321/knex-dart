---
title: Window Functions
description: Analytic and value window functions with WindowSpec frame clauses
---

# Window Functions

Knex Dart supports analytic window functions and value window functions in `SELECT` clauses.

> SQL output below uses PostgreSQL-style quoting/placeholders for readability.

## Analytic Functions

### `rowNumber()`, `rank()`, `denseRank()`

These methods accept the same overloads:
- `method(alias, orderBy, [partitionBy])`
- `method(alias, rawOverClause)`
- `method(alias, (a) => ...)` callback via `AnalyticClause`

```dart
final q = db
    .queryBuilder()
    .table('employees')
    .select(['id', 'department', 'salary'])
    .rowNumber('row_num', (a) =>
        a.partitionBy('department').orderBy('salary', 'desc'))
    .rank('salary_rank', (a) =>
        a.partitionBy('department').orderBy('salary', 'desc'))
    .denseRank('dense_salary_rank', (a) =>
        a.partitionBy('department').orderBy('salary', 'desc'));

final sql = q.toSQL();
```

```sql
select "id", "department", "salary", row_number() over (partition by "department" order by "salary" desc) as row_num, rank() over (partition by "department" order by "salary" desc) as salary_rank, dense_rank() over (partition by "department" order by "salary" desc) as dense_salary_rank from "employees"
```

### `ntile()`

`ntile()` is supported by SQL engines listed below, but there is currently no dedicated `QueryBuilder.ntile()` helper.
Use `raw()` in `select()`:

```dart
final q = db
    .queryBuilder()
    .table('employees')
    .select([
      'id',
      db.raw(
        'ntile(4) over (partition by "department" order by "salary" desc) as salary_quartile',
      ),
    ]);
```

```sql
select "id", ntile(4) over (partition by "department" order by "salary" desc) as salary_quartile from "employees"
```

## Value Window Functions

### `lead()` and `lag()`

`lead` signature:
- `lead(alias, sourceColumn, [second, third, offset, defaultVal])`

`lag` signature:
- `lag(alias, sourceColumn, [second, third, offset])`

`second/third` define `OVER (...)` exactly like analytic helpers (`orderBy`, `partitionBy`, callback, raw, or `WindowSpec`).

```dart
final q = db
    .queryBuilder()
    .table('employees')
    .select(['id', 'department', 'salary'])
    .lead('next_salary', 'salary', 'salary', 'department', 1, 0)
    .lag('prev_salary', 'salary', 'salary', 'department', 1);

final sql = q.toSQL();
```

```sql
select "id", "department", "salary", lead("salary", 1, $1) over (partition by "department" order by "salary") as next_salary, lag("salary", 1) over (partition by "department" order by "salary") as prev_salary from "employees"
```

Bindings:

```dart
[0]
```

### `firstValue()`, `lastValue()`, `nthValue()`

```dart
final win = WindowSpec()
    .partitionBy(['department'])
    .orderBy('salary', 'desc')
    .rowsBetween(
      WindowSpec.unboundedPreceding,
      WindowSpec.unboundedFollowing,
    );

final q = db
    .queryBuilder()
    .table('employees')
    .select(['id', 'department', 'salary'])
    .firstValue('first_salary', 'salary', win)
    .lastValue('last_salary', 'salary', win)
    .nthValue('third_salary', 'salary', 3, win);

final sql = q.toSQL();
```

```sql
select "id", "department", "salary", first_value("salary") over (partition by "department" order by "salary" desc rows between unbounded preceding and unbounded following) as first_salary, last_value("salary") over (partition by "department" order by "salary" desc rows between unbounded preceding and unbounded following) as last_salary, nth_value("salary", 3) over (partition by "department" order by "salary" desc rows between unbounded preceding and unbounded following) as third_salary from "employees"
```

For `lastValue()`, an explicit frame is usually required for true "last row in partition" semantics.

## WindowSpec

`WindowSpec` is immutable and chainable:

- `partitionBy(List<String>)`
- `orderBy(String column, [String direction = 'asc'])`
- `rowsBetween(int start, int end)`
- `rangeBetween(int start, int end)`

### Frame constants

- `WindowSpec.unboundedPreceding`
- `WindowSpec.currentRow`
- `WindowSpec.unboundedFollowing`

Example using `rangeBetween`:

```dart
final running = WindowSpec()
    .partitionBy(['department'])
    .orderBy('salary')
    .rangeBetween(
      WindowSpec.unboundedPreceding,
      WindowSpec.currentRow,
    );

final q = db
    .queryBuilder()
    .table('employees')
    .firstValue('running_first', 'salary', running);
```

```sql
select first_value("salary") over (partition by "department" order by "salary" asc range between unbounded preceding and current row) as running_first from "employees"
```

## Dialect Support

| Dialect | Support |
|---|---|
| PostgreSQL | All functions in this guide |
| MySQL 8+ | All functions in this guide |
| SQLite 3.25+ | `rank`, `row_number`, `lead`, `lag` |
| MSSQL | All functions in this guide |
| DuckDB | All functions in this guide |

