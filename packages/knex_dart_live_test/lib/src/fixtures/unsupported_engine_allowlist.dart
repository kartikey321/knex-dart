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

/// Shared reason for the sqlite `having/*` cluster below: SQLite rejects a
/// HAVING clause on a query with no GROUP BY and no aggregate function in
/// the SELECT list at all ("HAVING clause on a non-aggregate query"). This
/// is a different specific rule from postgres's strict-GROUP-BY rejection
/// (42803, `_havingNoGroupByReason` above) — SQLite's own message and root
/// cause were independently confirmed via `sqlite3 :memory: "create table
/// t(a int); select a from t having a>1;"` -> "Error: in prepare, HAVING
/// clause on a non-aggregate query" — but the underlying case shape is
/// identical: none of these 22 cases call `.groupBy()`. `having/basic` and
/// `having/grouped` are NOT in this list — both call `.groupBy('cat')`, so
/// SQLite's rule is satisfied and they execute clean (linked in
/// `fixtureLinksByDialect`); postgres additionally rejects `having/basic`
/// under its own stricter rule (every selected column must be
/// grouped/aggregated), which SQLite's relaxed GROUP BY semantics do not
/// enforce — a genuine, reviewed cross-dialect divergence, not a triage
/// inconsistency.
const _sqliteHavingNonAggregateReason =
    'No .groupBy() call and no aggregate function in the SELECT list — '
    'SQLite rejects any HAVING clause on such a query outright. Confirmed '
    'via sqlite3 CLI: "create table t(a int); select a from t having '
    'a>1;" -> "HAVING clause on a non-aggregate query". Not a knex-dart '
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
        'quoted), so the bare string fails to parse (22P02). Verified this '
        'is not a knex-dart-specific gap: knex-dart\'s json_builder.dart:93 '
        '(`value is String ? value : jsonEncode(value)`) passes an '
        'already-String value through unencoded; real knex.js\'s equivalent '
        '(querycompiler.js\'s `_jsonWrapValue`) tries `JSON.parse(value)` '
        'and, on failure (as for the un-quoted word "test"), falls back to '
        'returning the original string unchanged too — the same outcome via '
        'a different path. tool/parity/run_js.mjs\'s own reference case '
        '(`json/where-superset-string`) passes the identical bare strings '
        '\'test\'/\'test2\', confirming this is a faithful mirror of the '
        'real knex.js test suite, not a Dart-side omission. Not a knex-dart '
        'defect for this input; knex-dart\'s simpler rule is not proven '
        'equivalent to knex.js\'s for every input shape, but that\'s a '
        'separate, lower-priority question from what this specific case '
        'tests.',
    'query/truncate':
        'Compiles to "truncate \\"users\\"" — canonical_seed_v2\'s own '
        '"orders" table has a foreign key referencing users(id), and plain '
        'TRUNCATE (no CASCADE) is rejected by Postgres for any table '
        'referenced by an FK. This is standard Postgres FK semantics, not '
        'an engine limitation nor a knex-dart defect — but it is specific '
        'to this fixture\'s schema shape (a users table with no incoming '
        'FK would let this succeed). Left here rather than deferredFixture '
        'because no fixture we\'d actually want (users linked from orders) '
        'could ever satisfy it without changing the relationship itself.',
    'on/in-raw':
        'Compiles to a syntactically valid "... in (select \$1 as '
        '\\"user_id\\")" with the parameter bound to an int — but Postgres\'s '
        'extended query protocol cannot infer the parameter\'s type from '
        'this isolated shape and defaults it to text, producing "operator '
        'does not exist: integer = text". Confirmed the underlying SQL '
        'shape is valid when the parameter type is explicit: "prepare '
        'p1(int) as select 1 where 5 in (select \$1 as user_id); execute '
        'p1(5);" succeeds via psql. A driver/protocol-level parameter-type-'
        'inference limitation for this exact construction, not fixable by '
        'any fixture. Not a knex-dart defect.',
    'ref/where-column':
        'Compiles a .where() comparing "sometable.column" against a raw '
        '"someothertable.someothercolumn" reference, but the query never '
        'joins or otherwise brings someothertable into scope — Postgres '
        'correctly rejects it ("missing FROM-clause entry"). Structurally '
        'invalid regardless of what tables exist; the case appears to '
        'demonstrate client.ref() compiling to a bare column reference, '
        'not to produce runnable standalone SQL. Not a knex-dart defect.',
    'subquery/from-aliased':
        'The outer query\'s FROM is a subquery aliased "bar" (from `.table('
        '\'foo\').select([\'*\']).as(\'bar\')`), so only "bar" is in scope '
        'in the outer query — but the join condition references "foo.id" '
        'from that same outer scope, where "foo" was never exposed. '
        'Structurally invalid regardless of fixture (confirmed via the '
        'runtime error: "missing FROM-clause entry for table \\"foo\\""). '
        'Not a knex-dart defect.',
    'subquery/from-basic-alias':
        'The derived table aliased "g" only projects a raw "? as f" '
        'expression, but the outer query\'s WHERE references "g.secret" — '
        'a column the derived table never exposes. Invalid in any SQL '
        'engine regardless of fixture (confirmed via the runtime error: '
        '"column g.secret does not exist"). Not a knex-dart defect.',
    'subquery/from-no-alias':
        'The subquery used as the outer FROM has no .table()/.from() call '
        'of its own — it selects a raw literal and the bare column "bar" '
        'with nothing to resolve "bar" against. Invalid in any SQL engine '
        'regardless of fixture (confirmed via the runtime error: "column '
        '\\"bar\\" does not exist"). Not a knex-dart defect.',
    'delete/join-multi':
        'Compiles the WHERE clause against the singular "user.email" while '
        'the query\'s actual tables are "users"/"photos"/"docs" (plural) — '
        '"user" is never in scope, so Postgres rejects it ("missing '
        'FROM-clause entry for table \\"user\\""). Verified this is not a '
        'Dart-porting mistake: tool/parity/run_js.mjs\'s reference case '
        '(`delete/join-multi`) has the identical `.where({ \'user.email\': '
        '... })` — this is a faithful, deliberate mirror of the real, '
        'hand-mined knex.js test suite (the file even notes it was mined '
        'specifically to regression-test a previously-fixed knex-dart bug '
        'where DELETE+JOIN silently dropped the join). Whether upstream '
        'knex.js\'s own decades-old test ever intended "user" or "users" is '
        'not this pass\'s call to make — text-only unit tests would never '
        'have caught this either way, which is exactly why this framework '
        'exists. Left in the shared corpus untouched. Not a knex-dart '
        'defect.',
    'delete/join-single':
        'Same singular/plural "user.email" shape as delete/join-multi, '
        'confirmed identical in tool/parity/run_js.mjs\'s reference case — '
        'same conclusion: a faithful mirror of the real knex.js test suite, '
        'not fixed here.',
    'subquery/select-first-as':
        'The outer .where(\'dept_no\', \'=\', \'e.dept_no\') binds the '
        'literal string "e.dept_no" as a VALUE (not a column reference — '
        'that would need .whereColumn() instead), so Postgres tries to '
        'compare the integer dept_no column against the literal text '
        '"e.dept_no" and fails to cast it (22P02). Verified this is not a '
        'Dart-porting mistake: tool/parity/run_js.mjs\'s reference case '
        '(`subquery/select-first-as`) has the identical '
        '`.where(\'dept_no\', \'=\', \'e.dept_no\')` — a faithful mirror of '
        'the real knex.js test suite\'s own case. Likely a latent bug in '
        'that upstream test (probably meant a column comparison), never '
        'caught because it only ever asserted on compiled SQL text. Left '
        'in the shared corpus untouched. Not a knex-dart defect.',
    'subquery/select-scalar':
        'Same outer where()-vs-whereColumn() shape as subquery/select-'
        'first-as (comparing dept_no against the literal string '
        '"e.dept_no"), plus an inner `.select([\'avg(salary)\'])` passing a '
        'plain string rather than a raw expression — both confirmed '
        'identical in tool/parity/run_js.mjs\'s reference case '
        '(`subquery/select-scalar`: `.select(\'avg(salary)\')` and '
        '`.where(\'dept_no\', \'=\', \'e.dept_no\')`). A faithful mirror of '
        'the real knex.js test suite, not fixed here.',
    'update/join-mysql-qualified-col':
        'knex.js\'s own postgres query compiler (pg-querycompiler.js) '
        'compiles update() via `this._updateFrom(this.single.updateFrom)` '
        '— a value only set by an explicit .updateFrom() call, never by '
        '.join(). For Postgres specifically, .join() on an update query is '
        'simply not translated into the query at all (MySQL is the only '
        'family where .update().join() produces a literal UPDATE...JOIN); '
        'knex-dart mirrors this. update/join-mysql (already linked) '
        'happens not to reference the joined table anywhere else, so '
        'dropping the join silently produces valid (if not fully '
        'representative) SQL; this case\'s WHERE clause references the '
        'dropped-join table\'s column directly, exposing it as "missing '
        'FROM-clause entry for table \\"tblPersonData\\"". Not a knex-dart '
        'defect — this shape needs .updateFrom() for Postgres, which the '
        'case does not use.',
  },

  'sqlite': {
    'clear/having-then-rehaving': _sqliteHavingNonAggregateReason,
    'having/between': _sqliteHavingNonAggregateReason,
    'having/exists': _sqliteHavingNonAggregateReason,
    'having/from-alias': _sqliteHavingNonAggregateReason,
    'having/in': _sqliteHavingNonAggregateReason,
    'having/nested': _sqliteHavingNonAggregateReason,
    'having/nested-or': _sqliteHavingNonAggregateReason,
    'having/not-between': _sqliteHavingNonAggregateReason,
    'having/not-exists': _sqliteHavingNonAggregateReason,
    'having/not-in': _sqliteHavingNonAggregateReason,
    'having/not-null': _sqliteHavingNonAggregateReason,
    'having/null': _sqliteHavingNonAggregateReason,
    'having/or-between': _sqliteHavingNonAggregateReason,
    'having/or-exists': _sqliteHavingNonAggregateReason,
    'having/or-in': _sqliteHavingNonAggregateReason,
    'having/or-not-between': _sqliteHavingNonAggregateReason,
    'having/or-not-exists': _sqliteHavingNonAggregateReason,
    'having/or-not-in': _sqliteHavingNonAggregateReason,
    'having/or-not-null': _sqliteHavingNonAggregateReason,
    'having/or-null': _sqliteHavingNonAggregateReason,
    'having/raw': _sqliteHavingNonAggregateReason,
    'having/raw-or': _sqliteHavingNonAggregateReason,
    'cte/nested':
        'Same root cause as postgres\'s cte/nested entry: knex.js\'s own '
        'wrappingFormatter.outputQuery()/querybuilder.withWrapped() wrap an '
        'aliased CTE sub-value as "(select ...) as \\"alias\\"" and then wrap '
        'that again as \'"name" as ((select ...) as "alias")\' — knex-dart '
        'mirrors this exactly (query_compiler.dart _with()). Confirmed '
        'invalid against real SQLite independently via the sqlite3 CLI '
        '(near "(": syntax error). Not a knex-dart defect.',
    'cte/recursive-nested-chained':
        'Same root cause as cte/nested (a nested aliased CTE sub-value), '
        'confirmed independently via the same sqlite3 CLI check.',
    'except/wrapped-array':
        'Compiles each branch of the set operation as a parenthesized '
        'SELECT — "(select ...) except (select ...) except (select ...)" — '
        'mirroring knex.js\'s own sqlite3-family compiler output. Confirmed '
        'via sqlite3 CLI that SQLite\'s parser rejects a parenthesized '
        'SELECT anywhere in a compound-select statement: "create table a(x '
        'int); (select x from a) union (select x from a);" -> "near \\"(\\": '
        'syntax error" (same parser rule applies to UNION/UNION ALL/'
        'INTERSECT/EXCEPT alike). Not a knex-dart defect.',
    'intersect/wrapped-array':
        'Same root cause as except/wrapped-array (parenthesized compound-'
        'select branches) — confirmed via the same sqlite3 CLI check.',
    'union/wrapped-array':
        'Same root cause as except/wrapped-array (parenthesized compound-'
        'select branches) — confirmed via the same sqlite3 CLI check.',
    'unionAll/wrapped-array':
        'Same root cause as except/wrapped-array (parenthesized compound-'
        'select branches) — confirmed via the same sqlite3 CLI check.',
    'cte/delete-source':
        'Compiles to a data-modifying CTE — "with \\"delete1\\" as (delete '
        'from \\"accounts\\" where \\"id\\" = ?) select * from \\"accounts\\"" '
        '— mirroring knex.js\'s own compiler output faithfully (Postgres '
        'supports writable CTEs and accepts this shape; SQLite does not '
        'support DML — INSERT/UPDATE/DELETE — inside a CTE body at all). '
        'Confirmed via sqlite3 CLI: "with \\"delete1\\" as (delete from '
        '\\"accounts\\" where \\"id\\" = 1) select * from \\"accounts\\";" -> '
        '"near \\"delete\\": syntax error". A genuine SQLite engine '
        'limitation, not fixable by any fixture, not a knex-dart defect.',
    'cte/update-source':
        'Same root cause as cte/delete-source (a data-modifying CTE body — '
        'here an UPDATE ... RETURNING) — confirmed independently via '
        'sqlite3 CLI ("near \\"update\\": syntax error"). Not a knex-dart '
        'defect.',
    'insert/raw-value':
        'Same malformed-literal probe as postgres\'s insert/raw-value entry '
        '— the case\'s .raw() literal is "CURRENT TIMESTAMP" (missing the '
        'underscore both Postgres and SQLite require), a deliberately-'
        'arbitrary literal chosen to test that raw() passes text through '
        'verbatim for SQL-text parity, not meant to be valid runnable SQL. '
        'Confirmed via sqlite3 CLI (near "TIMESTAMP": syntax error).',
    'order/raw':
        'Same malformed-literal probe as postgres\'s order/raw entry — the '
        'case\'s orderByRaw() literal is "col NULLS LAST DESC" (wrong clause '
        'order), chosen for raw-passthrough text-parity, not meant to be '
        'valid runnable SQL. Confirmed via sqlite3 CLI (near "DESC": syntax '
        'error).',
    'order/raw-with-binding':
        'Same malformed "NULLS LAST"/"DESC" ordering as order/raw, plus a '
        'bound value in a position no valid grammar accepts a parameter — '
        'raw-passthrough text-parity case, not meant to be valid runnable '
        'SQL. Confirmed via sqlite3 CLI (near "?": syntax error).',
    'delete/join-multi':
        'Compiles to "delete \\"users\\" from \\"users\\" inner join ... '
        'where ..." — SQLite has no DELETE ... FROM ... JOIN syntax at all '
        '(unlike Postgres\'s USING or MySQL\'s multi-table DELETE), so the '
        'whole statement is structurally invalid regardless of the WHERE '
        'clause or fixture shape. Confirmed via sqlite3 CLI with a minimal '
        'two-table repro ("delete a from a join b on a.x=b.x;" -> "near '
        '\\"a\\": syntax error"). Not a knex-dart defect — this is a genuine '
        'SQLite engine limitation.',
    'delete/join-no-where':
        'Same root cause as delete/join-multi (DELETE ... FROM ... JOIN is '
        'not valid SQLite syntax under any circumstance) — confirmed via '
        'the same sqlite3 CLI check.',
    'delete/join-oncallback-where':
        'Same root cause as delete/join-multi (DELETE ... FROM ... JOIN is '
        'not valid SQLite syntax under any circumstance) — confirmed via '
        'the same sqlite3 CLI check.',
    'delete/join-single':
        'Same root cause as delete/join-multi (DELETE ... FROM ... JOIN is '
        'not valid SQLite syntax under any circumstance) — confirmed via '
        'the same sqlite3 CLI check.',
    'jsonb/amp-op':
        'The case is a deliberate divergence probe applying the postgres-'
        'jsonb-only "?&" ("exists all keys") operator to an integer column. '
        'SQLite has no jsonb type or "?&"/"?|"/"?" operators at all, and '
        'the literal "?" additionally collides with SQLite\'s own bind-'
        'parameter placeholder syntax — confirmed via sqlite3 CLI '
        '(unrecognized token: "\\", from the escaped "\\?&" knex-dart emits '
        'to keep the literal "?" from being parsed as a placeholder). Not '
        'fixable by any fixture, not a knex-dart defect.',
    'jsonb/pipe-op':
        'Same root cause as jsonb/amp-op ("?|" has no SQLite equivalent and '
        'collides with bind-parameter syntax) — confirmed via the same '
        'sqlite3 CLI check.',
    'jsonb/qmark-op':
        'Same root cause as jsonb/amp-op (the jsonb "?" key-exists operator '
        'has no SQLite equivalent and collides with bind-parameter syntax) '
        '— confirmed via the same sqlite3 CLI check.',
    'agg/count-array':
        'knex.js\'s own aggregateArray() compiles .count([...]) to a '
        'literal multi-argument call, e.g. count("id", "name") — knex-dart '
        'mirrors this exactly. SQLite genuinely has no multi-argument '
        'count() overload either (confirmed via sqlite3 CLI: "select '
        'count(1,2);" -> "wrong number of arguments to function count()"). '
        'Not a knex-dart defect.',
    'agg/count-distinct-multi-col':
        'Same root cause as agg/count-array (a literal multi-argument '
        'count() call) — confirmed via the same sqlite3 CLI check.',
    'insert/empty-array-noop':
        'knex-dart compiles .insert([]) to an empty SQL string (a '
        'deliberate no-op mirroring knex.js — see query_compiler.dart\'s '
        '`if (sql.isEmpty) ...` handling). Postgres\'s underlying client '
        'tolerates executing an empty statement; package:sqlite3\'s own '
        'Database.prepare() explicitly refuses one — confirmed at '
        'implementation/database.dart:460: `throw ArgumentError.value(sql, '
        '\'sql\', \'Must contain an SQL statement.\')` — so there is no way '
        'to "execute" this no-op through the sqlite3 Dart binding at all, '
        'regardless of fixture. Not a knex-dart defect.',
    'join/full-outer':
        'knex-dart\'s own compiler explicitly guards this: '
        '`if (joinType == \'full outer\' && '
        '!_supports(SqlCapability.fullOuterJoin)) throw StateError('
        '\'FULL OUTER JOIN is not supported by \${client.driverName}\')` '
        '(query_compiler.dart, near the join-compilation loop) — a '
        'deliberate knex-dart capability policy for the sqlite family '
        '(distinct from whether the underlying engine build happens to '
        'support it), so no fixture can make this succeed. Not a fixture '
        'gap.',
    'join/left-outer-and-outer':
        'knex.js\'s own compiler emits a bare "outer join" with no LEFT/'
        'RIGHT/FULL qualifier for .outerJoin() — knex-dart mirrors this '
        'exactly for SQL-text parity, same as postgres\'s identically-named '
        'allowlist entry. Confirmed against real SQLite via the sqlite3 '
        'CLI: bare "outer join" is rejected ("unknown join type: outer"). '
        'Not a knex-dart defect.',
    'update/join-mysql-qualified-col':
        'Compiles to \'update "tblPerson" set "tblPerson"."City" = ? '
        'where ...\' — a dotted (table-qualified) column reference in an '
        'UPDATE ... SET clause is not valid syntax for SQLite (nor '
        'standard SQL generally; only MySQL\'s dialect allows it). '
        'Confirmed via sqlite3 CLI with a minimal repro ("update t set '
        't.x = 1;" -> "near \\".\\": syntax error"). A different specific '
        'mechanism than postgres\'s identically-named entry (which drops '
        'the join and then hits a missing-FROM-clause error instead), but '
        'the same verdict: not fixable by any fixture, not a knex-dart '
        'defect.',
    'table/dotted-schema':
        'Compiles to \'select * from "public"."users"\'. Unlike postgres '
        '(where an unqualified schema search path made this silently read '
        'the real integration suite\'s public.users table — see the '
        'fixture-link-table docstring), SQLite resolves a dotted table '
        'reference as "<attached-database-name>.<table>"; since this '
        'framework never ATTACHes a database named "public", the case '
        'fails cleanly and cannot leak into real data. Confirmed via '
        'sqlite3 CLI ("no such table: public.users"). No fixture profile '
        'in this framework attaches a second database, so this cannot be '
        'linked; not a knex-dart defect.',
    'ref/where-column':
        'Same structural defect as postgres\'s identically-named allowlist '
        'entry: compiles a .where() comparing "sometable.column" against a '
        'raw "someothertable.someothercolumn" reference, but the query '
        'never joins or otherwise brings someothertable into scope. '
        'Confirmed independently on SQLite (no such column: '
        'someothertable.someothercolumn) — structurally invalid regardless '
        'of what tables exist. Not a knex-dart defect.',
    'subquery/from-aliased':
        'Same structural defect as postgres\'s identically-named allowlist '
        'entry: the outer query\'s FROM is a subquery aliased "bar", but '
        'the join condition references "foo.id" from that same outer '
        'scope, where "foo" was never exposed. Confirmed independently on '
        'SQLite (no such column: foo.id) — invalid regardless of fixture. '
        'Not a knex-dart defect.',
    'subquery/from-basic-alias':
        'Same structural defect as postgres\'s identically-named allowlist '
        'entry: the derived table aliased "g" only projects a raw "? as f" '
        'expression, but the outer WHERE references "g.secret", a column '
        'the derived table never exposes. Confirmed independently on '
        'SQLite (no such column: g.secret). Not a knex-dart defect.',
    'subquery/from-no-alias':
        'Same structural defect as postgres\'s identically-named allowlist '
        'entry: the subquery used as the outer FROM has no .table()/'
        '.from() call of its own and selects a bare column "bar" with '
        'nothing to resolve it against. Confirmed independently on SQLite '
        '(no such column "bar" — should this be a string literal in '
        'single-quotes?). Not a knex-dart defect.',
    'subquery/select-scalar':
        'Same authoring issue as postgres\'s identically-named allowlist '
        'entry\'s second half: the inner `.select([\'avg(salary)\'])` passes '
        'a plain string where an aggregate expression was intended, so '
        'knex-dart (matching knex.js) compiles it as a quoted identifier '
        'rather than a function call. Confirmed independently on SQLite '
        '(no such column "avg(salary)" — should this be a string literal '
        'in single-quotes?) — this fails before SQLite even reaches '
        'postgres\'s separate where()-vs-whereColumn() issue on dept_no, '
        'since SQLite\'s dynamic typing would not have rejected that part '
        'the way postgres does (see subquery/select-first-as, which is '
        'linked here for exactly that reason). Not a knex-dart defect, not '
        'fixed here per the same policy as postgres\'s entry.',
  },
};
