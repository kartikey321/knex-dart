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
