# knex_dart OTel SQLite Example

Runs a real `KnexSQLite` workload through `KnexOtelInterceptor` and exports
spans plus `db.client.operation.duration` metrics through the Dartastic
OpenTelemetry SDK.

The default mode uses console exporters, so it works without Docker:

```bash
dart pub get
dart run bin/sqlite_otel_collector.dart
```

To send telemetry to an OpenTelemetry Collector over OTLP/HTTP:

```bash
dart run bin/sqlite_otel_collector.dart \
  --otlp-http \
  --endpoint=http://localhost:4318 \
  --insecure
```

To send telemetry over OTLP/gRPC:

```bash
dart run bin/sqlite_otel_collector.dart \
  --otlp-grpc \
  --endpoint=localhost:4317 \
  --insecure
```

The workload emits spans for:

- `CREATE` schema statements
- `INSERT`
- `SELECT`
- transaction `UPDATE` and `SELECT`
- one intentional failing raw SQL query, to verify error span export

This package is intentionally standalone. It uses the current SDK with a
dependency override while `knex_dart_otel` itself remains API-only.
