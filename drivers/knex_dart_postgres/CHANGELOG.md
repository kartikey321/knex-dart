## 0.3.2

- Raised `postgres` lower bound to `^3.5.12` to pick up critical transaction
  bug fixes: silent rollback after `ROLLBACK TO SAVEPOINT` recovery, connection
  permanently blocked when `BEGIN` fails inside `runTx`, and undefined
  connection state after a failed `ROLLBACK` (postgres 3.5.12).
- Users also gain typed exceptions (`UniqueViolationException`,
  `ForeignKeyViolationException`) and better stack traces from 3.5.x.

## 0.3.1

- Tighten `knex_dart` lower bound to `^1.2.1` — `QueryInterceptor`
  and `QueryExecutionContext` were not present before 1.2.1.

## 0.3.0

- Added `QueryInterceptor` pipeline support: attach OTel, logging, or custom
  interceptors via the `interceptors` parameter on `KnexPostgres.connect()`.
- Fixed savepoint lifecycle events routed through child transaction ID so OTel
  spans are correctly attributed to nested transactions.
- Fixed exception propagation in transaction rollback using
  `Error.throwWithStackTrace` to preserve original stack traces.
- Fixed savepoint ID generation to use a per-instance counter.
- Removed leftover debug `print()` statements.

## 0.2.0

- Added `KnexPostgres.cockroachdb(...)` constructor for CockroachDB connections.
- Added `KnexPostgres.redshift(...)` constructor for Amazon Redshift connections.
- Propagated dialect identity through schema/query builder generation so capability checks
  stay dialect-aware for PostgreSQL wire-compatible variants.
- Added `universal_io` dependency for broader platform compatibility.

## 0.1.1

- Updated dependency to `knex_dart: ^1.1.0`.
- Transaction execution path aligned with core `runInTransaction(...)` hook.

## 0.1.0

- Initial release.
- PostgreSQL driver for `knex_dart` using the `postgres` package.
- `KnexPostgres.connect()` factory for establishing a connection.
- Full query execution: select, insert, update, delete.
- Transaction support via `trx()`.
- Schema execution via `executeSchema()`.
