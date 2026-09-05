/// Reviewed, versioned exceptions for [MechanicalStatus.unsupportedEngine].
///
/// An id belongs here only when a human has confirmed the case genuinely
/// cannot execute against the named dialect — never as a live adapter's own
/// guess at failure time (that would let real regressions launder
/// themselves through this label, exactly the false security this whole
/// framework exists to prevent). Every entry's [reason] must cite the
/// specific evidence used to confirm this (e.g. real knex.js source
/// consulted, a `psql`/native-client run against the actual engine) so a
/// future reviewer can re-verify rather than take it on faith.
///
/// This is a ratchet, not a one-time note: once the live-execution runner
/// exists, it must assert a listed id still reproduces a failure when run —
/// if it starts succeeding (e.g. a knex.js upstream fix changes the emitted
/// SQL), the test fails and demands the entry be removed, mirroring
/// `tool/parity/README.md`'s existing `parityAllowlist` ratchet.
library;

/// dialect -> case id -> reviewed reason it cannot run on this dialect.
const Map<String, Map<String, String>> unsupportedEngineAllowlist = {
  'postgres': {
    'join/left-outer-and-outer':
        'knex.js\'s own compiler (querycompiler.js: `join.joinType + \' join \'`) '
        'emits a bare "outer join" with no LEFT/RIGHT/FULL qualifier for '
        '.outerJoin() — knex-dart mirrors this exactly for SQL-text parity. '
        'Confirmed against real Postgres via psql: bare OUTER JOIN is '
        'rejected with 42601 syntax_error. Not a knex-dart defect.',
    'cte/nested':
        'knex.js\'s wrappingFormatter.outputQuery()/querybuilder.withWrapped() '
        'wrap an aliased CTE sub-value as "(select ...) as \\"alias\\"" and then '
        'wrap that again as \'"name" as ((select ...) as "alias")\' — '
        'knex-dart mirrors this exactly (see query_compiler.dart _with()). '
        'Confirmed invalid against real Postgres via psql (42601). Not a '
        'knex-dart defect.',
    'cte/recursive-nested-chained':
        'Same root cause as cte/nested (a nested aliased CTE sub-value), '
        'confirmed via the same knex.js source path and the same psql check.',
    'insert/raw-value':
        'The case\'s .raw() literal is "CURRENT TIMESTAMP" (missing the '
        'underscore Postgres requires) — a deliberately-arbitrary literal '
        'chosen to test that raw() passes text through verbatim for '
        'SQL-text parity, not meant to be valid runnable SQL. Confirmed via '
        'psql (42601 at the literal text itself).',
    'order/raw':
        'The case\'s orderByRaw() literal is "col NULLS LAST DESC" (wrong '
        'clause order — valid Postgres syntax is "col DESC NULLS LAST"), '
        'chosen for raw-passthrough text-parity, not meant to be valid '
        'runnable SQL. Confirmed via psql (42601).',
    'order/raw-with-binding':
        'Same malformed "NULLS LAST"/"DESC" ordering as order/raw, plus a '
        'bound value in a position no valid grammar accepts a parameter — '
        'raw-passthrough text-parity case, not meant to be valid runnable '
        'SQL. Confirmed via psql (42601).',
  },
};
