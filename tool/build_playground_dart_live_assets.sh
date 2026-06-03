#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_CONFIG="${ROOT_DIR}/.dart_tool/package_config.json"
OUT_DIR="${ROOT_DIR}/playground/public/dart-live"
BUILD_ROOT="/tmp/knex_dart_playground_build"
CANONICAL_PACKAGE_CONFIG="${BUILD_ROOT}/package_config.json"
STUB="${BUILD_ROOT}/knex_stub.dart"

if [[ ! -f "$PACKAGE_CONFIG" ]]; then
  echo "Missing ${PACKAGE_CONFIG}. Run dart pub get from the repository root first." >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT"

node "${ROOT_DIR}/tool/write_playground_package_config.mjs" \
  "$PACKAGE_CONFIG" \
  "${BUILD_ROOT}/packages" \
  "$CANONICAL_PACKAGE_CONFIG"

cat > "$STUB" <<'DART'
import 'package:knex_dart/knex_dart.dart';

void main() {
  KnexQuery.forDialect(KnexDialect.postgres);
}
DART

dart compile kernel \
  --no-link-platform \
  --no-embed-sources \
  -p "$CANONICAL_PACKAGE_CONFIG" \
  -o "${OUT_DIR}/knex_dart.dill" \
  "$STUB"

node "${ROOT_DIR}/tool/pack_playground_dart_packages.mjs" \
  "$PACKAGE_CONFIG" \
  "${OUT_DIR}/knex_dart_packages.bin"
