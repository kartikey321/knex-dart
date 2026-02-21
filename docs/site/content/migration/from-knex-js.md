---
title: Migrating from Knex.js
description: Transition your Knex.js knowledge to Knex Dart
---

# Migrating from Knex.js

Knex Dart is a Knex.js port. Most query-building patterns map directly.

## Key Differences

### 1. `with` keyword rename

**Knex.js**
```javascript
knex.with('cte', query).select('*').from('cte')
```

**Knex Dart**
```dart
knex.withQuery('cte', query).select(['*']).from('cte')
```

### 2. `select` argument style

Dart uses list-based column selection consistently:

```dart
knex('users').select(['id', 'name'])
```

### 3. Runtime entry points

For active DB execution, use async factories:

```dart
final pg = await Knex.postgres(...);
final my = await Knex.mysql(...);
final sq = await Knex.sqlite(filename: 'app.db');
```

## Operator Syntax

Both are supported in Dart:

```dart
// 2-arg form (implicit '=')
knex('users').where('name', 'John');

// 3-arg form
knex('users').where('name', '=', 'John');
```

## Current Parity Snapshot

| Area | Status |
|------|--------|
| SELECT / INSERT / UPDATE / DELETE | ✅ implemented |
| WHERE families (basic/IN/NULL/BETWEEN/EXISTS/grouped/column) | ✅ implemented |
| JOINs (all types + advanced callback join clauses) | ✅ implemented |
| Aggregates / Subqueries / CTEs / UNION | ✅ implemented |
| `first`, `pluck`, lock/wait modes | ✅ implemented |
| Window/analytic coverage | 🔶 partial |
| Schema builder / migrations full parity | 🔶 in progress |
| Runtime pooling + advanced transaction parity | 🔶 in progress |

## Migration Examples

### Basic query

**Knex.js**
```javascript
knex('users')
  .select('id', 'name')
  .where('active', true)
  .orderBy('name');
```

**Knex Dart**
```dart
knex('users')
  .select(['id', 'name'])
  .where('active', true)
  .orderBy('name');
```

### Advanced callback join

```dart
knex('users').join('orders', (j) {
  j.on('users.id', 'orders.user_id')
   .andOnVal('orders.status', '=', 'completed')
   .orOnNull('orders.deleted_at');
});
```

### CTE rename

```dart
knex.withQuery('high_value', knex('orders').where('amount', '>', 1000))
  .select(['*'])
  .from('high_value');
```

## Current Test Signal

The project currently has **411 passing tests**, including many JS-vs-Dart comparison tests.

## What is still evolving

- Connection pooling behavior parity
- Nested/savepoint transaction semantics parity
- Remaining advanced APIs and dialect-specific edge cases

## Getting Help

- [GitHub Issues](https://github.com/kartikey321/knex-dart/issues)
- [Examples](/examples/basic-queries)
- [WHERE Clauses](/query-building/where-clauses)
