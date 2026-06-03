## 0.2.0

- Added `QueryInterceptor` pipeline support: attach OTel, logging, or custom
  interceptors via the `interceptors` parameter on `KnexD1({...})`.
- Fixed exception propagation in transaction rollback using
  `Error.throwWithStackTrace`.

## 0.1.0

- Initial release.
- Cloudflare D1 HTTP driver for `knex_dart`.
