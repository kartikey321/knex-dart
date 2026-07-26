## 1.3.1

Correctness fixes surfaced by an adversarial knex.js-vs-knex-dart comparison
review and a new differential schema-DDL parity harness (`test/parity/`).
No breaking changes and no new public API — every item below is a bug fix to
existing behavior.

**Query compiler**
- `.onConflict().merge().where(...)` no longer silently drops the WHERE
  clause; MySQL now correctly refuses this combination instead of emitting
  wrong SQL.
- Fixed `$N` placeholder corruption in subqueries, lateral joins, `WHERE
  EXISTS`, `UNION`, and CTEs once binding counts reached double digits (was
  renumbering `$11` as `$101`).
- Ragged multi-row `INSERT` (rows with different keys) now fills missing
  cells with `DEFAULT` instead of misaligning columns; SQLite-family
  dialects refuse rather than emit invalid SQL for this case.
- `UPDATE`/`DELETE` no longer drop a preceding `WITH` (CTE) clause.
- Fixed dotted/qualified column names in aggregate `GROUP BY`/array forms.
- `.onConflict().ignore()` now refuses on dialects that don't support it
  instead of emitting broken SQL; MySQL's `ON DUPLICATE KEY UPDATE` merge
  form now correctly lowercases `values(...)`.
- Postgres-family `?` (jsonb key-existence) operator no longer leaks a
  stray backslash into the emitted SQL.
- `where(column, null)` now has correct null-shorthand semantics; added
  `orWhereIn`, `leftOuterJoin`/`rightOuterJoin`/`outerJoin`, and list-based
  `groupBy`.

**Schema compiler**
- `table.primary()`, `table.unique()`, and `table.index()` declared inside
  `createTable()` are no longer silently dropped — folded inline into the
  `CREATE TABLE` statement where required (SQLite-family) or emitted as
  proper deferred `ALTER TABLE` statements otherwise.
- Foreign keys declared inside `createTable()` (both `.references().inTable()`
  and fluent `table.foreign()`) were silently dropped entirely on
  SQLite/turso/d1; now folded inline into the `CREATE TABLE` statement.
- `alterTable().primary()`, `dropPrimary()`, `dropForeign()`, and
  `alterTable().foreign()` now correctly refuse on SQLite/turso/d1 (which
  can't `ALTER TABLE ADD/DROP CONSTRAINT`) instead of emitting invalid SQL.
- **turso and d1 were falling through to Postgres-shaped SQL for almost every
  schema operation** — most dialect-dispatch checks compared
  `driverName == 'sqlite' || 'sqlite3'` literally instead of using the
  family-aware helper that already covered turso/d1. Affected: `dropUnique`,
  `dropIndex`, primary-key folding, foreign-key folding, and every column
  type mapping (`increments`, booleans, datetimes, JSON, etc.) in
  `TableBuilder`.
- Redshift `increments()`/`bigIncrements()` now emit `IDENTITY(1,1)` instead
  of Postgres's `SERIAL`, which Redshift doesn't support.
- Redshift `index()`/`dropIndex()` now refuse (Redshift has no
  `CREATE INDEX`/`DROP INDEX`) instead of emitting SQL Redshift rejects at
  execution time.
- `enu()` (enum) values containing a single quote are now correctly escaped.
- Custom constraint/index names passed to `unique()`/`dropIndex()` are no
  longer ignored.

Verified against real Postgres, MySQL, SQLite, and turso (sqld) instances,
and against a real CockroachDB and local D1 instance for the two dialects
without a live driver in this repo. See `tool/parity/README.md` for the
differential harness this was built and checked against.

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
