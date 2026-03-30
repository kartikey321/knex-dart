## 1.1.0

- Added filesystem/config migration source support via `fromConfig()`.
- Added auto-registration of `JsonSchemaAdapter` for `fromSchema(...)`.
- Added `Client.runInTransaction(...)` hook and integrated migrator transaction path.
- Added lateral joins API (`joinLateral`, `leftJoinLateral`, `crossJoinLateral`).
- Added and published supporting packages:
  - `knex_dart_capabilities` (`0.1.0`)
  - `knex_dart_lint` (`0.1.0`)
- Documentation updates for migrations and optional dialect lint tooling.

## 1.0.0

- Initial stable release.
- SQL query builder core: SELECT, INSERT, UPDATE, DELETE.
- WHERE clauses, JOINs, aggregates, ORDER BY, GROUP BY, HAVING, LIMIT, OFFSET.
- Raw queries, CTEs, UNIONs, INTERSECTs, EXCEPTs, subqueries.
- JSON operators, full-text search, upserts (`onConflict().merge()`).
- Schema builder: createTable, alterTable, dropTable, foreign keys, indexes.
- Dialect-aware SQL generation (PostgreSQL `$1`, MySQL/SQLite `?`).
- 551+ tests passing with >85% coverage.
- Driver packages published separately: `knex_dart_postgres`, `knex_dart_mysql`, `knex_dart_sqlite`.
