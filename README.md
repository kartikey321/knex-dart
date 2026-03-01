# Knex Dart

A faithful port of [Knex.js](https://knexjs.org/) to Dart, bringing the same powerful and intuitive SQL query builder experience to Dart/Flutter backends.

[![Pub Version](https://img.shields.io/pub/v/knex_dart)](https://pub.dev/packages/knex_dart)
[![Test](https://img.shields.io/badge/tests-268%20passing-brightgreen)]()
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

## What is Knex Dart?

**Knex Dart is a work-in-progress port of [Knex.js](https://knexjs.org/) to Dart**, bringing the same powerful and intuitive query builder API to Dart/Flutter backends.

### � Current Status: Query Generation & Execution

Knex Dart supports **SQL query generation** and **database execution** with **identical API parity** for implemented features:

- ✅ **Type-safe query construction** - Fluent API identical to Knex.js
- ✅ **SQL generation** - Generate dialect-specific SQL (Postgres, MySQL, SQLite)
- ✅ **Database execution** - Built-in clients for PostgreSQL, MySQL, and SQLite (`.select()`, `.insert()`, etc.)
- ✅ **Transactions** - Bulletproof transactional scopes (`.trx()`)
- ✅ **Schema Builder** - Execute DDL for table creation (`createTable()`, `alterTable()`)
- ✅ **Advanced Queries** - CTEs (WITH), Subqueries, UNIONs, JSON operators, Full-Text Search, and Upserts (`onConflict`)
- ✅ **Comprehensive testing** - Hundreds of tests ensuring correctness against a Knex.js baseline

## Side-by-Side: Knex.js vs Knex Dart

### Basic Query

**Knex.js (JavaScript)**
```javascript
knex('users')
  .select('name', 'email')
  .where('age', '>', 18)
  .orderBy('created_at', 'desc')
  .limit(10);
```

**Knex Dart**
```dart
QueryBuilder(client)
  .table('users')
  .select(['name', 'email'])
  .where('age', '>', 18)
  .orderBy('created_at', 'desc')
  .limit(10);
```

### Joins

**Knex.js**
```javascript
knex('users')
  .join('orders', 'users.id', 'orders.user_id')
  .select('users.name', 'orders.total')
  .where('orders.status', 'completed');
```

**Knex Dart**
```dart
QueryBuilder(client)
  .table('users')
  .join('orders', 'users.id', 'orders.user_id')
  .select(['users.name', 'orders.total'])
  .where('orders.status', '=', 'completed');
```

### Aggregates

**Knex.js**
```javascript
knex('sales')
  .count('* as total_sales')
  .sum('amount as total_amount')
  .avg('amount as average_amount')
  .where('status', 'completed');
```

**Knex Dart**
```dart
QueryBuilder(client)
  .table('sales')
  .count('*', AggregateOptions(as: 'total_sales'))
  .sum('amount', AggregateOptions(as: 'total_amount'))
  .avg('amount', AggregateOptions(as: 'average_amount'))
  .where('status', '=', 'completed');
```

### Raw Queries

**Knex.js**
```javascript
knex.raw('select * from users where id = ?', [1])
```

**Knex Dart**
```dart
client.raw('select * from users where id = ?', [1])
```

## Features

✅ **SELECT, INSERT, UPDATE, DELETE** - Full CRUD support  
✅ **WHERE clauses** - Basic, IN, NULL, OR, Raw  
✅ **JOINs** - INNER, LEFT, RIGHT, FULL OUTER, CROSS with callback support  
✅ **Aggregates** - COUNT, SUM, AVG, MIN, MAX with DISTINCT variants  
✅ **Query composition** - ORDER BY, GROUP BY, HAVING, LIMIT, OFFSET  
✅ **DISTINCT** - Unique row selection  
✅ **Raw queries** - Full parameter binding support (`?`, `:name`, `??`)  
✅ **RETURNING clause** - PostgreSQL support  
✅ **Schema qualification** - Multi-schema database support  

## Installation

Add## Quick Start

Install the package:

```bash
dart pub add knex_dart
```

**Generate queries** (execution support coming soon):

```dart
import 'package:knex_dart/knex_dart.dart';

// Create a client (for query generation configuration)
final client = Client({
  'client': 'postgres',
});

// Build a query
final query = QueryBuilder(client)
  .table('users')
  .select(['id', 'name', 'email'])
  .where('status', '=', 'active')
  .limit(10);

// Get the generated SQL
final sql = query.toSQL();
print(sql.sql);       // select "id", "name", "email" from "users" where "status" = $1 limit $2
print(sql.bindings);  // ['active', 10]

// Execute on a live database (PostgreSQL wrapper natively supported)
final results = await client.select(query);
print(results);
```


## Documentation

### Basic Queries

```dart
// SELECT
QueryBuilder(client)
  .table('users')
  .select(['id', 'name']);

// INSERT
QueryBuilder(client)
  .table('users')
  .insert({'name': 'John', 'email': 'john@example.com'})
  .returning(['id']);

// UPDATE
QueryBuilder(client)
  .table('users')
  .where('id', '=', 1)
  .update({'name': 'Jane'});

// DELETE
QueryBuilder(client)
  .table('users')
  .where('id', '=', 1)
  .delete();
```

### Advanced Queries

```dart
// Complex JOIN with aggregates
QueryBuilder(client)
  .table('users')
  .select(['users.name', 'COUNT(orders.id) as order_count'])
  .leftJoin('orders', (j) {
    j.on('users.id', '=', 'orders.user_id')
     .andOn('orders.status', '=', 'completed');
  })
  .groupBy(['users.id', 'users.name'])
  .having('COUNT(orders.id)', '>', 5)
  .orderBy('order_count', 'desc');
```

## Roadmap

### ✅ Phase 1: Query Builder Core
- ✅ SELECT, INSERT, UPDATE, DELETE operations
- ✅ WHERE clauses, JOINs, ORDER BY, LIMIT/OFFSET
- ✅ Aggregate functions (COUNT, SUM, AVG, MIN, MAX)
- ✅ Raw queries with parameter binding
- ✅ PostgreSQL, MySQL, and SQLite generation

### ✅ Phase 2: Database Execution & Schema
- ✅ Database driver integration (PostgreSQL, MySQL, SQLite)
- ✅ Query execution with `client.select()` / `client.insert()` etc.
- ✅ Transaction support with `client.trx`
- ✅ Schema Builder phase 1 and 2 (`createTable`, `alterTable`, `foreign`)

### ✅ Phase 3: Advanced Query Features
- ✅ Extended WHERE clauses (BETWEEN, EXISTS, column comparisons, Full-Text, JSON)
- ✅ Subqueries & UNIONs
- ✅ CTEs (WITH clauses)
- ✅ Upserts (`onConflict.merge`)
- 🚧 Window functions (Planned)


## Comparison with Knex.js

Every implemented feature has been **comparison-tested** against Knex.js to ensure identical SQL generation. The only difference is parameter placeholder format:

- **Knex.js:** Uses `?` for all databases
- **Knex Dart:** Uses `$1, $2, ...` for PostgreSQL (database-specific)

This is actually **more correct** as it matches each database's native parameter format.

## Contributing

Contributions are welcome! Areas where help is needed:

- Additional WHERE clause variants
- Subquery support
- MySQL/SQLite client implementations
- Documentation improvements
- Bug reports and feature requests

## Acknowledgments

This project is a port of [Knex.js](https://knexjs.org/), created and maintained by Tim Griesser and contributors. All credit for the original design and API goes to the Knex.js team.

## License

MIT - See LICENSE file for details

## Links

- **Original Knex.js:** https://knexjs.org/
- **Issues:** https://github.com/kartikey321/knex-dart/issues

---

**Not ready for Knex Dart yet?** Check out the original [Knex.js](https://knexjs.org/) for Node.js applications.
