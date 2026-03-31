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
