---
title: Migrating from Knex.js
description: Transition your Knex.js knowledge to Knex Dart
---

# Migrating from Knex.js

Knex Dart provides near-100% API parity with Knex.js. If you know Knex.js, you already know most of Knex Dart!

## Key Differences

### 1. Explicit Operators

**Knex.js** (implicit `=`):
```javascript
knex('users').where('name', 'John')
```

**Knex Dart** (explicit operator):
```dart
knex('users').where('name', '=', 'John')
```

### 2. Reserved Keywords

**Knex.js**:
```javascript
knex.with('cte', query).select('*').from('cte')
```

**Knex Dart** (`with` is a Dart keyword):
```dart
knex.withQuery('cte', query).select(['*']).from('cte')
```

### 3. Array Syntax

**Knex.js**:
```javascript
knex('users').select('id', 'name')
// or
knex('users').select(['id', 'name'])
```

**Knex Dart** (always use lists):
```dart
knex('users').select(['id', 'name'])
```

### 4. Client Configuration

**Knex.js**:
```javascript
const knex = require('knex')({
  client: 'pg',
  connection: {
    host: 'localhost',
    database: 'myapp'
  }
});
```

**Knex Dart**:
```dart
// Query building only (current)
final knex = Knex(client: MockClient());

// PostgreSQL (coming soon)
final knex = await Knex.postgres(
  host: 'localhost',
  database: 'myapp',
);
```

### 5. Async/Await

**Knex.js**:
```javascript
const users = await knex('users').select('*');
```

**Knex Dart** (same!):
```dart
final users = await knex('users').select(['*']);
```

## Feature Parity Matrix

| Feature | Knex.js | Knex Dart | Notes |
|---------|---------|-----------|-------|
| SELECT | ✅ | ✅ | 100% |
| INSERT | ✅ | ✅ | 100% |
| UPDATE | ✅ | ✅ | 100% |
| DELETE | ✅ | ✅ | 100% |
| WHERE (basic) | ✅ | ✅ | Explicit operators |
| WHERE IN | ✅ | ✅ | 100% |
| WHERE NULL | ✅ | ✅ | 100% |
| WHERE BETWEEN | ✅ | ✅ | 100% |
| WHERE COLUMN | ✅ | ✅ | 100% |
| WHERE NOT | ✅ | ✅ | 100% |
| WHERE EXISTS | ✅ | ✅ | 100% |
| WHERE WRAPPED | ✅ | ✅ | 100% |
| JOINs (all types) | ✅ | ✅ | 100% |
| Callback JOINs | ✅ | ✅ | 100% |
| GROUP BY | ✅ | ✅ | 100% |
| HAVING | ✅ | ✅ | 100% |
| ORDER BY | ✅ | ✅ | 100% |
| LIMIT/OFFSET | ✅ | ✅ | 100% |
| Aggregates | ✅ | ✅ | 100% |
| Subqueries (WHERE) | ✅ | ✅ | 100% |
| Subqueries (FROM) | ✅ | ✅ | 100% |
| Subqueries (SELECT) | ✅ | ✅ | 100% |
| UNION | ✅ | ✅ | 100% |
| UNION ALL | ✅ | ✅ | 100% |
| CTEs | ✅ | ✅ | `withQuery()` |
| Recursive CTEs | ✅ | ✅ | `withRecursive()` |
| Raw queries | ✅ | ✅ | 100% |
| RETURNING | ✅ | ✅ | 100% |
| Window Functions | ✅ | 🔶 | Coming soon |
| CASE statements | ✅ | 🔶 | Planned |
| Transactions | ✅ | 🔶 | Coming soon |
| PostgreSQL | ✅ | 🔶 | In progress |
| MySQL | ✅ | 🔶 | Planned |
| SQLite | ✅ | 🔶 | Planned |

**Current Coverage:** ~90% query building API

## Migration Examples

### Simple Query

**Knex.js**:
```javascript
knex('users')
  .select('id', 'name')
  .where('active', true)
  .orderBy('name');
```

**Knex Dart**:
```dart
knex('users')
  .select(['id', 'name'])
  .where('active', '=', true)
  .orderBy('name');
```

### JOIN with WHERE

**Knex.js**:
```javascript
knex('users')
  .join('orders', 'users.id', 'orders.user_id')
  .where('orders.status', 'completed')
  .select('users.name', 'orders.total');
```

**Knex Dart**:
```dart
knex('users')
  .join('orders', 'users.id', 'orders.user_id')
  .where('orders.status', '=', 'completed')
  .select(['users.name', 'orders.total']);
```

### Subquery

**Knex.js**:
```javascript
knex('users').whereIn('id',
  knex('orders').select('user_id').where('total', '>', 1000)
);
```

**Knex Dart** (identical!):
```dart
knex('users').whereIn('id',
  knex('orders').select(['user_id']).where('total', '>', 1000)
);
```

### CTE

**Knex.js**:
```javascript
knex.with('high_value', knex('orders').where('amount', '>', 1000))
  .select('*').from('high_value');
```

**Knex Dart**:
```dart
knex.withQuery('high_value', knex('orders').where('amount', '>', 1000))
  .select(['*']).from('high_value');
```

## Quick Reference

### Common Patterns

| Operation | Knex.js | Knex Dart |
|-----------|---------|-----------|
| Select all | `.select('*')` | `.select(['*'])` |
| Multiple where | `.where('a', 1).where('b', 2)` | `.where('a', '=', 1).where('b', '=', 2)` |
| Where in list | `.whereIn('id', [1,2,3])` | `.whereIn('id', [1,2,3])` ✅ |
| Join | `.join('t', 'a.id', 'b.id')` | `.join('t', 'a.id', 'b.id')` ✅ |
| CTE | `.with('cte', ...)` | `.withQuery('cte', ...)` |

### Method Name Changes

| Knex.js | Knex Dart | Reason |
|---------|-----------|--------|
| `.with()` | `.withQuery()` | `with` is Dart keyword |

That's it! Only one method name is different.

## Tips for Migration

1. **Add Explicit Operators** - Always specify `=`, `>`, etc.
2. **Use Lists for Arrays** - `select(['a', 'b'])` not `select('a', 'b')`
3. **withQuery not with** - Remember the rename
4. **Test Incrementally** - Port queries one at a time

## What's Missing?

Currently not implemented (coming soon):
- Window functions
- CASE statements  
- INTERSECT/EXCEPT
- Actual database connections (PostgreSQL in progress)
- Transactions
- Schema builder
- Migrations

## Getting Help

- [GitHub Issues](https://github.com/kartikey321/knex-dart/issues)
- [Examples](/examples/basic-queries) - Real-world patterns
- [WHERE Clauses](/query-building/where-clauses) - Complete method list

## Community

Join the Dart/Flutter community:
- [r/dartlang](https://reddit.com/r/dartlang)
- [r/FlutterDev](https://reddit.com/r/FlutterDev)
- [Discord](https://discord.gg/dart)
