## 0.3.2

- Bumped `knex_dart` lower bound to `^1.3.0`.
- Bumped `lints` to `^6.1.0` and `test` to `^1.31.0`.

## 0.3.1

- Tighten `knex_dart` lower bound to `^1.2.1` — `QueryInterceptor`
  and `QueryExecutionContext` were not present before 1.2.1.

## 0.3.0

- Added `QueryInterceptor` pipeline support: attach OTel, logging, or custom
  interceptors via the `interceptors` parameter on `KnexMySQL.connect()`.
- Fixed prepared statement resource leak: `deallocate()` is now called in a
  `try/finally` block even when execution throws.
- Fixed transaction connection management: failed transactions now call
  `_pool.discard()` instead of `_pool.release()` to avoid returning broken
  connections to the pool.
- Fixed savepoint lifecycle events routed through child transaction ID.
- Fixed exception propagation in transaction rollback using
  `Error.throwWithStackTrace`.
- Removed leftover debug `print()` statements.

## 0.2.0

- Added `KnexMySQL.mariadb(...)` constructor for MariaDB connections.
- Propagated dialect identity through schema/query builder generation so MariaDB capability
  handling stays distinct from MySQL where needed.
- Added streaming query support in `MySQLClient` via `streamQuery(...)`.
- Added `universal_io` dependency for broader platform compatibility.

## 0.1.1

- Updated dependency to `knex_dart: ^1.1.0`.
- Transaction execution path aligned with core `runInTransaction(...)` hook.

## 0.1.0

- Initial release.
- MySQL driver for `knex_dart` using the `mysql_client` package.
- `KnexMySQL.connect()` factory for establishing a connection.
- Full query execution: select, insert, update, delete.
- Transaction support via `trx()`.
- Schema execution via `executeSchema()`.
