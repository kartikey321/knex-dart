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
