## 0.4.1

- Bumped `sqlite3` to `^3.0.0` and `sqlite3_web` to `^0.9.0`; replaced
  deprecated `.dispose()` calls with `.close()` in the native and web
  clients.
- Bumped `lints` to `^6.1.0` and `test` to `^1.31.0`.

## 0.4.0

- Added `watch()` reactive query streams for SQLite based on `UPDATE_HOOK`.
- Added web/WASM storage mode selection via `webStorageMode` / `storageMode`
  with `memory`, `indexedDb`, `opfs`, and `auto` modes.
- Serialized concurrent top-level transactions across native and web clients.
- Buffered web SQLite update notifications through transaction boundaries to
  match native `watch()` semantics.
- Added coverage for concurrent transactions, reactive query behavior, and
  native/web storage mode handling.

## 0.3.0

- Added `QueryInterceptor` pipeline support: attach OTel, logging, or custom
  interceptors via the `interceptors` parameter on `KnexSQLite.connect()`.
- Fixed `destroyPool()` idempotency — double close no longer throws.
- Fixed `StateError` on query after close with a clear message.
- Improved exception propagation in transaction rollback using
  `Error.throwWithStackTrace` to preserve original stack traces.
- Fixed savepoint ID generation to use a per-instance counter instead of
  timestamp-based IDs, avoiding collisions under concurrent transactions.

## 0.2.1

- Reduced wrapper overhead by reusing compiled SQL through the interceptor
  pipeline instead of compiling the same query twice.
- Removed redundant async wrappers in low-level query dispatch while preserving
  public `Future` semantics and error propagation.
- Optimized native SQLite row mapping by reading `ResultSet` column names and
  rows directly.
- No query result shape, binding behavior, or SQL execution semantics changed.

## 0.2.0

- Added web/WASM SQLite support with conditional web client loading.
- Added async web client initialization and configurable WASM URL support via
  `connection['wasmUri']`, including fallback URI behavior.
- Added prepared statement caching in native SQLite client execution path.
- Added stream query support in native SQLite client.
- Updated dependencies for web/WASM compatibility (`sqlite3` update, `sqlite3_web`,
  and `universal_io`).

## 0.1.1

- Updated dependency to `knex_dart: ^1.1.0`.
- Uses core `runInTransaction(...)` migration transaction path with SQLite-safe behavior.

## 0.1.0

- Initial release.
- SQLite driver for `knex_dart` using the `sqlite3` package.
- `KnexSQLite.connect()` factory supporting file-based and in-memory databases.
- Full query execution: select, insert, update, delete.
- Transaction support via `trx()`.
- Schema execution via `executeSchema()`.
