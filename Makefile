.PHONY: help db-up db-down test-all test-postgres test-mysql test-sqlite test-duckdb test-mssql test-turso test-bigquery test-d1 test-snowflake test-unit analyze coverage bench-sql bench-sqlite bench-matrix bench-all example-otel-sqlite check-docs check-docs-runtime check-docs-runtime-postgres check-docs-runtime-mysql check-docs-runtime-mssql snapshot-docs snapshot-docs-postgres snapshot-docs-mysql snapshot-docs-mssql update-versions

# Local development only — not used in CI.
# CI uses `dart test --tags=<driver>` directly against GitHub Actions service containers.
# See .github/workflows/ci.yml for the canonical test commands.

help: ## List available targets
	@grep -E '^[a-zA-Z0-9_.-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "%-18s %s\n", $$1, $$2}'

db-up: ## Start all database services
	docker compose up -d postgres mysql mssql mssql-init sqld bigquery

db-down: ## Stop and remove database services
	docker compose stop postgres mysql mssql-init mssql sqld bigquery || true
	docker compose rm -f postgres mysql mssql-init mssql sqld bigquery || true

test-all: ## Run tests for all drivers
	./tool/run_tests.sh

test-postgres: ## Run PostgreSQL driver tests
	./tool/run_tests.sh postgres

test-mysql: ## Run MySQL driver tests
	./tool/run_tests.sh mysql

test-sqlite: ## Run SQLite driver tests
	./tool/run_tests.sh sqlite

test-duckdb: ## Run DuckDB driver tests
	./tool/run_tests.sh duckdb

test-mssql: ## Run MSSQL driver tests
	./tool/run_tests.sh mssql

test-turso: ## Run Turso driver tests
	./tool/run_tests.sh turso

test-bigquery: ## Run BigQuery driver tests
	./tool/run_tests.sh bigquery

test-d1: ## Run D1 driver tests
	./tool/run_tests.sh d1

test-snowflake: ## Run Snowflake driver tests
	./tool/run_tests.sh snowflake

test-unit: ## Run core unit tests only
	dart test packages/knex_dart/test --exclude-tags=postgres,mysql,sqlite,turso,bigquery,mssql,duckdb

analyze: ## Run static analysis across workspace
	melos run analyze

check-docs: ## Validate doc snippets and README version constraints
	dart run tool/check_doc_snippets.dart

check-docs-runtime: ## Execute runnable local doc snippets
	dart run tool/check_doc_snippets.dart --mode=run --scope=local

check-docs-runtime-postgres: ## Execute runnable PostgreSQL doc snippets
	dart run tool/check_doc_snippets.dart --mode=run --scope=postgres

check-docs-runtime-mysql: ## Execute runnable MySQL doc snippets
	dart run tool/check_doc_snippets.dart --mode=run --scope=mysql

check-docs-runtime-mssql: ## Execute runnable MSSQL doc snippets
	dart run tool/check_doc_snippets.dart --mode=run --scope=mssql

snapshot-docs: ## Auto-generate expect_stdout in local doc:run directives
	dart run tool/check_doc_snippets.dart --mode=snapshot --scope=local

snapshot-docs-postgres: ## Auto-generate expect_stdout in PostgreSQL doc:run directives
	dart run tool/check_doc_snippets.dart --mode=snapshot --scope=postgres

snapshot-docs-mysql: ## Auto-generate expect_stdout in MySQL doc:run directives
	dart run tool/check_doc_snippets.dart --mode=snapshot --scope=mysql

snapshot-docs-mssql: ## Auto-generate expect_stdout in MSSQL doc:run directives
	dart run tool/check_doc_snippets.dart --mode=snapshot --scope=mssql

update-versions: ## Sync README version constraints from pubspec.yaml (run after version bumps)
	dart run tool/update_readme_versions.dart

coverage: ## Generate coverage/lcov.info for core package
	dart test packages/knex_dart/test --coverage=coverage
	dart pub global activate coverage
	dart pub global run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --packages=.dart_tool/package_config.json --report-on=packages/knex_dart/lib
	@if [ "$(shell uname)" = "Darwin" ]; then \
		sed -i '' 's|SF:.*/packages/knex_dart/lib|SF:packages/knex_dart/lib|' coverage/lcov.info; \
	else \
		sed -i 's|SF:.*/packages/knex_dart/lib|SF:packages/knex_dart/lib|' coverage/lcov.info; \
	fi

bench-sql:
	dart run benchmarks/bin/sql_generation.dart

bench-sqlite:
	dart run benchmarks/bin/sqlite_live.dart

bench-matrix:
	dart run benchmarks/bin/run_matrix.dart

bench-all: bench-sql bench-sqlite bench-matrix

example-otel-sqlite:
	cd examples/knex_otel_sqlite_app && dart run bin/sqlite_otel_collector.dart
