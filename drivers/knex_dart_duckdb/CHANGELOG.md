## 0.2.1

- Tighten `knex_dart` lower bound to `^1.2.1` — `QueryInterceptor`
  and `QueryExecutionContext` were not present before 1.2.1.

## 0.2.0

- Added `QueryInterceptor` pipeline support: attach OTel, logging, or custom
  interceptors via the `interceptors` parameter on `KnexDuckDB.memory()` /
  `KnexDuckDB.connect()`.
- Added `raw()` alias on `KnexDuckDBTransaction` for parity with other drivers.
- Fixed `ResultSet` resource leak: result sets are now disposed in a
  `try/finally` block after row mapping.
- Fixed exception propagation in transaction rollback using
  `Error.throwWithStackTrace`.
- Note: DuckDB does not support SQL-level `SAVEPOINT`; nested transactions are
  not available on this driver.

## 0.1.0

- Initial release.
- DuckDB driver for `knex_dart` with native and web/WASM support.
