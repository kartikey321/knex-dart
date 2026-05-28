---
name: knex-driver-setup
description: Use when choosing between SQL-only knex_dart usage and a live driver package, or when writing the first connected query.
metadata:
  knex_dart_version: 1.2.0
---

## Choose the Right Entry Point

Use `knex_dart` by itself when you only need SQL generation:

```dart
import 'package:knex_dart/knex_dart.dart';

final q = KnexQuery.forDialect(KnexDialect.postgres);
final compiled = q.from('users').where('active', '=', true).toSQL();
```

Use a driver package when you need live execution:

- PostgreSQL: `knex_dart_postgres`
- MySQL / MariaDB: `knex_dart_mysql`
- SQLite: `knex_dart_sqlite`
- DuckDB: `knex_dart_duckdb`
- MSSQL: `knex_dart_mssql`
- Turso / libSQL: `knex_dart_turso`
- BigQuery: `knex_dart_bigquery`
- D1: `knex_dart_d1`
- Snowflake: `knex_dart_snowflake`

## Connection Examples

```dart
import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';
final sqlite = await KnexSQLite.connect(filename: ':memory:');
```

```dart
import 'package:knex_dart_postgres/knex_dart_postgres.dart';
final pg = await KnexPostgres.connect(
  host: 'localhost',
  port: 5432,
  database: 'myapp',
  username: 'user',
  password: 'pass',
);
```

```dart
import 'package:knex_dart_mysql/knex_dart_mysql.dart';
final mysql = await KnexMySQL.connect(
  host: 'localhost',
  port: 3306,
  user: 'user',
  password: 'pass',
  database: 'myapp',
);
```

```dart
import 'package:knex_dart_duckdb/knex_dart_duckdb.dart';
final duck = await KnexDuckDB.memory();
```

## First Executable Query

Driver wrappers consistently expose `queryBuilder()` plus execution helpers:

```dart
final rows = await sqlite.select(
  sqlite.queryBuilder()
      .table('users')
      .select(['id', 'name'])
      .where('active', '=', true),
);
```

Write operations follow the same pattern:

```dart
await sqlite.insert(
  sqlite.queryBuilder().table('users').insert({'name': 'Alice'}),
);
```

## Important Constraints

- `knex_dart` core does not execute queries by itself
- The safest portable builder pattern is `queryBuilder().table('...')`
- `db.raw(...)` is the common way to create raw SQL fragments
- Direct raw execution method names differ by driver, so check the wrapper you are using

If you already have a low-level `Client`, wrap it in `Knex(client)` to get callable `db('users')` syntax.

## Docs

- Installation: `https://docs.knex.mahawarkartikey.in/raw/getting-started/installation.md`
- Quick start: `https://docs.knex.mahawarkartikey.in/raw/getting-started/quick-start.md`
- Database support: `https://docs.knex.mahawarkartikey.in/raw/database-support.md`
- AI docs index: `https://docs.knex.mahawarkartikey.in/llms.txt`
