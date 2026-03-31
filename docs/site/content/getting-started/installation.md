---
title: Installation
description: Install and set up Knex Dart in your project
---

# Installation

Get started with Knex Dart in your Dart or Flutter project.

## Requirements

- Dart SDK 3.10.0 or higher
- For Flutter: Flutter 3.22.0 or higher

## Packages

`knex_dart` is the core query builder. To connect to a database, add the driver package for your database — it pulls in `knex_dart` automatically.

| Database | Package | Install |
|---|---|---|
| PostgreSQL | `knex_dart_postgres` | `dart pub add knex_dart_postgres` |
| MySQL | `knex_dart_mysql` | `dart pub add knex_dart_mysql` |
| SQLite | `knex_dart_sqlite` | `dart pub add knex_dart_sqlite` |
| DuckDB | `knex_dart_duckdb` | `dart pub add knex_dart_duckdb` |
| SQL Server | `knex_dart_mssql` | `dart pub add knex_dart_mssql` |
| Google BigQuery | `knex_dart_bigquery` | `dart pub add knex_dart_bigquery` |
| Snowflake | `knex_dart_snowflake` | `dart pub add knex_dart_snowflake` |
| Turso (libSQL) | `knex_dart_turso` | `dart pub add knex_dart_turso` |
| Cloudflare D1 | `knex_dart_d1` | `dart pub add knex_dart_d1` |

## Add a Driver

Pick the driver for your database:

### PostgreSQL

```bash
dart pub add knex_dart_postgres
```

### MySQL

```bash
dart pub add knex_dart_mysql
```

### SQLite

```bash
dart pub add knex_dart_sqlite
```

### DuckDB (OLAP / Analytics)

```bash
dart pub add knex_dart_duckdb
```

> **System dependency (native):** Requires the DuckDB shared library.
> macOS: `brew install duckdb`
> Linux: download `libduckdb.so` from [duckdb.org/docs/installation](https://duckdb.org/docs/installation)
>
> No setup needed for browser/WASM — DuckDB loads via WASM automatically.

### SQL Server (MSSQL)

```bash
dart pub add knex_dart_mssql
```

> **System dependency:** Requires the FreeTDS shared library.
> Linux: `sudo apt-get install libsybdb5`
> macOS: `brew install freetds`

### Google BigQuery

```bash
dart pub add knex_dart_bigquery
```

No system dependencies. Uses the BigQuery REST API.

### Snowflake

```bash
dart pub add knex_dart_snowflake
```

No system dependencies. Uses the Snowflake SQL REST API.

### Turso (libSQL)

```bash
dart pub add knex_dart_turso
```

No system dependencies. Uses the libSQL HTTP wire protocol.

### Cloudflare D1

```bash
dart pub add knex_dart_d1
```

No system dependencies. Uses the Cloudflare D1 REST API.

---

## Query Builder Only

If you only need SQL generation (no database connection), add the core package directly:

```bash
dart pub add knex_dart
```

This is useful for testing, SQL snapshots, or generating queries to pass to another layer.

## Verify Installation

### With a driver (SQLite example)

```dart
import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';

Future<void> main() async {
  final db = await KnexSQLite.connect(filename: ':memory:');
  print(db('users').select(['id', 'name']).toSQL().sql);
  // select "id", "name" from "users"
  await db.destroy();
}
```

### Query builder only

```dart
import 'package:knex_dart/knex_dart.dart';
import 'package:knex_dart_capabilities/knex_dart_capabilities.dart';

void main() {
  final q = KnexQuery.forDialect(KnexDialect.postgres);
  print(q.from('users').select(['id', 'name']).toSQL().sql);
  // select "id", "name" from "users"
}
```

## Next Steps

- [Quick Start](./quick-start) — Connect and run your first query
- [Database Support](/database-support) — Connection examples for all 9 databases
- [WHERE Clauses](/query-building/where-clauses) — Learn query filtering
