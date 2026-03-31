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
