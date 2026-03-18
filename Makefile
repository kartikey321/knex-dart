.PHONY: help db-up db-down test-all test-postgres test-mysql test-sqlite test-duckdb test-mssql test-turso test-bigquery test-d1 test-snowflake test-unit analyze coverage

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
	dart test --exclude-tags=postgres,mysql,sqlite,turso,bigquery,mssql,duckdb

analyze: ## Run static analysis across workspace
	melos run analyze

coverage: ## Generate coverage/lcov.info for root package
	dart test --coverage=coverage
	dart pub global activate coverage
	dart pub global run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --packages=.dart_tool/package_config.json --report-on=lib
	@if [ "$(shell uname)" = "Darwin" ]; then \
		sed -i '' 's|SF:.*/lib|SF:lib|' coverage/lcov.info; \
	else \
		sed -i 's|SF:.*/lib|SF:lib|' coverage/lcov.info; \
	fi
