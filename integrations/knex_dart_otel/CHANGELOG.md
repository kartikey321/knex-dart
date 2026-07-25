# Changelog

## 0.1.2

- Bump `dartastic_opentelemetry_api` from `^0.9.0` to `^1.0.0-rc.1`,
  per upstream maintainer guidance
  ([dartastic_opentelemetry#93](https://github.com/MindfulSoftwareLLC/dartastic_opentelemetry/issues/93)).
  `^0.9.0` resolved to `0.9.1` mid-branch, which briefly needed an exact
  `0.9.0` pin to work around a real spec violation in the 0.9.x line
  (API-only spans recorded without an SDK installed, which `trace/api.md`
  requires to be non-recording); 0.9.1 fixed that violation, and 1.0.0-rc.x
  is the maintainer-recommended track going forward.
- No production behavior change: `lib/` only ever wrote to spans
  (`setStringAttribute`, `setStatus`, `recordException`, `end`), which is
  spec-compliant with or without an SDK installed.
- Test suite now installs a real SDK `TracerProvider` (`dartastic_opentelemetry`,
  dev-only) with an in-memory exporter to get genuinely recording spans to
  assert against, instead of relying on the API-only path recording (which
  was never spec-guaranteed).

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
