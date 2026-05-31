---
name: knex-connections
description: Use when configuring connection pools, executing raw SQL, or tapping observability streams on knex_dart driver clients.
metadata:
  knex_dart_version: 1.2.0
---

This skill covers pool configuration, raw SQL execution, observability, and teardown. For basic driver setup and first queries, see `knex-driver-setup`.

## Pool Configuration

Pass a `PoolConfig` to any `connect(...)` factory to tune the connection pool.

```dart
import 'package:knex_dart/knex_dart.dart';
import 'package:knex_dart_postgres/knex_dart_postgres.dart';

final db = await KnexPostgres.connect(
  host: 'db.example.com',
  port: 5432,
  database: 'myapp',
  username: 'app',
  password: 'secret',
  useSSL: true,
  poolConfig: const PoolConfig(
    min: 2,
    max: 10,
    acquireTimeoutMillis: 30000,
  ),
);
```

`PoolConfig` defaults: `min: 2`, `max: 10`, `acquireTimeoutMillis: 60000`.

## Raw SQL Execution

`db.rawSql(sql, [bindings])` on the driver wrapper runs a parameterized SQL string directly.

```dart
// No bindings
final rows = await db.rawSql('SELECT current_timestamp AS ts');

// Positional bindings
final users = await db.rawSql(
  'SELECT id, email FROM users WHERE created_at > \$1',
  [DateTime(2024).toIso8601String()],
);
```

For raw SQL fragments inside a query builder (not execution), use `db.queryBuilder().client.raw(sql, bindings)`.

## Observability Streams

Observability streams live on the low-level `Client` subclass (e.g. `PostgresClient`, `SQLiteClient`), which is also publicly exported by each driver package. Attach listeners before you run any queries.

```dart
import 'package:knex_dart_postgres/knex_dart_postgres.dart';

final client = await PostgresClient.connect(
  host: 'localhost',
  port: 5432,
  database: 'myapp',
  username: 'user',
  password: 'pass',
);

// Log every query
client.onQuery.listen((event) {
  print('[SQL] ${event.sql}  bindings=${event.bindings}');
});

// Log query errors
client.onQueryError.listen((event) {
  print('[ERROR] ${event.sql} → ${event.error}');
});

// Log query results with timing
client.onQueryResponse.listen((event) {
  print('[DONE] ${event.sql}  rows=${event.response?.length ?? 0}');
});
```

When you use `KnexPostgres.connect(...)`, the underlying `PostgresClient` is not exposed directly. Use the low-level `PostgresClient.connect(...)` constructor when you need stream access, then pass the client to queries through the `Knex` facade or use it directly.

## Teardown

```dart
// On KnexPostgres / KnexSQLite wrappers
await db.close();       // closes the pool
await db.destroy();     // alias for close()

// On PostgresClient / SQLiteClient directly
await client.close();
```

Always `await` teardown in `main()` or a `finally` block to drain the pool cleanly before process exit.

## SSL and Special Dialects

```dart
// CockroachDB — port 26257, wire-compatible with PostgreSQL
final crdb = await KnexPostgres.cockroachdb(
  host: 'localhost',
  database: 'defaultdb',
  username: 'root',
  useSSL: false,
);

// Amazon Redshift — port 5439, no RETURNING / LATERAL support
final rs = await KnexPostgres.redshift(
  host: 'my-cluster.us-east-1.redshift.amazonaws.com',
  database: 'dev',
  username: 'awsuser',
  password: 'secret',
);
```

## Docs

- Connections: `https://docs.knex.mahawarkartikey.in/raw/connections/connections.md`
- Streaming: `https://docs.knex.mahawarkartikey.in/raw/connections/streaming.md`
- OpenTelemetry: `https://docs.knex.mahawarkartikey.in/raw/tooling/opentelemetry.md`
- Quick start: `https://docs.knex.mahawarkartikey.in/raw/getting-started/quick-start.md`
