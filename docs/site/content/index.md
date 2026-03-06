---
title: Knex Dart
description: A Knex.js port for Dart — powerful SQL query builder with database execution
---

# Knex Dart

A powerful, flexible SQL query builder for Dart, ported from **[Knex.js](https://knexjs.org)**.

## ✨ Features

- ✅ **Complete Query Building** — SELECT, INSERT, UPDATE, DELETE with full support
- ✅ **29 WHERE Methods** — basic, grouped, BETWEEN, EXISTS, IN, NULL, column comparisons, JSON, full-text
- ✅ **All JOIN Types** — INNER, LEFT, RIGHT, FULL OUTER, CROSS
- ✅ **Advanced JOIN Clauses** — `onVal`, `onIn`, `onBetween`, `onExists`, `using`, `onJsonPathEquals`
- ✅ **Subqueries** — in WHERE IN, FROM, and SELECT clauses
- ✅ **UNION / INTERSECT / EXCEPT** — with ALL variants
- ✅ **CTEs** — WITH and WITH RECURSIVE
- ✅ **Aggregates** — COUNT, SUM, AVG, MIN, MAX with DISTINCT variants
- ✅ **Upserts** — `onConflict().merge()`
- ✅ **Schema Builder** — createTable, alterTable, dropTable, foreign keys, indexes
- ✅ **551+ Tests Passing** — comprehensive coverage with >85% line coverage
- ✅ **Driver Packages** — PostgreSQL, MySQL, SQLite (install only what you need)

## 🚀 Quick Start

Pick your database driver:

```bash
# PostgreSQL
dart pub add knex_dart_postgres

# MySQL
dart pub add knex_dart_mysql

# SQLite
dart pub add knex_dart_sqlite
```

Connect and query:

```dart
import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';

final db = await KnexSQLite.connect(filename: ':memory:');

final users = await db.select(
  db('users')
    .select(['id', 'name', 'email'])
    .where('active', '=', true)
    .orderBy('name'),
);

await db.destroy();
```

Or generate SQL without a connection:

```dart
import 'package:knex_dart/knex_dart.dart';

final db = Knex(MockClient());

print(db('users').where('active', '=', true).toSQL().sql);
// select * from "users" where "active" = ?
```

## 🎯 Why Knex Dart?

### Familiar API
Coming from Node.js/Knex.js? Most query-building patterns transfer directly.

### No Bundled Drivers
Install only the driver you need — no transitive dependencies on databases you don't use.

### Type-Safe
Leverages Dart's strong typing while maintaining the flexibility of dynamic query building.

### Well-Tested
551+ tests with >85% line coverage, ensuring correctness and behavioral parity with Knex.js.

## 📚 Documentation

- [Getting Started](/getting-started/installation) — Install and configure
- [Quick Start](/getting-started/quick-start) — Connect and run your first query
- [Database Support](/database-support) — PostgreSQL, MySQL, SQLite
- [Joins](/query-building/joins) — INNER, LEFT, RIGHT, FULL OUTER, CROSS + advanced ON clauses
- [WHERE Clauses](/query-building/where-clauses) — All 29 filtering methods
- [Write Operations](/query-building/write-operations) — INSERT, UPDATE, DELETE, upsert
- [Transactions](/query-building/transactions) — Atomic multi-query operations
- [Schema Builder](/query-building/schema-builder) — CREATE TABLE, ALTER TABLE, indexes, foreign keys
- [Migrations](/migration/migrations) — Code-first, SQL-directory, and external-schema migration sources
- [Dialect Lint](/tooling/dialect-lint) — Optional static checks for dialect-incompatible query APIs
- [Subqueries](/query-building/subqueries) — Nested queries
- [CTEs (WITH)](/query-building/ctes) — Common table expressions
- [Migration Guide](/migration/from-knex-js) — Coming from Knex.js?
- [Examples](/examples/basic-queries) — Real-world examples

## 🔗 Links

- [GitHub Repository](https://github.com/kartikey321/knex-dart)
- [pub.dev — knex_dart](https://pub.dev/packages/knex_dart)
- [Report Issues](https://github.com/kartikey321/knex-dart/issues)

## 📄 License

MIT License — see LICENSE file for details.
