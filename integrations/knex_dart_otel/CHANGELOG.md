# Changelog

## 0.1.0

- Initial release of `knex_dart_otel`.
- Added `KnexOtelInterceptor` for driver wrapper query instrumentation.
- Records OpenTelemetry client spans for query, raw SQL, schema, transaction, stream, and D1 batch operations routed through the interceptor pipeline.
- Records `db.client.operation.duration` histogram metrics.
- Added request/response hooks via `KnexOtelOptions`.

