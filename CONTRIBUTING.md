# Contributing to Knex Dart

Thank you for your interest in contributing!

## Repository Structure

This is a Melos monorepo. The root package (`knex_dart`) is the core query builder. Database drivers live under `drivers/`:

```
knex-dart/
├── lib/                        # Core query builder (knex_dart)
├── test/                       # Core unit tests (551+, no DB required)
├── drivers/
│   ├── knex_dart_postgres/     # PostgreSQL driver
│   ├── knex_dart_mysql/        # MySQL driver
│   └── knex_dart_sqlite/       # SQLite driver
└── docs/site/                  # Documentation site (Jaspr)
```

## Development Setup

```bash
git clone https://github.com/kartikey321/knex-dart.git
cd knex-dart

# Install melos globally
dart pub global activate melos

# Install all dependencies
dart pub get   # or: melos bs
```

## Running Tests

```bash
# Core unit tests (no DB required)
melos run test:unit

# SQLite integration tests
cd drivers/knex_dart_sqlite && dart test

# PostgreSQL integration tests (requires a running Postgres instance)
PG_HOST=localhost PG_PORT=5432 PG_DATABASE=knex_test PG_USER=knex PG_PASSWORD=knex \
  dart test --tags=postgres -C drivers/knex_dart_postgres

# MySQL integration tests (requires a running MySQL instance)
MYSQL_HOST=127.0.0.1 MYSQL_PORT=3306 MYSQL_DATABASE=knex_test MYSQL_USER=knex MYSQL_PASSWORD=knex \
  dart test --tags=mysql -C drivers/knex_dart_mysql
```

### Running a local DB with Docker

**PostgreSQL:**
```bash
docker run -d --name pg_test \
  -e POSTGRES_USER=knex -e POSTGRES_PASSWORD=knex -e POSTGRES_DB=knex_test \
  -p 5432:5432 postgres:16
psql -h localhost -U knex -d knex_test -f drivers/knex_dart_postgres/test/integration/sql/postgres_schema.sql
psql -h localhost -U knex -d knex_test -f drivers/knex_dart_postgres/test/integration/sql/postgres_seed.sql
```

**MySQL:**
```bash
docker run -d --name mysql_test \
  -e MYSQL_ROOT_PASSWORD=root -e MYSQL_DATABASE=knex_test -e MYSQL_USER=knex -e MYSQL_PASSWORD=knex \
  -p 3306:3306 mysql:8.0 --default-authentication-plugin=mysql_native_password
docker exec -i mysql_test mysql -u knex -pknex knex_test < drivers/knex_dart_mysql/test/integration/sql/mysql_schema.sql
docker exec -i mysql_test mysql -u knex -pknex knex_test < drivers/knex_dart_mysql/test/integration/sql/mysql_seed.sql
```

## Static Analysis

```bash
melos run analyze   # runs dart analyze --fatal-warnings across all packages
```

## Pull Requests

1. Fork and create a feature branch: `git checkout -b feature/my-feature`
2. Write tests for your changes
3. Ensure all relevant tests pass and `melos run analyze` is clean
4. Submit a PR with a clear description

### Testing Philosophy

- **Core unit tests** cover all SQL generation logic — every new query feature needs a unit test here
- **Integration tests** verify execution against a real DB — add one if you're touching driver code
- Comparison against Knex.js output is strongly encouraged for query generation tests

## Adding a New Driver

1. Create `drivers/knex_dart_<name>/` following the existing driver structure
2. Add the path to `workspace:` in the root `pubspec.yaml`
3. Implement `Client` from `knex_dart` and a typed connect factory
4. Add schema/seed SQL and integration tests tagged with `@Tags(['<name>'])`
5. Add a CI job in `.github/workflows/ci.yml`

## Priority Areas

- Window / analytic functions
- Connection pooling
- Nested / savepoint transaction semantics
- Additional database drivers (MSSQL, DuckDB)
- Documentation improvements

## Reporting Issues

Open an issue on [GitHub](https://github.com/kartikey321/knex-dart/issues). Please include:
- Dart SDK version
- Code snippet reproducing the issue
- Expected vs actual SQL output
- For query generation bugs, the equivalent Knex.js output is helpful
