## 0.3.1

- Bumped `lints` to `^6.1.0` and `test` to `^1.31.0` (no source changes).

## 0.3.0

- Added `KnexDialect.mssql` to the dialect enum and populated its capability
  entry (full outer join, CTE, window functions, JSON, INTERSECT/EXCEPT;
  no RETURNING support).

## 0.2.0

- Expanded dialect coverage to include `mariadb`, `redshift`, `turso`, `d1`,
  `duckdb`, `snowflake`, and `bigquery`.
- Extended capability matrix entries for new dialects and documented dialect-specific notes.
- Added driver-name normalization and aliases for new dialects in capability resolution.

## 0.1.0

- Initial release.
- Adds shared `SqlDialect` and `SqlCapability` enums.
- Adds centralized capability matrix used by runtime and lint tooling.
