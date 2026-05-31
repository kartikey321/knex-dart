---
title: OpenTelemetry
description: Instrument knex_dart driver wrappers with OpenTelemetry spans and DB client duration metrics
---

# OpenTelemetry

`knex_dart_otel` adds OpenTelemetry instrumentation to live driver wrappers through the `QueryInterceptor` API in `knex_dart` core.

It instruments driver wrapper operations, including:

- `select`, `insert`, `update`, `delete`, and `execute`
- `rawSql`
- `executeSchema` statements
- transaction queries routed through `KnexTransaction`
- streaming queries routed through `streamQuery`
- D1 `batch` / simulated transaction batches as one `BATCH` operation

Migrations that run through the separate migrator/facade path are not currently instrumented by `knex_dart_otel`. Wrap migration execution in a manual span if you need migration timing.

## Install

```bash
dart pub add knex_dart_otel
```

You also need an OpenTelemetry SDK/exporter in your app. `knex_dart_otel` depends only on `dartastic_opentelemetry_api`, so it stays API-only and low overhead when no SDK is installed.

## Basic Setup

Initialize your OpenTelemetry SDK before constructing `KnexOtelInterceptor`. Then pass the interceptor to the driver wrapper:

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

The same `interceptors` constructor parameter is available on the driver wrappers.

## What Gets Recorded

Each operation creates a client span with OpenTelemetry DB semantic convention attributes:

- `db.system.name`
- `db.operation.name`
- `db.namespace` when the driver knows the database name
- `db.collection.name` when the query builder has a concrete table name
- `db.query.text` when `captureQueryText` is enabled
- `server.address` and `server.port` for networked drivers

`knex_dart_otel` also records the stable DB client duration metric:

```text
db.client.operation.duration
```

The metric unit is seconds and uses standard DB duration buckets.

## Options

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
      span.setStringAttribute('tenant.id', 'tenant-123');
    },
    responseHook: (span, ctx, result) {
      if (!result.isError && result.rowCount != null) {
        span.setIntAttribute('db.response.row_count', result.rowCount!);
      }
    },
  ),
);
```

Hook errors are swallowed so observability code cannot break query execution.

## SDK Initialization Order

Construct `KnexOtelInterceptor` after your OpenTelemetry SDK is installed. The default histogram is created lazily and cached. If it is created before an SDK is installed, it may bind to a no-op provider for the lifetime of the process.

If you need full control, pass your own `operationDurationHistogram`:

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

## Context Propagation

The interceptor runs inside the caller's async zone. If your HTTP/gRPC framework sets the active OpenTelemetry context in Dart zones, DB spans created inside request handlers are parented to the current request span automatically.

## Transactions and Streams

Transaction callbacks receive a `KnexTransaction` facade. Queries executed through that facade are routed through the same interceptor pipeline and include a transaction ID in `KnexOtelSpanContext.txId`.

Streaming spans start when the stream is listened to and end exactly once when the stream completes, errors, or is cancelled.
