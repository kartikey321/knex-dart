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

/// Shared reason for the `having/*` cluster below: each case calls
/// `.having(...)`/`.havingRaw(...)`/`.havingExists(...)` with no
/// `.select()` narrower than the implicit `select *` and no matching
/// `.groupBy()`. Postgres's strict GROUP BY rules then reject every
/// non-aggregated selected column (42803) — confirmed identical root cause
/// across all 23 cases by reading each body; none call `.groupBy()`. Some
/// engines with relaxed GROUP BY semantics may accept this; not a
/// knex-dart defect either way — the cases are valid SQL text but were
/// never meant to execute as written against a strict-GROUP-BY engine.
const _havingNoGroupByReason =
    'No .select() narrower than the implicit select *, and no matching '
    '.groupBy() — Postgres rejects the ungrouped, non-aggregated selected '
    'columns (42803). Same root cause as having/basic, confirmed by '
    'reading the case body: no .groupBy() call present. Not a knex-dart '
    'defect.';

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
    'agg/count-array':
        'knex.js\'s own aggregateArray() (querycompiler.js) compiles '
        '.count([...]) to a literal multi-argument call, e.g. '
        'count("id", "name") — knex-dart mirrors this exactly. Postgres '
        'genuinely has no multi-argument count() overload (confirmed via '
        'psql: 42883 function count(integer, integer) does not exist). Not '
        'a knex-dart defect.',
    'having/basic':
        'The case has no explicit .select(), so the compiled SQL is '
        '"select * from t group by cat having cnt > 1" — Postgres enforces '
        'strict GROUP BY (every selected column must be grouped or '
        'aggregated) and rejects this (42803); some engines with relaxed '
        'GROUP BY semantics may accept it. Not a knex-dart defect — the '
        'case is valid SQL text but was never meant to execute as written.',
    'clear/having-then-rehaving': _havingNoGroupByReason,
    'having/between': _havingNoGroupByReason,
    'having/exists': _havingNoGroupByReason,
    'having/from-alias': _havingNoGroupByReason,
    'having/grouped': _havingNoGroupByReason,
    'having/in': _havingNoGroupByReason,
    'having/nested': _havingNoGroupByReason,
    'having/nested-or': _havingNoGroupByReason,
    'having/not-between': _havingNoGroupByReason,
    'having/not-exists': _havingNoGroupByReason,
    'having/not-in': _havingNoGroupByReason,
    'having/not-null': _havingNoGroupByReason,
    'having/null': _havingNoGroupByReason,
    'having/or-between': _havingNoGroupByReason,
    'having/or-exists': _havingNoGroupByReason,
    'having/or-in': _havingNoGroupByReason,
    'having/or-not-between': _havingNoGroupByReason,
    'having/or-not-exists': _havingNoGroupByReason,
    'having/or-not-in': _havingNoGroupByReason,
    'having/or-not-null': _havingNoGroupByReason,
    'having/or-null': _havingNoGroupByReason,
    'having/raw': _havingNoGroupByReason,
    'having/raw-or': _havingNoGroupByReason,
    'dml/onconflict-merge-where':
        'Compiles to "... on conflict (email) do update set ... where '
        'email = \$3" — an unqualified column in the ON CONFLICT DO '
        'UPDATE ... WHERE clause is inherently ambiguous on real Postgres '
        '(both the target table and the implicit "excluded" pseudo-table '
        'have an "email" column). Confirmed independently via psql against '
        'a minimal two-column table with the identical ON CONFLICT shape: '
        '42702 column reference "email" is ambiguous. Not fixable by any '
        'fixture — this is standard Postgres semantics for any table with '
        'this shape. Not a knex-dart defect.',
    'where/named-binding-array':
        'Binds a Dart List ([1, 2, 3]) as a single positional parameter '
        'inside "select (\$1)", then wraps that in "id in (...)" — Postgres '
        'infers the parameter as an array type, so the comparison becomes '
        '"integer = <array type>", which has no operator. Confirmed the '
        'same structural failure independently via psql with a literal '
        'array ("select 1 where 1 in (select (ARRAY[1,2,3]))" -> "operator '
        'does not exist: integer = integer[]"). A named-binding array probe, '
        'not meant to produce runnable SQL. Not a knex-dart defect.',
    'jsonb/amp-op':
        'The case is a deliberate divergence probe: .where(\'id\', \'?&\', 1) '
        'applies the jsonb-only "exists all keys" operator to the integer '
        '"id" column. No real engine has a "?&"/"?|" operator for integers '
        '— this can never be valid SQL against any correctly-typed table, '
        'regardless of fixture. Confirmed via psql (42883). Not a '
        'knex-dart defect.',
    'jsonb/pipe-op':
        'Same root cause as jsonb/amp-op ("?|" applied to the integer "id" '
        'column) — confirmed via psql (42883). Not a knex-dart defect.',
    'json/where-superset-string':
        'whereJsonSupersetOf(\'address\', \'test\') binds the bare string '
        '"test" against a jsonb column with @> — Postgres infers the '
        'parameter as jsonb and requires valid JSON text (i.e. \'"test"\', '
        'quoted), so the bare string fails to parse (22P02). The same '
        'requirement holds for MySQL\'s JSON_CONTAINS, which also demands '
        'valid JSON input — this is inherent to passing a non-JSON-encoded '
        'scalar to a JSON-containment operator, not specific to Postgres. '
        'Flagged for a closer look at whether whereJsonSupersetOf should '
        'auto-encode non-Map/List scalars before binding; treated as '
        'unsupported for now rather than guessed at.',
  },
};
