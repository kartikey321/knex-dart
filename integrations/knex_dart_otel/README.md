# knex_dart_otel

OpenTelemetry instrumentation for `knex_dart` driver wrappers.

This package provides `KnexOtelInterceptor`, a `QueryInterceptor` implementation that records:

- DB client spans for driver wrapper query operations
- stream spans for `streamQuery`
- transaction query spans through `KnexTransaction`
- `db.client.operation.duration` histogram metrics

It depends only on `dartastic_opentelemetry_api`, not an SDK/exporter, so applications choose their own OpenTelemetry SDK setup.

## Install

```bash
dart pub add knex_dart_otel
```

## Usage

Initialize your OpenTelemetry SDK before constructing the interceptor, then pass it to a driver wrapper:

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

final rows = await db.select(
  db.queryBuilder().from('users').where('active', true),
);
```

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
    },
    responseHook: (span, ctx, result) {
      if (result.rowCount != null) {
        span.setIntAttribute('db.response.row_count', result.rowCount!);
      }
    },
  ),
);
```

`requestHook` and `responseHook` errors are swallowed so instrumentation cannot break database execution.

## Coverage

Instrumentation covers the driver wrapper API:

- `select`, `insert`, `update`, `delete`, `execute`
- `rawSql`
- `executeSchema`
- transaction queries through `KnexTransaction`
- streaming queries through `streamQuery`
- D1 `batch` / simulated transaction batches as one `BATCH` operation

Migrations that run through the separate migrator/facade path are not currently instrumented by this package.

## Metrics

`KnexOtelInterceptor` records:

```text
db.client.operation.duration
```

The value is recorded in seconds with standard database client duration buckets.

## SDK Initialization

Construct `KnexOtelInterceptor` after your OpenTelemetry SDK is installed. The default histogram is created lazily and cached; if it is created before an SDK is installed, it may bind to a no-op provider.

Pass `operationDurationHistogram` explicitly if you need full control over meter/provider binding.

## Real SDK example

This package intentionally depends only on the OpenTelemetry API. A standalone
example app in the repository shows end-to-end export through the Dartastic
OpenTelemetry SDK:

```bash
cd examples/knex_otel_sqlite_app
dart pub get
dart run bin/sqlite_otel_collector.dart
```

The example uses console exporters by default and also supports OTLP HTTP/gRPC
collector endpoints.
