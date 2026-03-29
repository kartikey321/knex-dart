#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}" || exit 1

ALL_DRIVERS=(postgres mysql sqlite duckdb mssql turso bigquery d1 snowflake)

if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
  COLORS="$(tput colors 2>/dev/null || echo 0)"
else
  COLORS=0
fi

if [[ "${COLORS}" -ge 8 ]]; then
  GREEN="$(tput setaf 2)"
  RED="$(tput setaf 1)"
  BOLD="$(tput bold)"
  RESET="$(tput sgr0)"
else
  GREEN=""
  RED=""
  BOLD=""
  RESET=""
fi

RESULT_DRIVERS=()
RESULT_STATUS=()
RESULT_DURATION=()
ANY_FAILURE=0
DOCKER_CHECKED=0

usage() {
  cat <<'USAGE'
Usage: ./tool/run_tests.sh [driver]

Drivers:
  postgres | mysql | sqlite | duckdb | mssql | turso | bigquery | d1 | snowflake

Aliases:
  http      Runs d1 + snowflake (mock-only)

No argument runs all drivers sequentially.
USAGE
}

is_server_backed() {
  case "$1" in
    postgres|mysql|mssql|turso|bigquery) return 0 ;;
    *) return 1 ;;
  esac
}

driver_dir() {
  case "$1" in
    postgres) echo "drivers/knex_dart_postgres" ;;
    mysql) echo "drivers/knex_dart_mysql" ;;
    sqlite) echo "drivers/knex_dart_sqlite" ;;
    duckdb) echo "drivers/knex_dart_duckdb" ;;
    mssql) echo "drivers/knex_dart_mssql" ;;
    turso) echo "drivers/knex_dart_turso" ;;
    bigquery) echo "drivers/knex_dart_bigquery" ;;
    d1) echo "drivers/knex_dart_d1" ;;
    snowflake) echo "drivers/knex_dart_snowflake" ;;
    *) return 1 ;;
  esac
}

ensure_docker() {
  if [[ "${DOCKER_CHECKED}" -eq 1 ]]; then
    return 0
  fi

  if ! command -v docker >/dev/null 2>&1; then
    echo "Docker CLI not found in PATH." >&2
    return 1
  fi

  if ! docker compose version >/dev/null 2>&1; then
    echo "Docker Compose plugin not available (expected: docker compose)." >&2
    return 1
  fi

  if ! docker info >/dev/null 2>&1; then
    echo "Docker daemon is not running. Start Docker and retry." >&2
    return 1
  fi

  DOCKER_CHECKED=1
  return 0
}

wait_for_container_healthy() {
  local container="$1"
  local timeout_seconds="${2:-120}"
  local started_at
  started_at="$(date +%s)"

  while true; do
    local status
    status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "${container}" 2>/dev/null || true)"

    if [[ "${status}" == "healthy" ]]; then
      return 0
    fi

    if [[ "${status}" == "unhealthy" || "${status}" == "dead" || "${status}" == "exited" ]]; then
      echo "Container ${container} became ${status}." >&2
      return 1
    fi

    local now
    now="$(date +%s)"
    if (( now - started_at >= timeout_seconds )); then
      echo "Timed out waiting for ${container} to become healthy." >&2
      return 1
    fi

    sleep 2
  done
}

wait_for_container_exit_success() {
  local container="$1"
  local timeout_seconds="${2:-120}"
  local started_at
  started_at="$(date +%s)"

  while true; do
    local state
    state="$(docker inspect --format '{{.State.Status}}' "${container}" 2>/dev/null || true)"

    if [[ "${state}" == "exited" ]]; then
      local exit_code
      exit_code="$(docker inspect --format '{{.State.ExitCode}}' "${container}" 2>/dev/null || echo 1)"
      if [[ "${exit_code}" == "0" ]]; then
        return 0
      fi
      echo "Container ${container} exited with code ${exit_code}." >&2
      return 1
    fi

    if [[ "${state}" == "dead" ]]; then
      echo "Container ${container} is dead." >&2
      return 1
    fi

    local now
    now="$(date +%s)"
    if (( now - started_at >= timeout_seconds )); then
      echo "Timed out waiting for ${container} to finish." >&2
      return 1
    fi

    sleep 2
  done
}

start_services_for_driver() {
  local driver="$1"

  case "${driver}" in
    postgres)
      docker compose up -d postgres >/dev/null || return 1
      wait_for_container_healthy "knex_dart_postgres" 120 || return 1
      ;;
    mysql)
      docker compose up -d mysql >/dev/null || return 1
      wait_for_container_healthy "knex_dart_mysql" 120 || return 1
      ;;
    mssql)
      docker compose up -d mssql mssql-init >/dev/null || return 1
      wait_for_container_healthy "knex_dart_mssql" 180 || return 1
      wait_for_container_exit_success "knex_dart_mssql_init" 180 || return 1
      ;;
    turso)
      docker compose up -d sqld >/dev/null || return 1
      wait_for_container_healthy "knex_dart_sqld" 120 || return 1
      ;;
    bigquery)
      docker compose up -d bigquery >/dev/null || return 1
      wait_for_container_healthy "knex_dart_bigquery" 120 || return 1
      ;;
    *)
      return 0
      ;;
  esac

  return 0
}

