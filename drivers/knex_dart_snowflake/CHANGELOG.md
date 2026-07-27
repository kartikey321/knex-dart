## 0.2.2

- Bumped `knex_dart` lower bound to `^1.3.0`.
- Bumped `lints` to `^6.1.0` and `test` to `^1.31.0`.

## 0.2.1

- Tighten `knex_dart` lower bound to `^1.2.1` — `QueryInterceptor`
  and `QueryExecutionContext` were not present before 1.2.1.

## 0.2.0

- Added `QueryInterceptor` pipeline support: attach OTel, logging, or custom
  interceptors via the `interceptors` parameter on `KnexSnowflake.connect()`.
- Fixed null binding type for Snowflake SQL API: `_buildBindings` now uses
  `Map<String, String?>` so null parameter values are correctly serialized.
- Fixed exception propagation in transaction rollback using
  `Error.throwWithStackTrace`.

## 0.1.0

- Initial release.
- Snowflake HTTP driver for `knex_dart`.
