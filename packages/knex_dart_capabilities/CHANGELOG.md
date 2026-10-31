## 0.3.2

- `SqlCapability.returning` is now set for `sqlite`, `turso`, `d1` and `mssql`,
  not just `postgres`. SQLite >= 3.35 supports `RETURNING` on INSERT/UPDATE
  (and turso/d1 inherit it), and MSSQL expresses the same thing as
  `OUTPUT inserted.*` / `OUTPUT deleted.*`, which `knex_dart` 1.3.4+ compiles.
  Previously `dialect_unsupported_returning` warned on correct code for all
  four.

  One asymmetry is deliberately not modelled here: SQLite supports `RETURNING`
  on INSERT and UPDATE but never on DELETE, which a single per-dialect flag
  cannot express. The DELETE carve-out lives in
  `QueryCompiler._deleteQuery`, so the flag being set does not by itself mean
  `.returning()` works on every verb.

- `dialectFromDriverName('mssql')` now resolves to `KnexDialect.mssql`; it
  previously returned `null` because the switch had no `mssql` case.

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
