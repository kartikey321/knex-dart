---
title: Knex Dart
description: A Knex.js port for Dart — powerful SQL query builder supporting PostgreSQL, MySQL, SQLite, DuckDB, MSSQL, BigQuery, Snowflake, Turso, and Cloudflare D1
---

# Knex Dart

A powerful, flexible SQL query builder for Dart, ported from **[Knex.js](https://knexjs.org)**.

## ✨ Features

- ✅ **Complete Query Building** — SELECT, INSERT, UPDATE, DELETE with full support
- ✅ **29 WHERE Methods** — basic, grouped, BETWEEN, EXISTS, IN, NULL, column comparisons, JSON, full-text
- ✅ **All JOIN Types** — INNER, LEFT, RIGHT, FULL OUTER, CROSS, LATERAL
- ✅ **Advanced JOIN Clauses** — `onVal`, `onIn`, `onBetween`, `onExists`, `using`, `onJsonPathEquals`
- ✅ **Subqueries** — in WHERE IN, FROM, and SELECT clauses
- ✅ **UNION / INTERSECT / EXCEPT** — with ALL variants
- ✅ **CTEs** — WITH and WITH RECURSIVE
- ✅ **Aggregates** — COUNT, SUM, AVG, MIN, MAX with DISTINCT and FILTER variants
- ✅ **Window Functions** — RANK, DENSE_RANK, ROW_NUMBER, LEAD, LAG, FIRST_VALUE, LAST_VALUE, NTH_VALUE + frame clauses
- ✅ **Upserts** — `onConflict().merge()`
- ✅ **Schema Builder** — createTable, alterTable, dropTable, foreign keys, indexes
- ✅ **Migrations** — code-first, SQL-directory, and JSON-schema sources
- ✅ **Connection Pooling** — built-in pool for PostgreSQL and MySQL
- ✅ **Streaming** — `streamQuery()` for large result sets and SQLite `watch()` for reactive queries
- ✅ **Nested Transactions** — savepoint-based nesting on all drivers
- ✅ **OpenTelemetry** — optional driver-wrapper spans and `db.client.operation.duration` metrics
- ✅ **Browser Playground** — Dart LSP diagnostics, hover, auto-imports, and embedded SQL execution
- ✅ **Web / WASM** — DuckDB and SQLite run in the browser via WASM
- ✅ **591+ Tests Passing** — comprehensive coverage with >85% line coverage
- ✅ **9 Driver Packages** — install only what you need

## 📦 Driver Packages

| Database | Package | Notes |
|---|---|---|
| PostgreSQL | [`knex_dart_postgres`](https://pub.dev/packages/knex_dart_postgres) | Pooled, savepoints, RETURNING |
| MySQL | [`knex_dart_mysql`](https://pub.dev/packages/knex_dart_mysql) | Pooled, savepoints |
| SQLite | [`knex_dart_sqlite`](https://pub.dev/packages/knex_dart_sqlite) | File + in-memory, savepoints, watch(), web/WASM |
| DuckDB | [`knex_dart_duckdb`](https://pub.dev/packages/knex_dart_duckdb) | OLAP, native + WASM/web |
| SQL Server | [`knex_dart_mssql`](https://pub.dev/packages/knex_dart_mssql) | FreeTDS-based |
| Google BigQuery | [`knex_dart_bigquery`](https://pub.dev/packages/knex_dart_bigquery) | HTTP-based |
| Snowflake | [`knex_dart_snowflake`](https://pub.dev/packages/knex_dart_snowflake) | HTTP-based |
| Turso (libSQL) | [`knex_dart_turso`](https://pub.dev/packages/knex_dart_turso) | HTTP + sqld |
| Cloudflare D1 | [`knex_dart_d1`](https://pub.dev/packages/knex_dart_d1) | HTTP-based |

## 🛠️ Tooling Packages

| Tooling | Package | Notes |
|---|---|---|
| Dialect linting | [`knex_dart_lint`](https://pub.dev/packages/knex_dart_lint) | Optional custom_lint plugin |
| OpenTelemetry | [`knex_dart_otel`](https://pub.dev/packages/knex_dart_otel) | Optional instrumentation for driver wrappers |

## 🚀 Quick Start

Pick your database driver:

```bash
# PostgreSQL
dart pub add knex_dart_postgres

# MySQL
dart pub add knex_dart_mysql

# SQLite
dart pub add knex_dart_sqlite

# DuckDB (OLAP / analytics)
dart pub add knex_dart_duckdb
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

await db.close();
```

Or generate SQL without a connection (for testing or logging):

```dart
import 'package:knex_dart/knex_dart.dart';
import 'package:knex_dart_capabilities/knex_dart_capabilities.dart';

final q = KnexQuery.forDialect(KnexDialect.postgres);

print(q.from('users').where('active', '=', true).toSQL().sql);
// select * from "users" where "active" = $1
```

## 🎯 Why Knex Dart?

### Familiar API
Coming from Node.js/Knex.js? Most query-building patterns transfer directly — same method names, same chaining style.

### No Bundled Drivers
Install only the driver you need. No transitive dependencies on databases you don't use.

### Type-Safe
Leverages Dart's strong typing while maintaining the flexibility of dynamic query building.

### Well-Tested
591+ tests with >85% line coverage, ensuring correctness and behavioral parity with Knex.js.

### Works Everywhere
Native (macOS/Linux/Windows), Flutter mobile, and browser/WASM (DuckDB).

## 📚 Documentation

Try examples in the browser playground: **[playground.knex.mahawarkartikey.in](https://playground.knex.mahawarkartikey.in/)**

**Getting Started**
- [Installation](/getting-started/installation) — Add driver packages
- [Quick Start](/getting-started/quick-start) — Connect and run your first query
- [Database Support](/database-support) — All 9 supported databases with connection examples

**Query Building**
- [WHERE Clauses](/query-building/where-clauses) — All 29 filtering methods
- [Joins](/query-building/joins) — INNER, LEFT, RIGHT, FULL OUTER, CROSS, LATERAL
- [Write Operations](/query-building/write-operations) — INSERT, UPDATE, DELETE, upsert
- [Aggregation](/query-building/aggregation) — COUNT, SUM, AVG, GROUP BY, HAVING
- [Window Functions](/query-building/window-functions) — RANK, LEAD, LAG, frame clauses
- [Subqueries](/query-building/subqueries) — Nested queries
- [CTEs (WITH)](/query-building/ctes) — Common table expressions
- [UNION / INTERSECT / EXCEPT](/query-building/unions) — Set operations
- [Schema Builder](/query-building/schema-builder) — CREATE TABLE, ALTER TABLE, indexes

**Advanced**
- [Transactions](/query-building/transactions) — Atomic operations, savepoints, nesting
- [Migrations](/migration/migrations) — Code-first and SQL-directory migration sources
- [Connection Pooling](/connections/pooling) — Pool configuration for PostgreSQL and MySQL
- [Streaming](/connections/streaming) — `streamQuery()` for large result sets

**Tooling**
- [Dialect Lint](/tooling/dialect-lint) — Optional static checks for dialect-incompatible APIs
- [OpenTelemetry](/tooling/opentelemetry) — Query spans, stream spans, transaction query spans, and DB client duration metrics

**Migration Guide**
- [From Knex.js](/migration/from-knex-js) — Differences and equivalents

## 🔗 Links

- [GitHub Repository](https://github.com/kartikey321/knex-dart)
- [pub.dev — knex_dart](https://pub.dev/packages/knex_dart)
- [Report Issues](https://github.com/kartikey321/knex-dart/issues)

## 📄 License

MIT License — see LICENSE file for details.
