# Skill: add-driver

Use when adding a new driver package under `drivers/knex_dart_<name>/`.

## Principles

- Start from the nearest existing driver instead of designing a new abstraction first.
- Keep SQL-generation changes in `packages/knex_dart/` unless the behavior is truly driver-specific.
- A new driver is not complete until workspace wiring, tests, docs, and release metadata are in place.

## Checklist

### 1. Pick the closest template

Use an existing driver as the base:

- PostgreSQL family: `drivers/knex_dart_postgres/`
- MySQL or MariaDB-like: `drivers/knex_dart_mysql/`
- Embedded local DBs: `drivers/knex_dart_sqlite/` or `drivers/knex_dart_duckdb/`
- HTTP / emulator-backed drivers: `drivers/knex_dart_d1/`, `drivers/knex_dart_bigquery/`, `drivers/knex_dart_turso/`

### 2. Create the standard package shape

Every driver should follow:

```text
drivers/knex_dart_<name>/
  lib/
    knex_dart_<name>.dart
    src/
      <name>_client.dart
      <name>_query_compiler.dart
      <name>_schema_compiler.dart
  test/
    integration/
  pubspec.yaml
```

### 3. Match the existing public wrapper API

The top-level wrapper should stay aligned with the other drivers:

- `connect(...)` or the equivalent named constructors
- `select`, `execute`, `insert`, `update`, `delete`
- `queryBuilder()`
- `schema` getter and `executeSchema(...)`
- `trx(...)`
- `close()` or the driver-appropriate shutdown method

Do not invent a driver-only surface unless the database genuinely requires it.

### 4. Wire the workspace and local tooling

Update:

- Root [pubspec.yaml](/Users/kartik/StudioProjects/knex/knex-dart/pubspec.yaml)
- [tool/run_tests.sh](/Users/kartik/StudioProjects/knex/knex-dart/tool/run_tests.sh)
- [Makefile](/Users/kartik/StudioProjects/knex/knex-dart/Makefile)
- [docker-compose.yml](/Users/kartik/StudioProjects/knex/knex-dart/docker-compose.yml) if the driver needs a local service

If the driver is server-backed, add health-check and teardown handling to the test runner.

### 5. Add tests at the right level

- Driver-specific behavior: `drivers/knex_dart_<name>/test/`
- Live DB behavior: `drivers/knex_dart_<name>/test/integration/` with the correct `@Tags([...])`
- Shared SQL compiler changes: `packages/knex_dart/test/`

Prefer copying the nearest existing driver test and adapting it.

### 6. Update capabilities and docs

- Add dialect support differences to `packages/knex_dart_capabilities/`
- Keep lint expectations aligned in `packages/knex_dart_lint/` when needed
- Add connection and support details to `docs/site/content/database-support.md`

### 7. Verify

Run the smallest useful set of checks first, then the full driver checks:

```bash
melos run analyze
make test-unit
make test-<name>
```
