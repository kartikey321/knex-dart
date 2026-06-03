## 0.2.0

- Added `QueryInterceptor` pipeline support: attach OTel, logging, or custom
  interceptors via the `interceptors` parameter on `KnexMSSQL.connect()`.
- Fixed schema compiler `renameColumn` to emit the correct `exec sp_rename`
  syntax with full `[schema].[table].[column]` qualified name.
- Fixed savepoint lifecycle events routed through child transaction ID.
- Fixed exception propagation in transaction rollback using
  `Error.throwWithStackTrace`.
- Fixed savepoint ID generation to use a per-instance counter.

## 0.1.0

- Initial release.
- Microsoft SQL Server driver for `knex_dart`.
