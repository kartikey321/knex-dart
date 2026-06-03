# Changelog

## 0.1.1

- Bump `knex_dart` lower bound to `^1.2.1` — `QueryInterceptor` and
  `QueryExecutionContext` were not present in `1.2.0`, causing pana downgrade
  analysis to fail.
- Added `example/main.dart` demonstrating interceptor setup with request/response hooks.
- Added dartdoc to all previously undocumented public symbols
  (`intercept`, `interceptStream`, `KnexOtelOptions()`, `KnexOtelResult()`).
- Added library-level doc comment.

## 0.1.0

- Initial release of `knex_dart_otel`.
- Added `KnexOtelInterceptor` for driver wrapper query instrumentation.
- Records OpenTelemetry client spans for query, raw SQL, schema, transaction, stream, and D1 batch operations routed through the interceptor pipeline.
- Records `db.client.operation.duration` histogram metrics.
- Added request/response hooks via `KnexOtelOptions`.
- Added DB semantic convention span attributes, span status, error type, and
  exception event coverage.
- Uses direct OpenTelemetry context activation so the interceptor is the single
  source of DB exception events when running with a real SDK.
