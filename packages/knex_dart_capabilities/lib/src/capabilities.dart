/// Canonical dialect keys used by capability checks.
enum KnexDialect { postgres, mysql, sqlite, mariadb,
                  redshift, turso, d1, duckdb, snowflake,
                  bigquery, mssql }

/// SQL features whose support varies by dialect in knex_dart.
enum SqlCapability {
  // ── Already supported ────────────────────────────────────────────────────
  /// `RETURNING` clause — PostgreSQL only.
  returning,

  /// `FULL OUTER JOIN` — PostgreSQL only (MySQL/SQLite don't support it).
  fullOuterJoin,

  /// `LATERAL JOIN` — PostgreSQL + MySQL 8+.
  lateralJoin,

  /// `ON CONFLICT ... DO UPDATE SET` / `ON DUPLICATE KEY UPDATE` — all except
  /// older SQLite (supported since SQLite 3.24).
  onConflictMerge,

  // ── Newly added ───────────────────────────────────────────────────────────
  /// `WITH` / `WITH RECURSIVE` CTEs — PostgreSQL, MySQL 8+, SQLite 3.35+.
  cte,

  /// Window functions: `OVER (PARTITION BY … ORDER BY …)` —
  /// PostgreSQL, MySQL 8+, SQLite 3.25+.
  windowFunctions,

  /// JSON operators and path functions: `->`, `->>`, `@>`, `jsonb_*`, etc.
  /// Full support: PostgreSQL.
  /// Partial support (JSON functions only): MySQL 5.7+.
  /// Not supported: SQLite (no native JSON type).
  json,

  /// `INTERSECT` / `EXCEPT` set operations —
  /// PostgreSQL, SQLite. Not supported in MySQL prior to 8.0.31.
  intersectExcept,
}