teardown_services_for_driver() {
  local driver="$1"

  case "${driver}" in
    postgres)
      docker compose stop postgres >/dev/null 2>&1 || true
      docker compose rm -f postgres >/dev/null 2>&1 || true
      ;;
    mysql)
      docker compose stop mysql >/dev/null 2>&1 || true
      docker compose rm -f mysql >/dev/null 2>&1 || true
      ;;
    mssql)
      docker compose stop mssql-init mssql >/dev/null 2>&1 || true
      docker compose rm -f mssql-init mssql >/dev/null 2>&1 || true
      ;;
    turso)
      docker compose stop sqld >/dev/null 2>&1 || true
      docker compose rm -f sqld >/dev/null 2>&1 || true
      ;;
    bigquery)
      docker compose stop bigquery >/dev/null 2>&1 || true
      docker compose rm -f bigquery >/dev/null 2>&1 || true
      ;;
  esac
}

run_driver_tests() {
  local driver="$1"
  local package_dir
  package_dir="$(driver_dir "${driver}")" || return 1

  case "${driver}" in
    postgres)
      (
        cd "${package_dir}" && \
          PG_HOST=localhost PG_PORT=5432 PG_DATABASE=knex_test PG_USER=knex PG_PASSWORD=knex \
          dart test --tags=postgres
      )
      ;;
    mysql)
      (
        cd "${package_dir}" && \
          MYSQL_HOST=localhost MYSQL_PORT=3306 MYSQL_DATABASE=knex_test MYSQL_USER=knex MYSQL_PASSWORD=knex \
          dart test --tags=mysql
      )
      ;;
    sqlite)
      (cd "${package_dir}" && dart test)
      ;;
    duckdb)
      (cd "${package_dir}" && dart test)
      ;;
    mssql)
      (
        cd "${package_dir}" && \
          if [[ "$(uname)" == "Darwin" ]]; then \
            if [[ -f "/opt/homebrew/lib/libsybdb.dylib" ]]; then \
              ln -sf "/opt/homebrew/lib/libsybdb.dylib" . ; \
              ln -sf "/opt/homebrew/lib/libct.dylib" . ; \
            elif [[ -f "/usr/local/lib/libsybdb.dylib" ]]; then \
              ln -sf "/usr/local/lib/libsybdb.dylib" . ; \
              ln -sf "/usr/local/lib/libct.dylib" . ; \
            fi ; \
          fi && \
          MSSQL_HOST=127.0.0.1 MSSQL_PORT=1433 MSSQL_DATABASE=knex_test MSSQL_USER=sa MSSQL_PASSWORD='Knex_Test1!' \
          dart test --tags=mssql
      )
      ;;
    turso)
      (
        cd "${package_dir}" && \
          dart test test/turso_test.dart && \
          TURSO_URL=http://localhost:8080 \
          dart test test/integration/turso_integration_test.dart --tags=turso
      )
      ;;
    bigquery)
      (
        cd "${package_dir}" && \
          dart test test/bigquery_test.dart && \
          BIGQUERY_EMULATOR_HOST=http://localhost:9050 BIGQUERY_PROJECT=knex-test BIGQUERY_DATASET=knex_dataset \
          dart test test/integration/bigquery_integration_test.dart --tags=bigquery
      )
      ;;
    d1)
      (cd "${package_dir}" && dart test)
      ;;
    snowflake)
      (cd "${package_dir}" && dart test)
      ;;
    *)
      return 1
      ;;
  esac
}

record_result() {
  RESULT_DRIVERS+=("$1")
  RESULT_STATUS+=("$2")
  RESULT_DURATION+=("$3")
}

run_one_driver() {
  local driver="$1"
  local started_at ended_at duration status
  started_at="$(date +%s)"

  echo
  echo "${BOLD}==> ${driver}${RESET}"

  local setup_ok=1

  if is_server_backed "${driver}"; then
    if ! ensure_docker; then
      setup_ok=0
    elif ! start_services_for_driver "${driver}"; then
      setup_ok=0
    fi
  fi

  if [[ "${setup_ok}" -eq 1 ]]; then
    if run_driver_tests "${driver}"; then
      status="PASS"
    else
      status="FAIL"
      ANY_FAILURE=1
    fi
  else
    status="FAIL"
    ANY_FAILURE=1
  fi

  if is_server_backed "${driver}"; then
    teardown_services_for_driver "${driver}"
  fi

  ended_at="$(date +%s)"
  duration="$((ended_at - started_at))s"
  record_result "${driver}" "${status}" "${duration}"
}

print_summary() {
  echo
  echo "${BOLD}Test Summary${RESET}"
  printf "%-12s | %-6s | %-8s\n" "driver" "status" "duration"
  printf "%-12s-+-%-6s-+-%-8s\n" "------------" "------" "--------"

  local i
  for ((i = 0; i < ${#RESULT_DRIVERS[@]}; i++)); do
    local status_text
    status_text="${RESULT_STATUS[$i]}"

    if [[ "${status_text}" == "PASS" ]]; then
      status_text="${GREEN}PASS${RESET}"
    else
      status_text="${RED}FAIL${RESET}"
    fi

    printf "%-12s | %-15b | %-8s\n" \
      "${RESULT_DRIVERS[$i]}" \
      "${status_text}" \
      "${RESULT_DURATION[$i]}"
  done
}

TARGET_DRIVERS=()

if [[ "$#" -gt 1 ]]; then
  usage
  exit 1
fi

if [[ "$#" -eq 1 ]]; then
  requested="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "${requested}" in
    postgres|mysql|sqlite|duckdb|mssql|turso|bigquery|d1|snowflake)
      TARGET_DRIVERS=("${requested}")
      ;;
    http)
      TARGET_DRIVERS=(d1 snowflake)
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown driver: ${1}" >&2
      usage
      exit 1
      ;;
  esac
else
  TARGET_DRIVERS=("${ALL_DRIVERS[@]}")
fi

for driver in "${TARGET_DRIVERS[@]}"; do
  run_one_driver "${driver}"
done

print_summary

if [[ "${ANY_FAILURE}" -eq 1 ]]; then
  exit 1
fi
