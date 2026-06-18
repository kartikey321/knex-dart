---
title: Database Support
description: All supported databases and how to connect to each
---

# Database Support

Each database is a separate driver package. Install only what you need.

## Supported Databases

| Database | Package | Transport | Notes |
|---|---|---|---|
| PostgreSQL | [`knex_dart_postgres`](https://pub.dev/packages/knex_dart_postgres) | TCP | Pooled, savepoints, RETURNING |
| MySQL | [`knex_dart_mysql`](https://pub.dev/packages/knex_dart_mysql) | TCP | Pooled, savepoints |
| SQLite | [`knex_dart_sqlite`](https://pub.dev/packages/knex_dart_sqlite) | FFI / WASM | File + in-memory, savepoints, watch(), web storage modes |
| DuckDB | [`knex_dart_duckdb`](https://pub.dev/packages/knex_dart_duckdb) | FFI / WASM | OLAP, native + browser |
| SQL Server | [`knex_dart_mssql`](https://pub.dev/packages/knex_dart_mssql) | FreeTDS | Windows/Linux/macOS |
| Google BigQuery | [`knex_dart_bigquery`](https://pub.dev/packages/knex_dart_bigquery) | HTTP | REST API |
| Snowflake | [`knex_dart_snowflake`](https://pub.dev/packages/knex_dart_snowflake) | HTTP | REST API |
| Turso (libSQL) | [`knex_dart_turso`](https://pub.dev/packages/knex_dart_turso) | HTTP | libSQL wire protocol |
| Cloudflare D1 | [`knex_dart_d1`](https://pub.dev/packages/knex_dart_d1) | HTTP | Workers REST API |

---

## PostgreSQL

<!-- doc:run scope=postgres expect_stdout='Alice' -->
```dart
import 'dart:io';

import 'package:knex_dart_postgres/knex_dart_postgres.dart';

final db = await KnexPostgres.connect(
  host: Platform.environment['PG_HOST'] ?? 'localhost',
  port: int.parse(Platform.environment['PG_PORT'] ?? '5432'),
  database: Platform.environment['PG_DATABASE'] ?? 'knex_test',
  username: Platform.environment['PG_USER'] ?? 'knex',
  password: Platform.environment['PG_PASSWORD'] ?? 'knex',
);

await db.rawSql('create temporary table doc_users (name text)');
await db.insert(
  db('doc_users').insert({'name': 'Alice'}),
);

final rows = await db.select(
  db('doc_users').select(['name']),
);

print(rows.first['name']);
await db.destroy();
```

With connection pool:

```dart
final db = await KnexPostgres.connect(
  host: 'localhost',
  database: 'myapp',
  username: 'user',
  password: 'pass',
  poolConfig: const PoolConfig(min: 2, max: 10),
);
```

**PostgreSQL-specific features:**
- `$1, $2, ...` positional placeholders
- `RETURNING` clause support
- JSON operators (`whereJsonPath`, `whereJsonSupersetOf`, `whereJsonSubsetOf`)
- Full-text search with language option
- Connection pooling via native postgres pool

---

## MySQL

<!-- doc:run scope=mysql expect_stdout='Alice' -->
```dart
import 'dart:io';

import 'package:knex_dart_mysql/knex_dart_mysql.dart';

final db = await KnexMySQL.connect(
  host: Platform.environment['MYSQL_HOST'] ?? 'localhost',
  port: int.parse(Platform.environment['MYSQL_PORT'] ?? '3306'),
  database: Platform.environment['MYSQL_DATABASE'] ?? 'knex_test',
  user: Platform.environment['MYSQL_USER'] ?? 'knex',
  password: Platform.environment['MYSQL_PASSWORD'] ?? 'knex',
);

await db.rawSql('create temporary table doc_users (name varchar(50))');
await db.insert(
  db('doc_users').insert({'name': 'Alice'}),
);

final rows = await db.select(
  db('doc_users').select(['name']),
);

print(rows.first['name']);
await db.destroy();
```

With connection pool:

```dart
final db = await KnexMySQL.connect(
  host: 'localhost',
  database: 'myapp',
  user: 'user',
  password: 'pass',
  poolConfig: const PoolConfig(min: 2, max: 10),
);
```

**MySQL-specific features:**
- `?` positional placeholders
- Backtick identifier quoting
- Full-text search (`IN BOOLEAN MODE` / `IN NATURAL LANGUAGE MODE`)
- Connection pooling via `TarnPool`

---

## SQLite

```dart
import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';

// File-based
final fileDb = await KnexSQLite.connect(filename: 'app.db');

// In-memory
final memoryDb = await KnexSQLite.connect(filename: ':memory:');

// Browser/WASM only: automatic storage selection
final webDb = await KnexSQLite.connect(
  filename: 'app.db',
  webStorageMode: 'auto',
);

final rows = await fileDb.select(
  fileDb('users').where('active', '=', true),
);

await fileDb.close();
await memoryDb.close();
await webDb.close();
```

**SQLite-specific features:**
- `?` positional placeholders
- Double-quoted identifier quoting
- In-memory database support
- Nested transactions via `SAVEPOINT`
- Streaming via `Statement.selectCursor()`
- Reactive `watch()` query streams
- Browser/WASM storage modes: `memory`, `indexedDb`, `opfs`, `auto`
- JSON via `json_extract()`

`webStorageMode` is web-only. Passing it to the native sqlite3 driver throws
`UnsupportedError`.

---

## DuckDB

DuckDB is an in-process OLAP database optimised for analytical queries. It works on native platforms and in the **browser via WASM**.

```dart
import 'package:knex_dart_duckdb/knex_dart_duckdb.dart';

// In-memory
final db = await KnexDuckDB.memory();

// File-backed
final db = await KnexDuckDB.file('/path/to/analytics.db');

final rows = await db.select(
  db.queryBuilder()
    .from('sales')
    .sum('amount as total')
    .groupBy('region'),
);

await db.close();
```

**Web / WASM (browser):** DuckDB runs in Chrome/headless browsers via `dart_duckdb`'s WASM backend. No additional setup is required in application code — the same API works on both native and web.

**DuckDB-specific features:**
- `$1, $2, ...` positional placeholders (PostgreSQL-compatible)
- Double-quoted identifier quoting
- FULL OUTER JOIN, LATERAL joins
- Window functions, CTEs, INTERSECT/EXCEPT
- JSON functions
- Nested transactions via `SAVEPOINT`
- Streaming via `fetchAllStream()`

> **System dependency (native):** Requires the DuckDB shared library.
> macOS: `brew install duckdb`
> Linux: download `libduckdb.so` from [duckdb.org/docs/installation](https://duckdb.org/docs/installation)

---

## SQL Server (MSSQL)

<!-- doc:run scope=mssql expect_stdout='Alice' -->
```dart
import 'dart:io';

import 'package:knex_dart_mssql/knex_dart_mssql.dart';

final db = await KnexMssql.connect(
  host: Platform.environment['MSSQL_HOST'] ?? 'localhost',
  port: Platform.environment['MSSQL_PORT'] ?? '1433',
  database: Platform.environment['MSSQL_DATABASE'] ?? 'knex_test',
  username: Platform.environment['MSSQL_USER'] ?? 'sa',
  password: Platform.environment['MSSQL_PASSWORD'] ?? 'Knex_Test1!',
);

await db.rawSql('CREATE TABLE #doc_users (name NVARCHAR(50))');
await db.rawSql("INSERT INTO #doc_users (name) VALUES ('Alice')");

final rows = await db.select(
  db('#doc_users').select(['name']),
);

print(rows.first['name']);
await db.destroy();
```

**SQL Server-specific features:**
- `@p1, @p2, ...` named placeholders
- Square-bracket identifier quoting (`[column]`)
- `TOP N` for LIMIT
- `RETURNING`-equivalent via `OUTPUT` clause

> **System dependency:** Requires the FreeTDS shared library.
> Linux: `sudo apt-get install libsybdb5`
> macOS: `brew install freetds`

---

## Google BigQuery

```dart
import 'package:knex_dart_bigquery/knex_dart_bigquery.dart';

final db = KnexBigQuery(
  projectId: 'my-gcp-project',
  token: 'your-gcp-access-token',
  defaultDataset: 'analytics',
);

final rows = await db.select(
  db('events').where('event_type', '=', 'purchase'),
);

db.destroy();
```

**BigQuery-specific features:**
- Uses the BigQuery REST API (no native driver)
- Backtick identifier quoting (`` `dataset.table` ``)
- `@param` named placeholders
- Works on native and web platforms

---

## Snowflake

```dart
import 'package:knex_dart_snowflake/knex_dart_snowflake.dart';

final db = KnexSnowflake(
  account: 'myorg-myaccount',
  token: 'your-snowflake-jwt-or-oauth-token',
  database: 'MYDB',
  schema: 'PUBLIC',
);

final rows = await db.select(
  db('orders').where('status', '=', 'shipped'),
);

db.destroy();
```

**Snowflake-specific features:**
- Uses the Snowflake SQL REST API
- Double-quoted identifier quoting
- `?` positional placeholders
- Works on native and web platforms

---

## Turso (libSQL)

```dart
import 'package:knex_dart_turso/knex_dart_turso.dart';

final db = KnexTurso(
  url: 'https://my-db.turso.io',
  authToken: 'your-token',
);

final rows = await db.select(
  db('users').where('active', '=', true),
);

db.destroy();
```

**Turso-specific features:**
- Uses the libSQL HTTP wire protocol
- Works with Turso cloud databases and self-hosted `sqld`
- `?` positional placeholders
- Works on native and web platforms

---

## Cloudflare D1

```dart
import 'package:knex_dart_d1/knex_dart_d1.dart';

final db = KnexD1(
  accountId: 'your-cf-account-id',
  databaseId: 'your-d1-database-id',
  apiToken: 'your-cf-api-token',
);

final rows = await db.select(
  db('users').where('active', '=', true),
);

db.destroy();
```

**D1-specific features:**
- Uses the Cloudflare D1 REST API
- SQLite-compatible SQL dialect
- `?` positional placeholders
- Works on native and web platforms

---

## Query Builder Only (No Connection)

Use `KnexQuery` when you only need SQL generation — no driver required. Pick any target dialect to get correct identifier quoting and parameter placeholders:

```dart
import 'package:knex_dart/knex_dart.dart';
import 'package:knex_dart_capabilities/knex_dart_capabilities.dart';

// PostgreSQL dialect — double-quoted identifiers, $1 placeholders
final q = KnexQuery.forDialect(KnexDialect.postgres);

final result = q.from('users')
  .select(['id', 'name'])
  .where('active', '=', true)
  .toSQL();

print(result.sql);       // select "id", "name" from "users" where "active" = $1
print(result.bindings);  // [true]

// MySQL dialect — backtick identifiers, ? placeholders
final qMySQL = KnexQuery.forClient('mysql2');
print(qMySQL.from('users').where('active', '=', true).toSQL().sql);
// select * from `users` where `active` = ?
```

Useful for testing, SQL snapshots, ORM layers, and multi-dialect query generation.

---

## Dialect Capability Matrix

Not every feature is available on every database. The `knex_dart_capabilities` package and `knex_dart_lint` plugin help you catch incompatibilities at analysis time.

| Feature | PostgreSQL | MySQL | SQLite | DuckDB | MSSQL | BigQuery | Snowflake | Turso | D1 |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| RETURNING | ✅ | ❌ | ❌ | ✅ | via OUTPUT | ❌ | ❌ | ❌ | ❌ |
| FULL OUTER JOIN | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| LATERAL JOIN | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| onConflict().merge() | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ |
| Connection Pool | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Nested Transactions | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| streamQuery() | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Web / WASM | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ |
