## 0.2.0

- Added `QueryInterceptor` pipeline support: attach OTel, logging, or custom
  interceptors via the `interceptors` parameter on `KnexBigQuery({...})`.
- Fixed exception propagation in transaction rollback using
  `Error.throwWithStackTrace`.

## 0.1.0

- Initial release.
- BigQuery driver for `knex_dart`.
