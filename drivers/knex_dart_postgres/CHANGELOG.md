## 0.3.3

- Fixed a data-corruption bug in `PostgresClient.runInTransaction()`: two
  concurrent calls on the same client instance could silently share one
  pinned transaction session, causing one caller's writes to be discarded
  by the other's unrelated rollback — while the affected call still
  returned successfully, with no exception, giving no indication its data
  was lost. In the worst case a caller's own writes could be torn in half
  across the session boundary (part rolled back, part autocommitted
  outside any transaction).
  The pinned session is now stored per-`Zone` instead of in a plain
  instance field, keyed by an object unique to each `PostgresClient`
  instance, so each top-level `runInTransaction()` call gets its own
  isolated session while genuine nested/reentrant calls (made from within
  the same call's own `action`) still correctly reuse it. `trx()` was
  already safe and is unaffected.
  A detached `Future`/`Timer`/stream listener started inside `action` but
  not awaited before it returns now fails with a clear `StateError` if it
  later tries to run a query, instead of risking reuse of a session whose
  connection may already be back in the pool.

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
