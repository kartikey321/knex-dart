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
