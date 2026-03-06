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
