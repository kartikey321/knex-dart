# Skill: run-tests

Run knex_dart tests locally.

## Decision tree

**Changed only `packages/knex_dart/`?**
→ `make test-unit` — no Docker needed, fast.

**Changed a specific driver?**
→ `make test-<driver>` — starts/stops Docker automatically for server-backed drivers.

**Changed shared code (capabilities, core compilers, query builder APIs)?**
→ `make test-unit` plus each affected driver target.

**Changed docs or playground only?**
→ Run the relevant site build instead of the database matrix:
- `cd docs/site && dart run jaspr build`
- `cd playground && npm run check && npm run build`

**Before opening a PR?**
→ `melos run analyze && make test-unit` at minimum. CI will run all drivers.

## Commands

```bash
# Core unit tests — no Docker required
make test-unit

# Single driver (Docker auto-managed)
make test-postgres
make test-mysql
make test-sqlite       # no Docker
make test-duckdb       # no Docker
make test-mssql
make test-turso
make test-bigquery
make test-d1           # no Docker (mock)
make test-snowflake    # no Docker (mock)

# All drivers sequentially
make test-all

# Mock-only HTTP-style drivers together
./tool/run_tests.sh http

# Manual Docker control
make db-up             # start all DB services
make db-down           # stop and remove all DB containers
```

## Server-backed drivers (need Docker)

| Driver | Container | Health check |
|--------|-----------|--------------|
| postgres | `knex_dart_postgres` | healthy |
| mysql | `knex_dart_mysql` | healthy |
| mssql | `knex_dart_mssql` + `knex_dart_mssql_init` | healthy + exit 0 |
| turso | `knex_dart_sqld` | healthy |
| bigquery | `knex_dart_bigquery` | healthy |

## Environment variables (if running dart test directly)

```bash
# Postgres
cd drivers/knex_dart_postgres
PG_HOST=localhost PG_PORT=5432 PG_DATABASE=knex_test PG_USER=knex PG_PASSWORD=knex \
  dart test --tags=postgres

# MySQL
cd drivers/knex_dart_mysql
MYSQL_HOST=localhost MYSQL_PORT=3306 MYSQL_DATABASE=knex_test MYSQL_USER=knex MYSQL_PASSWORD=knex \
  dart test --tags=mysql

# MSSQL (also needs libsybdb.dylib symlinked on macOS)
cd drivers/knex_dart_mssql
MSSQL_HOST=127.0.0.1 MSSQL_PORT=1433 MSSQL_DATABASE=knex_test MSSQL_USER=sa MSSQL_PASSWORD='Knex_Test1!' \
  dart test --tags=mssql

# Turso
cd drivers/knex_dart_turso
TURSO_URL=http://localhost:8080 dart test test/integration/turso_integration_test.dart --tags=turso

# BigQuery
cd drivers/knex_dart_bigquery
BIGQUERY_EMULATOR_HOST=http://localhost:9050 BIGQUERY_PROJECT=knex-test BIGQUERY_DATASET=knex_dataset \
  dart test test/integration/bigquery_integration_test.dart --tags=bigquery
```

## Notes

- `tool/run_tests.sh` is the canonical runner; the `make test-*` targets call it.
- CI does NOT use `run_tests.sh` — it uses `dart test --tags=<driver>` directly against GitHub Actions service containers.
- Analysis runs separately: `melos run analyze` (runs with concurrency 1 to avoid analyzer plugin cache races).
- `make test-unit` runs only the core package tests under `packages/knex_dart/test`.
