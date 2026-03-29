---
title: Connection Pooling
description: Configure PoolConfig for PostgreSQL and MySQL drivers
---

# Connection Pooling

`PoolConfig` configures connection pool behavior for pooled drivers.

## PoolConfig Fields

```dart
const PoolConfig(
  min: 2,
  max: 10,
  acquireTimeoutMillis: 60000,
  idleTimeoutMillis: null,
  reapIntervalMillis: 1000,
)
```

- `min`: minimum open connections to keep.
- `max`: maximum open connections.
- `acquireTimeoutMillis`: max wait time to get a connection from the pool.
- `idleTimeoutMillis`: how long an idle connection can stay open before cleanup.
- `reapIntervalMillis`: how often idle-connection cleanup runs.

## PostgreSQL Example

```dart
import 'package:knex_dart/knex_dart.dart' show PoolConfig;
import 'package:knex_dart_postgres/knex_dart_postgres.dart';

final db = await KnexPostgres.connect(
  host: 'localhost',
  database: 'app',
  username: 'postgres',
  password: 'secret',
  poolConfig: const PoolConfig(
    min: 2,
    max: 10,
    acquireTimeoutMillis: 30000,
    idleTimeoutMillis: 30000,
    reapIntervalMillis: 1000,
  ),
);
```

## MySQL Example

```dart
import 'package:knex_dart/knex_dart.dart' show PoolConfig;
import 'package:knex_dart_mysql/knex_dart_mysql.dart';

final db = await KnexMySQL.connect(
  host: 'localhost',
  user: 'root',
  password: 'secret',
  database: 'app',
  poolConfig: const PoolConfig(
    min: 2,
    max: 10,
    acquireTimeoutMillis: 30000,
    idleTimeoutMillis: 30000,
    reapIntervalMillis: 1000,
  ),
);
```

## Drivers Without Pooling

These drivers currently run without a connection pool (single-connection or request-based transport):

- `knex_dart_sqlite`
- `knex_dart_duckdb`
- `knex_dart_mssql`
- `knex_dart_bigquery`
- `knex_dart_snowflake`
- `knex_dart_turso`
- `knex_dart_d1`

## Best Practices

- Start with `min: 2` to keep warm connections ready.
- Set `max` based on database limits and app concurrency.
- Use `idleTimeoutMillis` to clean up idle connections in bursty workloads.
- Keep `reapIntervalMillis` small (default `1000`) for predictable idle cleanup.

> Implementation note: PostgreSQL and MySQL both accept `PoolConfig`; MySQL currently uses all five fields directly, while PostgreSQL primarily uses `max` and `acquireTimeoutMillis` in its underlying pool settings.

