## 0.3.2

- Fixed: every dialect-aware rule silently skipped code written as
  `KnexQuery.forDialect(KnexDialect.mssql)`. The resolver behind
  `forDialect(...)` was a hand-written switch that listed ten of the eleven
  `KnexDialect` values and omitted `mssql`, so it returned `null` and each rule
  took its "dialect unknown, say nothing" path. No warning, no hint that the
  file was going unchecked — the lints simply did not apply to MSSQL code.
  The argument is an enum member name, so it is now matched against
  `KnexDialect.values` instead of a switch, which cannot drift as dialects are
  added — a new `KnexDialect` member resolves through the lookup with no
  resolver change at all. A test iterates the enum and asserts every value
  resolves through `forDialect(...)`, so reintroducing a hand-written switch
  that omits a dialect fails CI instead of quietly disabling the rules for it.

  The resolver also now requires the argument's qualifier to be `KnexDialect`.
  Previously only the trailing identifier was read, so any expression ending in
  a dialect name was taken for that dialect: a field called `mssql` holding a
  Postgres value resolved to MSSQL, and the dialect-aware rules then reported
  valid Postgres code against SQL Server. Prefixed imports
  (`knex.KnexDialect.mssql`) still resolve.

- `knex_dart_capabilities` is now required at `^0.3.2`, not `^0.3.0`. The
  resolver recognising `KnexDialect.mssql` is only correct against a capability
  map that marks `returning` as supported there, which 0.3.2 added; with an
  older capabilities pinned in a lockfile, `dialect_unsupported_returning`
  would have flagged valid MSSQL `.returning()` calls. Before this release the
  dialect resolved to `null` and the rules stayed silent, so tightening the
  constraint is what stops the fix turning "no lints" into "wrong lints".

## 0.3.1

- Migrated the plugin from the archived `custom_lint_builder` to
  `analysis_server_plugin ^0.3.0`: all 15 rules moved from
  `DartLintRule` + `run()` to `AnalysisRule` + `registerNodeProcessors()` +
  a `_Visitor` pattern, and a `lib/main.dart` plugin entry point was added.
- Bumped `lints` to `^6.1.0` and `test` to `^1.31.0`.

## 0.3.0

- Added `raw_null_identifier_binding` lint rule (WARNING): fires when a `:key:`
  identifier binding in `raw()`, `rawSql()`, `whereRaw()`, `havingRaw()`,
  `orderByRaw()`, or `groupByRaw()` is assigned `null`, which leaves the
  placeholder unresolved and produces invalid SQL at runtime.
- Added MSSQL dialect support to dialect resolution and rule utilities.
- Bumped `knex_dart_capabilities` constraint to `^0.3.0`.

## 0.2.0

- Expanded dialect inference to cover additional constructor patterns and driver families.
- Added support for dialect detection from:
  `KnexQuery.forDialect(...)`, `KnexQuery.forClient(...)`,
  and named constructors such as `KnexPostgres.redshift(...)`,
  `KnexPostgres.cockroachdb(...)`, and `KnexMySQL.mariadb(...)`.
- Added lint-side dialect labels for `mariadb`, `redshift`, `turso`, `d1`,
  `duckdb`, `snowflake`, and `bigquery`.

## 0.1.0

- Initial release.
- Adds optional `custom_lint` plugin for knex_dart.
- Includes dialect compatibility and query-argument validation rules.
