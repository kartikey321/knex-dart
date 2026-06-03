---
name: knex-opentelemetry
description: Use when instrumenting knex_dart live driver wrappers with OpenTelemetry spans, DB client duration metrics, hooks, transactions, or stream/query interceptor behavior.
metadata:
  knex_dart_version: 1.2.1
---

## Scope

Use `knex_dart_otel` only with live driver wrappers such as `KnexPostgres`, `KnexSQLite`, `KnexMySQL`, `KnexDuckDB`, `KnexMssql`, `KnexTurso`, `KnexBigQuery`, `KnexD1`, and `KnexSnowflake`.

Do not use it with `KnexQuery.forDialect(...)` or `KnexQuery.forClient(...)`; those are SQL-generation-only APIs and do not execute database work.

## Install

```bash
dart pub add knex_dart_otel
```

`knex_dart_otel` depends on `dartastic_opentelemetry_api`, not a concrete SDK/exporter. The application must install and initialize its OpenTelemetry SDK/exporter separately.

## Basic Setup

Initialize the OpenTelemetry SDK before constructing `KnexOtelInterceptor`, then pass it to the driver wrapper through `interceptors`.

```dart
import 'package:dartastic_opentelemetry_api/dartastic_opentelemetry_api.dart';
import 'package:knex_dart_otel/knex_dart_otel.dart';
import 'package:knex_dart_postgres/knex_dart_postgres.dart';

final tracer = OTelAPI.tracerProvider().getTracer(
  'my-service',
  version: '1.0.0',
);

final db = await KnexPostgres.connect(
  host: 'localhost',
  port: 5432,
  database: 'myapp',
  username: 'user',
  password: 'pass',
  interceptors: [
    KnexOtelInterceptor(tracer: tracer),
  ],
);
```

The same `interceptors: [...]` pattern is available on driver wrappers that support live execution.

## What Gets Measured

`KnexOtelInterceptor` creates OpenTelemetry client spans and records the `db.client.operation.duration` histogram.

Covered wrapper operations:

- `select`, `insert`, `update`, `delete`, `execute`
- `rawSql(sql, [bindings])`
- `executeSchema((schema) { ... })`
- transaction queries through `KnexTransaction`
- streaming queries through `streamQuery` or driver-specific stream methods
- D1 `batch` and simulated `trx` as one `BATCH` operation
- Snowflake `getAsyncResult` as `GET_ASYNC_RESULT`

Not covered:

- SQL-generation-only APIs (`KnexQuery.forDialect`, `KnexQuery.forClient`)
- direct low-level client usage outside wrapper APIs
- migrations through the separate migrator/facade path
- bound parameter values by default
- per-statement spans inside D1 batches

## Span Attributes

Base span attributes set by `KnexOtelInterceptor`:

- `db.system.name`
- `db.operation.name`
- `db.namespace` when known
- `db.collection.name` when known
- `db.query.text` when query text capture is enabled
- `server.address` when known
- `server.port` when known

Span name is the low-cardinality query summary, for example `SELECT users`, `INSERT orders`, `CREATE`, `BATCH`, or `GET_ASYNC_RESULT`.

On errors, the interceptor records the exception, sets `error.type`, sets span status to `SpanStatusCode.Error`, and rethrows the original error.

## Duration Metric

The interceptor records:

```text
db.client.operation.duration
```

The value is elapsed time in seconds. Default histogram buckets are:

```text
0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1, 5, 10
```

Metric attributes include low-cardinality database metadata such as `db.system.name`, `db.operation.name`, `db.namespace`, `db.collection.name`, `server.address`, and `server.port`. Do not add SQL text or parameter values to metric attributes.

## Options and Hooks

```dart
final interceptor = KnexOtelInterceptor(
  tracer: tracer,
  options: KnexOtelOptions(
    captureQueryText: true,
    maxQueryTextLength: 1024,
    requestHook: (span, ctx) {
      if (ctx.txId != null) {
        span.setStringAttribute('db.transaction.id', ctx.txId!);
      }
    },
    responseHook: (span, ctx, result) {
      if (result.rowCount != null) {
        span.setIntAttribute('db.response.row_count', result.rowCount!);
      }
    },
  ),
);
```

`requestHook` receives `APISpan` and `KnexOtelSpanContext`.

`responseHook` receives `APISpan`, `KnexOtelSpanContext`, and `KnexOtelResult`.

Hook exceptions are swallowed so instrumentation cannot break database execution.

## Custom Histogram

Pass `operationDurationHistogram` when you need explicit meter/provider control.

```dart
final histogram = OTelAPI.meterProvider()
    .getMeter(name: 'my-service')
    .createHistogram<double>(
      name: 'db.client.operation.duration',
      unit: 's',
      description: 'Duration of database client operations.',
    );

final interceptor = KnexOtelInterceptor(
  tracer: tracer,
  operationDurationHistogram: histogram,
);
```

## Transactions

Transaction callbacks receive wrapper-level transaction facades implementing `KnexTransaction`.

```dart
await db.trx((tx) async {
  await tx.insert(tx('users').insert({'email': 'a@example.com'}));
  await tx.select(tx('users').where('email', 'a@example.com'));
});
```

Queries executed through `tx` route through the same interceptor pipeline and include `ctx.txId` in `KnexOtelSpanContext`.

Nested transactions create child transaction IDs. SQLite manages savepoints internally, so nested SQLite operations have child `txId` values but SQLite savepoint SQL itself is not exposed as separate spans.

## Streams

For streaming queries, the span starts when the returned stream is listened to and ends exactly once on normal close, error, or subscriber cancellation.

```dart
await for (final row in db.streamQuery(db('users').select(['id', 'email']))) {
  print(row);
}
```

Only call transaction `streamQuery` where the driver supports it. `KnexTransaction.streamQuery()` throws `UnsupportedError` by default for drivers that do not override it.

## Docs

- OpenTelemetry docs: `https://docs.knex.mahawarkartikey.in/raw/tooling/opentelemetry.md`
- OTel architecture: `https://github.com/kartikey321/knex-dart/blob/main/integrations/knex_dart_otel/ARCHITECTURE.md`
- Package README: `https://github.com/kartikey321/knex-dart/blob/main/integrations/knex_dart_otel/README.md`
- AI docs index: `https://docs.knex.mahawarkartikey.in/llms.txt`
