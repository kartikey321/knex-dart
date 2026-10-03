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

### Before bumping a version: check what's actually pending

Don't rely on eyeballing `pubspec.yaml`'s version against pub.dev — it's
unreliable in both directions (a package can have real unreleased changes
sitting on `main` with no version bump to show for it, or show as
"published" with no corresponding git tag at all because someone ran
`dart pub publish` by hand). Run:

```bash
dart run tool/check_release_status.dart            # cross-checks pub.dev too
dart run tool/check_release_status.dart --offline   # skip the network calls
```

For every publishable package this reports: the current `pubspec.yaml`
version, what `tool/release_state.json` says was actually last published and
from which commit, the latest matching git tag (if any), pub.dev's live
version, and — the useful part — every commit since the last real release
that touched `lib/`/`bin`/`pubspec.yaml` (test-only changes are called out
separately since they usually don't need a version bump). It flags:
`NEEDS A VERSION BUMP` when there are unreleased shippable changes,
`MISMATCH`/`disagrees` when the state file, the git tag, and pub.dev don't
all agree, and `NOT IN release_state.json` for anything that's never been
recorded (shouldn't happen for any current package; would mean a new package
was added without bootstrapping an entry).

### `tool/release_state.json` — the source of truth for "what's released"

This file records, per package, `lastPublishedVersion` / `lastPublishedCommit`
/ `lastPublishedAt`. **It's written only by CI**, as the final step of the
"Publish to pub.dev" job in `.github/workflows/ci.yml`
(`tool/record_release_state.dart`), immediately after `melos publish`
succeeds — never by hand, and never as part of a feature PR. It exists
specifically because git tags alone weren't reliable: `knex_dart_otel` is
live on pub.dev with no matching tag in this repo's history at all, which a
tag-only check can't detect but this file's cross-check against pub.dev can.

If you ever publish manually outside the tag-triggered CI flow (should be
rare — only ever necessary for a genuinely new package's first publish,
which pub.dev requires to happen from an authenticated local machine), update
`tool/release_state.json` yourself in the same commit so it doesn't drift:
record the version, the commit you published from, the timestamp, and set
`"source"` to something identifiable (e.g. `"manual:<your reason>"`) instead
of the `"ci:tag:..."` shape CI writes.

## Docs Site

Content lives in `docs/site/content/` as Markdown. Pages map to URLs directly:
- `content/index.md` → `/`
- `content/query-building/joins.md` → `/query-building/joins`
- etc.

The Jaspr site is built with `dart run jaspr build`. Static assets go in `docs/site/web/`. Raw markdown mirrors are served under `/raw/...`.
