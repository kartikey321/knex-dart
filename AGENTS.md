# knex_dart Agent Guide

Canonical agent-facing guide for the knex_dart monorepo. Read this before making any changes.

## Repo Map

```
packages/
  knex_dart/               # Core query builder — published to pub.dev
  knex_dart_capabilities/  # Shared dialect capability matrix (which features each dialect supports)
  knex_dart_lint/          # Custom lint rules for dialect-aware static analysis
drivers/
  knex_dart_postgres/      # PostgreSQL driver (postgres ^3.x)
  knex_dart_mysql/         # MySQL driver
  knex_dart_sqlite/        # SQLite driver
  knex_dart_duckdb/        # DuckDB driver
  knex_dart_mssql/         # Microsoft SQL Server driver
  knex_dart_turso/         # Turso (libSQL) driver
  knex_dart_bigquery/      # BigQuery driver
  knex_dart_d1/            # Cloudflare D1 driver
  knex_dart_snowflake/     # Snowflake driver
integrations/
  knex_dart_otel/          # OpenTelemetry instrumentation for live driver wrappers
docs/site/                 # Jaspr-based documentation site (served at docs.knex.mahawarkartikey.in)
playground/                # Vite + TypeScript browser playground (deployed to Cloudflare Pages)
tool/run_tests.sh          # Cross-driver test runner (wraps Docker + dart test)
docker-compose.yml         # DB services for local driver testing
```

All packages use `resolution: workspace` (melos monorepo). Root `pubspec.yaml` is the workspace manifest.

## Architecture

- **`KnexQuery.forDialect(KnexDialect)` / `KnexQuery.forClient(String)`** — SQL generation only; produces dialect-correct SQL without a live database connection
- **Driver wrappers** — `KnexPostgres`, `KnexMySQL`, `KnexSQLite`, `KnexDuckDB`, etc. provide live query execution, schema execution, and transactions
- **`Client`** — abstract base for all drivers; exposes `onQuery`, `onQueryError`, `onQueryResponse` broadcast streams (each event carries a `uid` for correlation)
- **`QueryBuilder` / `SchemaBuilder`** — fluent builders shared across dialects
- **`QueryCompiler` / `SchemaCompiler`** — dialect-specific SQL generation; drivers override these only where behavior differs
- **`knex_dart_capabilities`** — `DialectCapabilities` matrix; used by lint rules to flag unsupported features at analysis time

## Required Workflow

- **Change the narrowest package possible.** Core SQL generation changes go in `packages/knex_dart/`. Driver-specific behavior goes in the relevant `drivers/` package. Cross-cutting integrations such as OpenTelemetry go in `integrations/`.
- For any core change that affects SQL output, add or update a unit test in `packages/knex_dart/test/`.
- For any driver behavior change, add or update an integration test in `drivers/knex_dart_<name>/test/integration/`.
- Keep `docs/site/content/` pages aligned with any API additions or behavior changes.
- If a feature's availability differs by dialect, update `knex_dart_capabilities` and the lint rules.

## Commands

### Bootstrap
```bash
dart pub global activate melos
melos bs          # or: dart pub get (at workspace root)
```

### Analysis
```bash
melos run analyze                    # dart analyze --fatal-warnings across all packages
```

### Testing (local)
```bash
make test-unit                       # Core unit tests — no Docker needed
make test-<driver>                   # e.g. make test-postgres, make test-sqlite
make test-all                        # All drivers sequentially (starts/stops Docker per driver)
make db-up                           # Start all DB containers
make db-down                         # Stop and remove all DB containers
```

Server-backed drivers (need Docker): `postgres`, `mysql`, `mssql`, `turso`, `bigquery`
Embedded/mock (no Docker): `sqlite`, `duckdb`, `d1`, `snowflake`

The underlying runner is `tool/run_tests.sh [driver]`. CI uses `dart test --tags=<driver>` directly.

### Coverage
```bash
make coverage                        # Generates coverage/lcov.info for core package
```

### Playground (dev)
```bash
cd playground && npm ci && npm run dev    # http://localhost:5177
```

### Docs (dev)
```bash
cd docs/site && jaspr serve     # http://localhost:8080
```

## Driver Pattern

Each driver in `drivers/knex_dart_<name>/` follows this shape:

```
lib/
  knex_dart_<name>.dart      # exports <Name>Client (extends Client)
  src/
    <name>_client.dart
    <name>_query_compiler.dart
    <name>_schema_compiler.dart
test/
  integration/               # tagged tests (--tags=<name>), need live DB
  <name>_test.dart           # mock/unit tests, no live DB
pubspec.yaml                 # resolution: workspace; depends on knex_dart: ^x.y.z
```

For Claude users, `.claude/skills/add-driver/SKILL.md` has a step-by-step contributor checklist. `AGENTS.md` remains the tool-agnostic source of truth.

## CI/CD

- **`.github/workflows/ci.yml`** — runs on push/PR; tests each driver against GitHub Actions service containers
- **`.github/workflows/deploy_docs.yml`** — deploys docs on `docs-v*.*.*` tags to Cloudflare Pages
- **`.github/workflows/deploy_playground.yml`** — deploys playground on `playground-v*.*.*` tags to Cloudflare Pages
- Required secrets: `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`

## Release Process

- Packages are versioned independently. Bump `version` in the package's `pubspec.yaml`.
- Update `CHANGELOG.md` in the affected package.
- Push a tag: `git tag knex_dart-v<x.y.z>` (or `knex_dart_postgres-v<x.y.z>`, etc.) then `git push --tags`.
- Playground release: `git tag playground-v<x.y.z> && git push --tags`
- Docs release: `git tag docs-v<x.y.z> && git push --tags`

## Docs Site

Content lives in `docs/site/content/` as Markdown. Pages map to URLs directly:
- `content/index.md` → `/`
- `content/query-building/joins.md` → `/query-building/joins`
- etc.

The Jaspr site is built with `dart run jaspr build`. Static assets go in `docs/site/web/`. Raw markdown mirrors are served under `/raw/...`.
