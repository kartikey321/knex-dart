/// Pre-defined SQL operator constants for use with `where()`, `having()`,
/// `onVal()`, and similar methods.
///
/// Using `Op` constants is optional — raw strings still work. `Op` provides
/// IDE auto-complete and makes query intent explicit.
///
/// ```dart
/// // These are equivalent:
/// db('users').where('age', Op.gt, 18);
/// db('users').where('age', '>', 18);
/// ```
///
/// Postgres-only operators (e.g. [Op.contains]) are documented with a note.
/// Using them against a MySQL/SQLite driver will produce invalid SQL.
abstract final class Op {
  // ── Comparison ────────────────────────────────────────────────────────────
  /// Equal to: `=`
  static const eq = '=';

  /// Not equal to: `<>` (standard SQL — prefer over `!=`)
  static const neq = '<>';

  /// Less than: `<`
  static const lt = '<';

  /// Greater than: `>`
  static const gt = '>';

  /// Less than or equal to: `<=`
  static const lte = '<=';

  /// Greater than or equal to: `>=`
  static const gte = '>=';

  // ── Pattern matching ──────────────────────────────────────────────────────
  /// Case-sensitive pattern match: `like`
  static const like = 'like';

  /// Negated case-sensitive pattern match: `not like`
  static const notLike = 'not like';

  /// Case-insensitive pattern match: `ilike` *(PostgreSQL only)*
  static const ilike = 'ilike';

  /// Negated case-insensitive pattern match: `not ilike` *(PostgreSQL only)*
  static const notIlike = 'not ilike';

  /// POSIX regular expression match: `similar to` *(PostgreSQL only)*
  static const similarTo = 'similar to';

  /// Negated POSIX regular expression match: `not similar to` *(PostgreSQL only)*
  static const notSimilarTo = 'not similar to';

  // ── JSON / array operators (PostgreSQL only) ──────────────────────────────
  /// Contains: `@>` — left value contains right *(PostgreSQL only)*
  static const contains = '@>';

  /// Contained by: `<@` — left value is contained by right *(PostgreSQL only)*
  static const containedBy = '<@';

  /// Any key exists: `?` *(PostgreSQL jsonb only)*
  static const anyKeyExists = '?';

  /// Any of the keys exist: `?|` *(PostgreSQL jsonb only)*
  static const anyKeysExist = '?|';

  /// All keys exist: `?&` *(PostgreSQL jsonb only)*
  static const allKeysExist = '?&';

  /// Overlap (have points in common): `&&` *(PostgreSQL array/range only)*
  static const overlap = '&&';
}
