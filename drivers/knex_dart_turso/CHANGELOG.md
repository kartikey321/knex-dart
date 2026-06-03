## 0.2.0

- Added `QueryInterceptor` pipeline support: attach OTel, logging, or custom
  interceptors via the `interceptors` parameter on `KnexTurso.connect()`.
- Added 30-second timeout on all HTTP requests to prevent indefinite hangs.
- Fixed `_tryOpen()` to only suppress known connection errors rather than
  all exceptions, so driver-level regressions are not silently swallowed.
- Fixed savepoint lifecycle events routed through child transaction ID.
- Fixed exception propagation in transaction rollback using
  `Error.throwWithStackTrace`.

## 0.1.0

- Initial release.
- Turso/libSQL HTTP driver for `knex_dart`.