/// Canonical capability matrix.
///
/// Notes:
/// - `lateralJoin` on MySQL/MariaDB assumes MySQL 8+ / MariaDB 10.0+.
/// - `fullOuterJoin` is not natively supported by MySQL/SQLite.
/// - `json` support on MySQL/MariaDB is partial (no `@>` / `jsonb_*` operators).
/// - `intersectExcept` on MySQL requires 8.0.31+; omitted here.
/// - `returning` on MariaDB requires 10.5+.
/// - `fullOuterJoin` on CockroachDB requires v23.1+.
/// - Redshift: no RETURNING, no LATERAL, no JSON operators; FULL OUTER JOIN supported.
const Map<KnexDialect, Set<SqlCapability>> dialectCapabilities = {
  KnexDialect.postgres: {
    SqlCapability.returning,
    SqlCapability.fullOuterJoin,
    SqlCapability.lateralJoin,
    SqlCapability.onConflictMerge,
    SqlCapability.cte,
    SqlCapability.windowFunctions,
    SqlCapability.json,
    SqlCapability.intersectExcept,
  },
  KnexDialect.mysql: {
    SqlCapability.lateralJoin,
    SqlCapability.onConflictMerge,
    SqlCapability.cte,
    SqlCapability.windowFunctions,
    SqlCapability.json, // partial — no @> or jsonb operators
  },
  // SQLite >=3.35 supports RETURNING, but only on INSERT/UPDATE — never on
  // DELETE (knex.js's own sqlite3 dialect never emits it there either).
  // That asymmetry isn't expressible as a single per-dialect capability
  // flag; the DELETE-specific carve-out lives in QueryCompiler._deleteQuery.
  KnexDialect.sqlite: {
    SqlCapability.returning,
    SqlCapability.onConflictMerge,
    SqlCapability.cte,
    SqlCapability.windowFunctions,
    SqlCapability.intersectExcept,
  },
  // MariaDB: superset of MySQL — adds RETURNING (10.5+), FULL OUTER JOIN,
  // INTERSECT/EXCEPT (10.3+). Uses ON DUPLICATE KEY UPDATE for upserts.
  KnexDialect.mariadb: {
    SqlCapability.returning,
    SqlCapability.fullOuterJoin,
    SqlCapability.lateralJoin,
    SqlCapability.onConflictMerge,
    SqlCapability.cte,
    SqlCapability.windowFunctions,
    SqlCapability.json, // partial — JSON functions, no @> operators
    SqlCapability.intersectExcept,
  },
  // Redshift: PostgreSQL wire protocol, but PostgreSQL 8.0-era dialect.
  // No RETURNING, no LATERAL, no JSONB. FULL OUTER JOIN and window functions
  // are fully supported. CTEs and INTERSECT/EXCEPT are supported.
  KnexDialect.redshift: {
    SqlCapability.fullOuterJoin,
    SqlCapability.cte,
    SqlCapability.windowFunctions,
    SqlCapability.intersectExcept,
  },
  // Turso (libSQL): SQLite-compatible dialect over HTTP.
  // Same capabilities as SQLite (libSQL is built on SQLite 3.45+), including
  // the RETURNING-except-on-DELETE asymmetry noted above. No LATERAL, no
  // FULL OUTER JOIN.
  KnexDialect.turso: {
    SqlCapability.returning,
    SqlCapability.onConflictMerge,
    SqlCapability.cte,
    SqlCapability.windowFunctions,
    SqlCapability.intersectExcept,
  },
  // Cloudflare D1: SQLite dialect via Cloudflare REST API.
  // Same SQLite capability set, including the RETURNING-except-on-DELETE
  // asymmetry noted above. No LATERAL, no FULL OUTER JOIN.
  KnexDialect.d1: {
    SqlCapability.returning,
    SqlCapability.onConflictMerge,
    SqlCapability.cte,
    SqlCapability.windowFunctions,
    SqlCapability.intersectExcept,
  },
  // DuckDB: analytical SQL engine with PostgreSQL-compatible syntax.
  // Full capability set: window functions, CTEs, LATERAL, FULL OUTER JOIN,
  // INTERSECT/EXCEPT, JSON. Also supports RETURNING.
  KnexDialect.duckdb: {
    SqlCapability.returning,
    SqlCapability.fullOuterJoin,
    SqlCapability.lateralJoin,
    SqlCapability.onConflictMerge,
    SqlCapability.cte,
    SqlCapability.windowFunctions,
    SqlCapability.json,
    SqlCapability.intersectExcept,
  },
  // Snowflake: cloud data warehouse. Supports window functions, CTEs,
  // FULL OUTER JOIN, LATERAL, INTERSECT/EXCEPT. No `ON CONFLICT` — uses MERGE.
  // RETURNING not supported natively. JSON semi-structured types via VARIANT.
  KnexDialect.snowflake: {
    SqlCapability.fullOuterJoin,
    SqlCapability.lateralJoin,
    SqlCapability.cte,
    SqlCapability.windowFunctions,
    SqlCapability.json, // VARIANT type + JSON functions
    SqlCapability.intersectExcept,
  },
  // BigQuery: Google's serverless data warehouse. Full analytical SQL support.
  // No RETURNING, no ON CONFLICT (uses MERGE for upserts). DML in implicit
  // transactions; interactive transactions require multi-statement API.
  KnexDialect.bigquery: {
    SqlCapability.fullOuterJoin,
    SqlCapability.lateralJoin,
    SqlCapability.cte,
    SqlCapability.windowFunctions,
    SqlCapability.json,
    SqlCapability.intersectExcept,
  },
  // MSSQL (SQL Server): No RETURNING (uses OUTPUT instead), supports CTEs,
  // window functions, FULL OUTER JOIN, INTERSECT/EXCEPT, JSON functions.
  KnexDialect.mssql: {
    SqlCapability.fullOuterJoin,
    SqlCapability.cte,
    SqlCapability.windowFunctions,
    SqlCapability.json,
    SqlCapability.intersectExcept,
  },
};

/// Returns true when [dialect] supports [capability].
bool supportsCapability(KnexDialect dialect, SqlCapability capability) {
  final set = dialectCapabilities[dialect];
  return set != null && set.contains(capability);
}

/// Best-effort conversion from knex/client driver strings to [KnexDialect].
///
/// Returns `null` when the value cannot be mapped.
KnexDialect? dialectFromDriverName(String? driverName) {
  if (driverName == null) return null;
  switch (driverName.toLowerCase()) {
    case 'pg':
    case 'postgres':
    case 'postgresql':
      return KnexDialect.postgres;
    case 'mysql':
    case 'mysql2':
      return KnexDialect.mysql;
    case 'sqlite':
    case 'sqlite3':
      return KnexDialect.sqlite;
    case 'mariadb':
      return KnexDialect.mariadb;
    case 'cockroachdb':
    case 'crdb':
      return KnexDialect.postgres; // wire-identical to postgres
    case 'redshift':
      return KnexDialect.redshift;
    case 'turso':
    case 'libsql':
      return KnexDialect.turso;
    case 'd1':
    case 'cloudflare-d1':
      return KnexDialect.d1;
    case 'duckdb':
      return KnexDialect.duckdb;
    case 'snowflake':
      return KnexDialect.snowflake;
    case 'bigquery':
    case 'big_query':
      return KnexDialect.bigquery;
    case 'mssql':
      return KnexDialect.mssql;
    default:
      return null;
  }
}
