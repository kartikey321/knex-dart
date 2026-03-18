# =============================================================================
# knex-dart — multi-stage test image
#
# Build a specific target to get an environment ready to test that driver:
#
#   docker build --target test-postgres -t knex-test-postgres docker/
#   docker build --target test-mysql    -t knex-test-mysql    docker/
#   docker build --target test-mssql    -t knex-test-mssql    docker/
#   docker build --target test-duckdb   -t knex-test-duckdb   docker/
#   docker build --target test-sqlite   -t knex-test-sqlite   docker/
#   docker build --target test-http     -t knex-test-http     docker/
#
# Or use docker compose (see docker-compose.yml):
#   docker compose --profile test run dart-test-postgres
# =============================================================================

# ── Base: Dart SDK + workspace ────────────────────────────────────────────────
FROM dart:stable AS base

WORKDIR /workspace
COPY . .
RUN dart pub get

# ── test-http ─────────────────────────────────────────────────────────────────
# HTTP-based drivers (Turso, D1, Snowflake, BigQuery, MSSQL-REST).
# No native library dependencies — pure Dart + http package.
FROM base AS test-http

CMD ["sh", "-c", " \
  echo '=== Turso (mock) ===' && dart test drivers/knex_dart_turso/test/turso_test.dart && \
  echo '=== D1 (mock) ===' && dart test drivers/knex_dart_d1/test/d1_test.dart && \
  echo '=== Snowflake (mock) ===' && dart test drivers/knex_dart_snowflake/test/snowflake_test.dart && \
  echo '=== BigQuery (mock) ===' && dart test drivers/knex_dart_bigquery/test/bigquery_test.dart \
"]

# ── test-sqlite ───────────────────────────────────────────────────────────────
# SQLite via the sqlite3 Dart package (links against libsqlite3).
FROM base AS test-sqlite

RUN apt-get update && apt-get install -y --no-install-recommends \
      libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace/drivers/knex_dart_sqlite
CMD ["dart", "test"]

# ── test-duckdb ───────────────────────────────────────────────────────────────
# DuckDB via the dart_duckdb FFI package.
# Downloads the appropriate libduckdb.so at image-build time.
FROM base AS test-duckdb

ARG DUCKDB_VERSION=v1.2.2

RUN apt-get update && apt-get install -y --no-install-recommends curl unzip \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL \
       "https://github.com/duckdb/duckdb/releases/download/${DUCKDB_VERSION}/libduckdb-linux-amd64.zip" \
       -o /tmp/libduckdb.zip \
    && unzip -o /tmp/libduckdb.zip libduckdb.so -d /usr/local/lib/ \
    && ldconfig \
    && rm /tmp/libduckdb.zip

WORKDIR /workspace/drivers/knex_dart_duckdb
CMD ["dart", "test"]

# ── test-postgres ─────────────────────────────────────────────────────────────
# PostgreSQL driver.  Expects a Postgres service reachable via env vars.
FROM base AS test-postgres

# psql for schema setup scripts
RUN apt-get update && apt-get install -y --no-install-recommends postgresql-client \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace/drivers/knex_dart_postgres
CMD ["dart", "test", "--tags=postgres"]

# ── test-mysql ────────────────────────────────────────────────────────────────
# MySQL driver.  Expects a MySQL service reachable via env vars.
FROM base AS test-mysql

RUN apt-get update && apt-get install -y --no-install-recommends default-mysql-client \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace/drivers/knex_dart_mysql
CMD ["dart", "test", "--tags=mysql"]

# ── test-mssql ────────────────────────────────────────────────────────────────
# SQL Server driver via mssql_connection (FreeTDS FFI).
FROM base AS test-mssql

RUN apt-get update && apt-get install -y --no-install-recommends \
      freetds-dev \
      libct4 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace/drivers/knex_dart_mssql
CMD ["dart", "test", "--tags=mssql"]

# ── test-turso-integration ────────────────────────────────────────────────────
# Turso driver integration tests against a real sqld server.
FROM base AS test-turso-integration

WORKDIR /workspace/drivers/knex_dart_turso
CMD ["dart", "test", "test/integration/turso_integration_test.dart", "--tags=turso"]

# ── test-bigquery-integration ─────────────────────────────────────────────────
# BigQuery driver integration tests against the bigquery-emulator.
FROM base AS test-bigquery-integration

WORKDIR /workspace/drivers/knex_dart_bigquery
CMD ["dart", "test", "test/integration/bigquery_integration_test.dart", "--tags=bigquery"]
