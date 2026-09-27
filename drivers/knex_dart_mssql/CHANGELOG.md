## 0.3.0

- **Breaking (internal): swapped the backing driver from `mssql_connection`
  (FFI/FreeTDS) to `mssql` (pure Dart, TDS 7.4/8.0, no native dependencies).**
  This removes the `brew install freetds` / `apt-get install freetds-dev`
  system dependency entirely, and structurally eliminates a class of bugs
  found in the FFI driver during this investigation: a global singleton
  connection, a blocking synchronous FFI call that could freeze the whole
  isolate, and a socket-lifecycle bug in its reachability probe.
  `KnexMssql`/`MssqlTrxClient`'s public API is unchanged — only the
  internal `MssqlClient` implementation was rewritten.
  **Not yet validated against a live SQL Server** in this environment
  (blocked by a local Docker/Rosetta limitation, unrelated to the driver);
  relying on CI's real SQL Server container for first real verification.
- Added `encrypt`/`trustServerCertificate` parameters to
  `KnexMssql.connect()`/`MssqlClient.connect()`, defaulting to
  `encrypt: true, trustServerCertificate: true`. The `mssql` package
  defaults to strict certificate validation (`trustServerCertificate:
  false`), unlike the previous FFI driver, which did not enforce TLS
  certificate validation by default — most local/on-prem/CI SQL Server
  instances (including this repo's own docker-compose setup) present a
  self-signed certificate and would otherwise fail to connect.

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
