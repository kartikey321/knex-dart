---
title: Migrating from Knex.js
description: Transition your Knex.js knowledge to Knex Dart
---

# Migrating from Knex.js

Knex Dart is a Knex.js port. Most query-building patterns map directly.

## Setup

**Knex.js**
```javascript
const knex = require('knex')({ client: 'pg', connection: { ... } });
```

**Knex Dart**
```dart
import 'package:knex_dart_postgres/knex_dart_postgres.dart';

final db = await KnexPostgres.connect(
  host: 'localhost',
  database: 'myapp',
  username: 'user',
  password: 'pass',
);
```

The driver package determines the dialect — no `client:` string needed.

## Key Differences

### 1. Driver packages are separate

In Knex.js, the client is configured in one package. In Knex Dart, each database is a separate package:

| Database | Import |
|---|---|
| PostgreSQL | `package:knex_dart_postgres/knex_dart_postgres.dart` |
| MySQL | `package:knex_dart_mysql/knex_dart_mysql.dart` |
| SQLite | `package:knex_dart_sqlite/knex_dart_sqlite.dart` |

### 2. `select` takes a list

```dart
// Knex.js
knex('users').select('id', 'name')

// Knex Dart
db('users').select(['id', 'name'])
```

### 3. `with` → `withQuery`

`with` is a reserved keyword in Dart:

```dart
// Knex.js
knex.with('cte', query).select('*').from('cte')

// Knex Dart
db().withQuery('cte', db('orders').where('amount', '>', 1000))
  .select(['*'])
  .from('cte')
```

### 4. `destroy()` not `destroy()`

```dart
// Knex.js
await knex.destroy()

// Knex Dart
await db.destroy()
```

### 5. 2-arg where defaults to `=`

Both forms are supported:

```dart
// implicit '='
db('users').where('name', 'John');

// explicit operator
db('users').where('name', '=', 'John');
db('users').where('age', '>', 18);
```

## Query Parity Examples

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
db('users')
  .select(['id', 'name'])
  .where('active', '=', true)
  .orderBy('name');
```

### Join with callback

**Knex.js**
```javascript
knex('users').join('orders', function() {
  this.on('users.id', 'orders.user_id')
      .andOnVal('orders.status', 'completed');
});
```

**Knex Dart**
```dart
db('users').join('orders', (j) {
  j.on('users.id', '=', 'orders.user_id')
   .andOnVal('orders.status', '=', 'completed');
});
```

### CTE

**Knex.js**
```javascript
knex.with('high_value', knex('orders').where('amount', '>', 1000))
  .select('*').from('high_value')
```

**Knex Dart**
```dart
db().withQuery('high_value', db('orders').where('amount', '>', 1000))
  .select(['*']).from('high_value')
```

## Current Parity Snapshot

| Area | Status |
|------|--------|
| SELECT / INSERT / UPDATE / DELETE | ✅ implemented |
| WHERE families (basic/IN/NULL/BETWEEN/EXISTS/grouped/column/JSON/full-text) | ✅ implemented |
| JOINs (all types + advanced callback join clauses) | ✅ implemented |
| Aggregates / Subqueries / CTEs / UNION / INTERSECT / EXCEPT | ✅ implemented |
| `first`, `pluck`, lock/wait modes | ✅ implemented |
| Upserts (`onConflict().merge()`) | ✅ implemented |
| Schema builder phase 1 & 2 | ✅ implemented |
| Window/analytic functions | 🔶 partial |
| Connection pooling | 🔶 in progress |
| Nested/savepoint transactions | 🔶 in progress |

## Getting Help

- [GitHub Issues](https://github.com/kartikey321/knex-dart/issues)
- [Examples](/examples/basic-queries)
- [WHERE Clauses](/query-building/where-clauses)
