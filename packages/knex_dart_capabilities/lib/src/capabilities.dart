/// Canonical dialect keys used by capability checks.
enum KnexDialect { postgres, mysql, sqlite }

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
/// - `lateralJoin` on MySQL assumes MySQL 8+.
/// - `fullOuterJoin` is not natively supported by MySQL/SQLite.
/// - `json` support on MySQL is partial (no `@>` / `jsonb_*` operators).
/// - `intersectExcept` on MySQL requires 8.0.31+; omitted here as it is not
///   universally available in MySQL 8.
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
  KnexDialect.sqlite: {
    SqlCapability.onConflictMerge,
    SqlCapability.cte,
    SqlCapability.windowFunctions,
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
    default:
      return null;
  }
}
