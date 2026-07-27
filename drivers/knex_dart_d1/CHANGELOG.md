## 0.2.2

- Bumped `knex_dart` lower bound to `^1.3.0`.
- Bumped `lints` to `^6.1.0` and `test` to `^1.31.0`.

## 0.2.1

- Tighten `knex_dart` lower bound to `^1.2.1` — `QueryInterceptor`
  and `QueryExecutionContext` were not present before 1.2.1.

## 0.2.0

- Added `QueryInterceptor` pipeline support: attach OTel, logging, or custom
  interceptors via the `interceptors` parameter on `KnexD1({...})`.
- Fixed exception propagation in transaction rollback using
  `Error.throwWithStackTrace`.

## 0.1.0

- Initial release.
- Cloudflare D1 HTTP driver for `knex_dart`.
