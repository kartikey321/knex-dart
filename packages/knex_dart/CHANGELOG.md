## 1.3.0

- Added the public `WatchableClient` contract for drivers that support
  reactive query streams.
- Exported the doc snippet runtime helpers used by the docs site and playground
  through the public `knex_dart` API.
- Added executable doc snippet runtime support and regression coverage for
  snippet wrapping and dialect validation.
- Documentation updates for runnable snippets and SQLite reactive examples.

## 1.2.1

- Improved query compilation hot paths by replacing timestamp/random UID
  generation with per-isolate counters.
- Avoided enum string splitting when resolving compiled query methods.
- Documented the public `QueryInterceptor` / `QueryExecutionContext` pipeline
  used by live driver wrappers for tracing, metrics, logging, and policy hooks.
- Added a compiled-query interceptor path so driver wrappers can avoid
  compiling the same query twice when interceptors are installed.
- No SQL escaping, binding, identifier wrapping, or generated SQL semantics
  changed in this release.

## 1.2.0

- Added `KnexQuery` for dialect-only SQL generation via `KnexQuery.forDialect(...)` and `KnexQuery.forClient(...)`.
- Added schema parity APIs in `SchemaBuilder` and `SchemaCompiler`, including:
  `createTableLike`, `hasTable`, `hasColumn`, `renameView`, view/materialized-view operations,
  schema operations, extension operations, and `schema.raw(...)`.
- Improved cross-dialect schema SQL generation for MSSQL and MySQL-family paths
  (dialect-specific `dropTableIfExists`, `renameTable`, and fulltext alter support).
- Improved query compilation behavior for function-style subqueries, analytic `OVER(...)`
  handling, and MSSQL `LIMIT/OFFSET` SQL generation.
- Internal workspace refactor: core package moved under `packages/knex_dart`
  with no user-facing import path change.

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
