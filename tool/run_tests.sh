#!/bin/bash

# Ensure we are in the project root directory
cd "$(dirname "$0")/.." || exit 1

echo "Running Unit & Query Parity Tests..."
dart test test/query test/schema test/raw_test.dart

echo "Running SQLite Integration Tests..."
dart test test/integration/sqlite_test.dart

# Optional: Run Postgres and MySQL tests if docker containers are up locally
# dart test test/integration/postgres_test.dart
# dart test test/integration/mysql_test.dart
# dart test test/integration/schema_integration_test.dart

echo "Generating Coverage Report..."
dart test --coverage=coverage

echo "Formatting Coverage to lcov.info..."
dart run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --packages=.dart_tool/package_config.json --report-on=lib

echo "Sanitizing paths to relative structure for reports..."
# Detect OS for correct sed syntax
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS requires an empty string argument for in-place edit
  sed -i '' 's|SF:.*/lib|SF:lib|' coverage/lcov.info
else
  # Linux and others
  sed -i 's|SF:.*/lib|SF:lib|' coverage/lcov.info
fi

echo "Done! Coverage report generated at coverage/lcov.info"
