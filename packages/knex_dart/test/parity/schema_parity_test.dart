/// Differential parity harness: knex-dart vs knex.js — SCHEMA DDL.
///
/// Sibling to parity_test.dart (query builder). Split out because a schema
/// `.toSQL()` call returns a LIST of statements on both sides (e.g.
/// `createTable` may emit a CREATE TABLE plus separate ALTER TABLE
/// statements for deferred constraints), so the comparison is list-of-SQL
/// vs list-of-SQL rather than one SqlString each.
///
/// See parity_test.dart's doc comment for the ratchet/allowlist mechanics —
/// identical design, just a different fixture and comparator shape.
///
/// Regenerate fixtures: node tool/parity/run_js_schema.mjs
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'schema_parity_cases.dart';

/// Triage ledger of known divergences, keyed `id::dialect`. Every entry MUST
/// carry a reason. See parity_test.dart for the [ACCEPTED]/[OPEN BUG] legend.
const Map<String, String> schemaParityAllowlist = {
  // ── ACCEPTED: SQLite cannot ALTER TABLE ADD CONSTRAINT for primary key,
  // foreign key, or column type/nullability changes. knex.js reroutes these
  // through a PRAGMA-table_info-based table-rebuild compat path (a dynamic,
  // multi-step runtime operation, not a fixed SQL string); knex-dart instead
  // refuses outright with UnsupportedError, matching the primary()-on-SQLite
  // fix already applied elsewhere in this compiler. Both are defensible;
  // knex-dart chooses "fail loudly" over "silently do something complex" —
  // the PRAGMA statement itself isn't even the real operation, just the
  // first probe of a multi-query rebuild knex.js performs internally.
  'schema/alter-table-primary::sqlite':
      '[ACCEPTED] SQLite: knex.js reroutes through a PRAGMA-based table '
          'rebuild; knex-dart refuses. See schema_compiler.dart primary() guard.',
  'schema/alter-table-primary::turso':
      '[ACCEPTED] see schema/alter-table-primary::sqlite (turso is sqlite-family).',
  'schema/alter-table-primary::d1':
      '[ACCEPTED] see schema/alter-table-primary::sqlite (d1 is sqlite-family).',
  'schema/alter-table-foreign::sqlite':
      '[ACCEPTED] SQLite: knex.js reroutes through a PRAGMA-based table '
          'rebuild for ALTER TABLE ADD CONSTRAINT FOREIGN KEY; knex-dart refuses.',
  'schema/alter-table-foreign::turso':
      '[ACCEPTED] see schema/alter-table-foreign::sqlite (turso is sqlite-family).',
  'schema/alter-table-foreign::d1':
      '[ACCEPTED] see schema/alter-table-foreign::sqlite (d1 is sqlite-family).',
  'schema/alter-table-set-nullable::sqlite':
      '[ACCEPTED] SQLite: knex.js reroutes through a PRAGMA-based table rebuild.',
  'schema/alter-table-set-nullable::turso':
      '[ACCEPTED] see schema/alter-table-set-nullable::sqlite (sqlite-family).',
  'schema/alter-table-set-nullable::d1':
      '[ACCEPTED] see schema/alter-table-set-nullable::sqlite (sqlite-family).',
  'schema/alter-table-drop-nullable::sqlite':
      '[ACCEPTED] SQLite: knex.js reroutes through a PRAGMA-based table rebuild.',
  'schema/alter-table-drop-nullable::turso':
      '[ACCEPTED] see schema/alter-table-drop-nullable::sqlite (sqlite-family).',
  'schema/alter-table-drop-nullable::d1':
      '[ACCEPTED] see schema/alter-table-drop-nullable::sqlite (sqlite-family).',
  'schema/alter-table-drop-primary::sqlite':
      '[ACCEPTED] see schema/alter-table-primary::sqlite — dropPrimary mirrors it.',
  'schema/alter-table-drop-primary::turso':
      '[ACCEPTED] see schema/alter-table-primary::sqlite (turso is sqlite-family).',
  'schema/alter-table-drop-primary::d1':
      '[ACCEPTED] see schema/alter-table-primary::sqlite (d1 is sqlite-family).',
  'schema/alter-table-drop-foreign::sqlite':
      '[ACCEPTED] see schema/alter-table-foreign::sqlite — dropForeign mirrors it.',
  'schema/alter-table-drop-foreign::turso':
      '[ACCEPTED] see schema/alter-table-foreign::sqlite (turso is sqlite-family).',
  'schema/alter-table-drop-foreign::d1':
      '[ACCEPTED] see schema/alter-table-foreign::sqlite (d1 is sqlite-family).',

  // ── ACCEPTED: SQLite's DROP COLUMN has been natively supported since
  // 3.35.0 (2021). knex.js still defensively routes it through the
  // PRAGMA-based rebuild for compatibility with pre-3.35 SQLite; knex-dart
  // targets current SQLite and emits the direct, modern statement, which is
  // valid SQL. Same "modern vs legacy-compat" choice as MySQL rename-column
  // below — not a capability gap.
  'schema/alter-table-drop-column::sqlite':
      '[ACCEPTED] knex.js routes through a PRAGMA-based rebuild for pre-3.35 '
          'SQLite compat; knex-dart emits the native DROP COLUMN directly '
          '(valid since SQLite 3.35, 2021).',
  'schema/alter-table-drop-column::turso':
      '[ACCEPTED] see schema/alter-table-drop-column::sqlite (turso is sqlite-family).',
  'schema/alter-table-drop-column::d1':
      '[ACCEPTED] see schema/alter-table-drop-column::sqlite (d1 is sqlite-family).',

  // ── ACCEPTED: knex-dart's setNullable/dropNullable are narrow, single-
  // purpose "toggle nullability only" operations (a single ALTER COLUMN ...
  // DROP/SET NOT NULL). knex.js's `.nullable().alter()` is a generic
  // "redefine this column" operation that always re-specifies type and
  // default too (3 statements on Postgres: drop default, drop/set not
  // null, re-assert type via USING). Different API shape, not a bug —
  // knex-dart's single statement is valid, minimal, and does what its
  // name says.
  'schema/alter-table-set-nullable::postgres':
      '[ACCEPTED] knex.js .alter() rewrites default+type+nullable (3 '
          'statements); knex-dart setNullable() only toggles NOT NULL (1 '
          'statement, still correct SQL for that narrower purpose).',
  'schema/alter-table-set-nullable::cockroachdb':
      '[ACCEPTED] see schema/alter-table-set-nullable::postgres.',
  'schema/alter-table-set-nullable::redshift':
      '[ACCEPTED] see schema/alter-table-set-nullable::postgres.',
  'schema/alter-table-set-nullable::mysql':
      '[ACCEPTED] knex.js .alter() on MySQL re-emits the full column '
          'definition (MODIFY requires it); knex-dart setNullable() is a '
          'narrower, single-purpose operation. See postgres entry above.',
  'schema/alter-table-drop-nullable::postgres':
      '[ACCEPTED] see schema/alter-table-set-nullable::postgres (dropNullable mirrors it).',
  'schema/alter-table-drop-nullable::cockroachdb':
      '[ACCEPTED] see schema/alter-table-set-nullable::postgres.',
  'schema/alter-table-drop-nullable::redshift':
      '[ACCEPTED] see schema/alter-table-set-nullable::postgres.',
  'schema/alter-table-drop-nullable::mysql':
      '[ACCEPTED] see schema/alter-table-set-nullable::mysql.',

  // ── ACCEPTED: Redshift genuinely does not support CREATE INDEX / DROP
  // INDEX (confirmed against AWS Redshift docs and knex.js's own Redshift
  // compiler, which prints this exact warning and emits NO SQL rather than
  // refusing outright). knex-dart throws UnsupportedError, refusing loudly
  // instead of silently producing nothing. Verified: a Codex adversarial
  // review of this file caught that a *prior* version of this entry claimed
  // knex-dart "emits standard SQL, which Redshift can be configured to
  // accept" — that was wrong; knex-dart used to emit `create index`/`drop
  // index` SQL here, which Redshift genuinely rejects at execution time.
  // Fixed in schema_compiler.dart (both `index`/`dropIndex` cases in
  // _alterTable, and the `index` case in _pushDeferredConstraintsForTable
  // for index() called inside createTable) rather than left as a divergence.
  'schema/alter-table-add-index::redshift':
      '[ACCEPTED] Redshift has no CREATE INDEX; knex.js silently emits no '
          'SQL (console warning only), knex-dart throws UnsupportedError. '
          'Both refuse the operation — different failure mode, not a bug.',
  'schema/alter-table-add-index-named::redshift':
      '[ACCEPTED] see schema/alter-table-add-index::redshift.',
  'schema/alter-table-drop-index::redshift':
      '[ACCEPTED] Redshift has no DROP INDEX; knex.js silently emits no SQL '
          '(console warning only), knex-dart throws UnsupportedError.',
  'schema/alter-table-drop-index-named::redshift':
      '[ACCEPTED] see schema/alter-table-drop-index::redshift.',

  // ── ACCEPTED: MySQL accepts multiple equivalent forms for these DDL
  // clauses; knex.js and knex-dart each independently picked a valid one.
  // Verified against MySQL's documented ALTER TABLE grammar — both sides
  // compile and execute identically, this is spelling, not semantics.
  //   ADD [COLUMN] col_def         — COLUMN keyword optional
  //   DROP [COLUMN] col_name       — COLUMN keyword optional
  //   ADD [CONSTRAINT [symbol]] UNIQUE [INDEX|KEY] [name] (cols)
  //                                 — knex.js: UNIQUE name (cols); knex-dart: CONSTRAINT name UNIQUE (cols)
  //   ADD INDEX name (cols)  ==  CREATE INDEX name ON table (cols)
  //   DROP INDEX name ON table  ==  ALTER TABLE table DROP INDEX name
  //   ADD [CONSTRAINT [symbol]] PRIMARY KEY [index_type] (cols)
  //                                 — knex.js: PRIMARY KEY name(cols); knex-dart: CONSTRAINT name PRIMARY KEY (cols)
  'schema/alter-table-add-column::mysql':
      '[ACCEPTED] MySQL: `ADD col_def` vs `ADD COLUMN col_def` — COLUMN is optional, both valid.',
  'schema/alter-table-drop-column::mysql':
      '[ACCEPTED] MySQL: `DROP col` vs `DROP COLUMN col` — COLUMN is optional, both valid.',
  'schema/alter-table-add-unique::mysql':
      '[ACCEPTED] MySQL: `ADD UNIQUE name(cols)` vs `ADD CONSTRAINT name UNIQUE (cols)` — both valid grammar forms.',
  'schema/alter-table-add-unique-named::mysql':
      '[ACCEPTED] see schema/alter-table-add-unique::mysql.',
  'schema/alter-table-add-index::mysql':
      '[ACCEPTED] MySQL: `ALTER TABLE ADD INDEX` vs `CREATE INDEX` are equivalent ways to add an index.',
  'schema/alter-table-add-index-named::mysql':
      '[ACCEPTED] see schema/alter-table-add-index::mysql.',
  'schema/alter-table-drop-index::mysql':
      '[ACCEPTED] MySQL: `DROP INDEX name ON table` vs `ALTER TABLE table DROP INDEX name` are equivalent.',
  'schema/alter-table-drop-index-named::mysql':
      '[ACCEPTED] see schema/alter-table-drop-index::mysql.',
  'schema/alter-table-primary::mysql':
      '[ACCEPTED] MySQL: `ADD PRIMARY KEY name(cols)` vs `ADD CONSTRAINT name PRIMARY KEY (cols)` — both valid.',

  // ── ACCEPTED: knex-dart targets modern MySQL/MariaDB (8.0+ / 10.5+, both
  // long-GA) and emits RENAME COLUMN directly. knex.js's `SHOW FULL FIELDS`
  // introspection is a compat shim for pre-8.0 MySQL, which had no RENAME
  // COLUMN and required reconstructing the full CHANGE COLUMN definition.
  // Deliberate "target current versions" choice, not a capability gap.
  'schema/alter-table-rename-column::mysql':
      '[ACCEPTED] knex-dart emits RENAME COLUMN directly (MySQL 8+/MariaDB '
          '10.5+); knex.js SHOW FULL FIELDS-introspects for pre-8.0 compat.',

  // ── ACCEPTED: cosmetic-only differences repeated across many cases —
  // grouped here instead of one entry per case×dialect.
  //
  // (1) FK action casing: `.onDelete('cascade')`/`.onUpdate('cascade')`
  //     uppercase the action (ColumnBuilder/ForeignBuilder both call
  //     `.toUpperCase()`); knex.js preserves the caller's casing verbatim.
  //     SQL keywords are case-insensitive — `CASCADE` and `cascade` are the
  //     same referential action. Changing knex-dart to preserve case would
  //     be a defensible follow-up but is not a correctness fix.
  // (2) `int`/`integer` on MySQL: knex.js emits `int`; knex-dart's
  //     `.integer()` emits `integer`. MySQL documents INTEGER as an exact
  //     synonym for INT — identical column, different spelling.
  // (3) Implicit NOT NULL on MySQL `AUTO_INCREMENT`/SQLite
  //     `INTEGER PRIMARY KEY`: both engines force NOT NULL on these columns
  //     regardless of an explicit NOT NULL keyword. knex.js states it
  //     redundantly; knex-dart omits the redundant keyword. Same column.
  // (4) SQLite inline `foreign key(col)` vs `foreign key (col)`: whitespace
  //     only.
  // (5) SQLite table-level PRIMARY KEY constraint naming: knex.js omits
  //     `constraint NAME` for an *unnamed* composite primary key on SQLite
  //     (there is no DROP CONSTRAINT path on SQLite to ever need the name —
  //     see the alter-table-drop-primary::sqlite entry above); knex-dart
  //     always names it. When a name IS explicitly given
  //     (create-table-primary-named), both sides include it identically —
  //     confirming this is a naming-when-absent style choice, not a
  //     structural difference.
  'schema/create-table-foreign-fluent-cascade::postgres':
      '[ACCEPTED] FK action casing only — see grouped note above (1).',
  'schema/create-table-foreign-fluent-cascade::cockroachdb':
      '[ACCEPTED] see schema/create-table-foreign-fluent-cascade::postgres.',
  'schema/create-table-foreign-fluent-cascade::redshift':
      '[ACCEPTED] see schema/create-table-foreign-fluent-cascade::postgres.',
  'schema/create-table-foreign-fluent-cascade::mysql':
      '[ACCEPTED] int/integer synonym + implicit NOT NULL — see grouped note above (2)(3).',
  'schema/create-table-foreign-fluent-cascade::sqlite':
      '[ACCEPTED] implicit NOT NULL + FK action casing + inline-FK whitespace — see grouped note above (1)(3)(4).',
  'schema/create-table-foreign-fluent-cascade::turso':
      '[ACCEPTED] see schema/create-table-foreign-fluent-cascade::sqlite (turso is sqlite-family).',
  'schema/create-table-foreign-fluent-cascade::d1':
      '[ACCEPTED] see schema/create-table-foreign-fluent-cascade::sqlite (d1 is sqlite-family).',
  'schema/create-table-foreign-onupdate::postgres':
      '[ACCEPTED] see schema/create-table-foreign-fluent-cascade::postgres.',
  'schema/create-table-foreign-onupdate::cockroachdb':
      '[ACCEPTED] see schema/create-table-foreign-fluent-cascade::postgres.',
  'schema/create-table-foreign-onupdate::redshift':
      '[ACCEPTED] see schema/create-table-foreign-fluent-cascade::postgres.',
  'schema/create-table-foreign-onupdate::mysql':
      '[ACCEPTED] see schema/create-table-foreign-fluent-cascade::mysql.',
  'schema/create-table-foreign-onupdate::sqlite':
      '[ACCEPTED] see schema/create-table-foreign-fluent-cascade::sqlite.',
  'schema/create-table-foreign-onupdate::turso':
      '[ACCEPTED] see schema/create-table-foreign-fluent-cascade::sqlite (turso is sqlite-family).',
  'schema/create-table-foreign-onupdate::d1':
      '[ACCEPTED] see schema/create-table-foreign-fluent-cascade::sqlite (d1 is sqlite-family).',
  'schema/create-table-foreign-column::mysql':
      '[ACCEPTED] see grouped note above (2)(3) — int/integer + implicit NOT NULL.',
  'schema/create-table-foreign-column::sqlite':
      '[ACCEPTED] see grouped note above (3)(4) — implicit NOT NULL + inline-FK whitespace.',
  'schema/create-table-foreign-column::turso':
      '[ACCEPTED] see schema/create-table-foreign-column::sqlite (turso is sqlite-family).',
  'schema/create-table-foreign-column::d1':
      '[ACCEPTED] see schema/create-table-foreign-column::sqlite (d1 is sqlite-family).',
  'schema/create-table-basic::mysql':
      '[ACCEPTED] see grouped note above (2)(3) — int/integer + implicit NOT NULL.',
  'schema/create-table-basic::sqlite':
      '[ACCEPTED] see grouped note above (3) — implicit NOT NULL.',
  'schema/create-table-basic::turso':
      '[ACCEPTED] see schema/create-table-basic::sqlite (turso is sqlite-family).',
  'schema/create-table-basic::d1':
      '[ACCEPTED] see schema/create-table-basic::sqlite (d1 is sqlite-family).',
  'schema/create-table-unique-column::mysql':
      '[ACCEPTED] see grouped note above (2)(3) — int/integer + implicit NOT NULL.',
  'schema/create-table-unique-column::sqlite':
      '[ACCEPTED] see grouped note above (3) — implicit NOT NULL.',
  'schema/create-table-unique-column::turso':
      '[ACCEPTED] see schema/create-table-unique-column::sqlite (turso is sqlite-family).',
  'schema/create-table-unique-column::d1':
      '[ACCEPTED] see schema/create-table-unique-column::sqlite (d1 is sqlite-family).',
  'schema/create-table-unique-named::mysql':
      '[ACCEPTED] see grouped note above (2)(3) — int/integer + implicit NOT NULL.',
  'schema/create-table-unique-named::sqlite':
      '[ACCEPTED] see grouped note above (3) — implicit NOT NULL.',
  'schema/create-table-unique-named::turso':
      '[ACCEPTED] see schema/create-table-unique-named::sqlite (turso is sqlite-family).',
  'schema/create-table-unique-named::d1':
      '[ACCEPTED] see schema/create-table-unique-named::sqlite (d1 is sqlite-family).',
  'schema/create-table-primary-named::mysql':
      '[ACCEPTED] see grouped note above (2) — int/integer synonym only '
          '(the constraint name is already identical on both sides).',

  // ── ACCEPTED: Redshift treats PRIMARY KEY as informational only (not
  // storage-enforced) and additionally refuses nullable columns in a
  // primary key client-side — knex.js's Redshift client silently drops the
  // whole constraint clause with just a console warning rather than
  // erroring. knex-dart doesn't model that restriction and emits the
  // constraint the caller asked for; Redshift's CREATE TABLE grammar
  // accepts a PRIMARY KEY clause on nullable columns (it's simply not
  // enforced at the storage layer, like all Redshift PK/FK/UNIQUE
  // constraints). knex-dart's behavior more faithfully reflects what the
  // caller declared instead of silently discarding it.
  'schema/create-table-primary-composite::redshift':
      '[ACCEPTED] knex.js silently drops the PK clause (console warning '
          'only) because Redshift disallows nullable PK columns client-side; '
          'knex-dart emits it — Redshift constraints are informational-only '
          'and the CREATE TABLE syntax accepts this.',
  'schema/create-table-primary-named::redshift':
      '[ACCEPTED] see schema/create-table-primary-composite::redshift.',

  // ── ACCEPTED: same "implicit NOT NULL" + "unnamed SQLite constraint
  // naming" pattern as the grouped note above, applied to the composite
  // (unnamed) primary key case specifically.
  'schema/create-table-primary-composite::mysql':
      '[ACCEPTED] see grouped note above (2) — int/integer synonym only.',
  'schema/create-table-primary-composite::sqlite':
      '[ACCEPTED] see grouped note above (5) — SQLite omits the constraint '
          'name when none was given; knex-dart always names it.',
  'schema/create-table-primary-composite::turso':
      '[ACCEPTED] see schema/create-table-primary-composite::sqlite (turso is sqlite-family).',
  'schema/create-table-primary-composite::d1':
      '[ACCEPTED] see schema/create-table-primary-composite::sqlite (d1 is sqlite-family).',

  // ── OPEN BUG: real knex-dart defects to fix (then delete these) ────────────

  // ── NEEDS VERIFICATION: could not confirm against a live CockroachDB
  // instance in this session. knex.js's CockroachDB client uses
  // `DROP INDEX "table"@"name" CASCADE` for dropping a UNIQUE constraint;
  // knex-dart emits standard `ALTER TABLE ... DROP CONSTRAINT name`.
  // CockroachDB added DROP CONSTRAINT support for UNIQUE constraints in
  // v21.2+, so knex-dart's form is plausibly correct on current CockroachDB
  // — but knex.js's dedicated compiler subclass for this exact case
  // suggests a real compatibility reason (older CockroachDB implements
  // UNIQUE as an index and may reject DROP CONSTRAINT on it). Left
  // unresolved rather than guessed at; whoever picks this up should test
  // both statements against docker-compose's cockroachdb service before
  // deciding which is correct (or whether both need to be version-gated).
  'schema/alter-table-drop-unique::cockroachdb':
      '[UNVERIFIED] knex.js uses DROP INDEX "t"@"name" CASCADE (CockroachDB-'
          'specific); knex-dart uses standard DROP CONSTRAINT. Needs a live '
          'CockroachDB check to confirm which (or both, version-gated) is correct.',
  'schema/alter-table-drop-unique-named::cockroachdb':
      '[UNVERIFIED] see schema/alter-table-drop-unique::cockroachdb.',
};

const Set<String> _skipDialects = {'mssql'};

const Set<String> _sqliteFamily = {'sqlite', 'turso', 'd1'};

String _normalizeSql(String sql, String dialect) =>
    _sqliteFamily.contains(dialect) ? sql.replaceAll('`', '"') : sql;

bool _isRefusal(Object e) =>
    e is StateError || e is ArgumentError || e is UnsupportedError;

bool _bindingsEqual(List<dynamic> got, List<dynamic> expected) {
  if (got.length != expected.length) return false;
  for (var i = 0; i < got.length; i++) {
    final a = got[i], b = expected[i];
    if (a is num && b is num) {
      if (a != b) return false;
    } else if (a != b) {
      return false;
    }
  }
  return true;
}

String? _divergence(
  Map<String, dynamic> entry,
  String dialect,
  SchemaParityCase b,
) {
  final jsRefused = entry.containsKey('error');

  List<Map<String, dynamic>>? got;
  Object? refusal;
  try {
    got = b(dialect);
  } catch (e) {
    if (_isRefusal(e)) {
      refusal = e;
    } else {
      rethrow;
    }
  }
  final dartRefused = refusal != null;

  if (jsRefused && dartRefused) return null;
  if (jsRefused && !dartRefused) {
    return 'knex.js refused (${entry['error']}) but knex-dart emitted: '
        '${got!.map((s) => s['sql']).toList()}';
  }
  if (!jsRefused && dartRefused) {
    return 'knex-dart refused ($refusal) but knex.js compiled: '
        '${(entry['statements'] as List).map((s) => (s as Map)['sql']).toList()}';
  }

  final expectedStatements = (entry['statements'] as List).cast<Map<String, dynamic>>();
  if (got!.length != expectedStatements.length) {
    return 'statement count: expected ${expectedStatements.length} '
        '(${expectedStatements.map((s) => s['sql']).toList()}), '
        'got ${got.length} (${got.map((s) => s['sql']).toList()})';
  }
  for (var i = 0; i < got.length; i++) {
    final expectedSql = _normalizeSql(expectedStatements[i]['sql'] as String, dialect);
    final gotSql = _normalizeSql(got[i]['sql'] as String, dialect);
    if (gotSql != expectedSql) {
      return 'statement $i SQL:\n  expected: $expectedSql\n  actual:   $gotSql';
    }
    final expectedBindings = (expectedStatements[i]['bindings'] as List).cast<dynamic>();
    final gotBindings = (got[i]['bindings'] as List).cast<dynamic>();
    if (!_bindingsEqual(gotBindings, expectedBindings)) {
      return 'statement $i bindings: expected $expectedBindings, got $gotBindings';
    }
  }
  return null;
}

Map<String, dynamic> _loadFixtures() {
  const rel = 'test/parity/fixtures/schema_parity_cases.json';
  final candidates = [
    rel,
    'packages/knex_dart/$rel',
    '${Directory.current.path}/$rel',
  ];
  for (final p in candidates) {
    final f = File(p);
    if (f.existsSync()) {
      return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    }
  }
  throw StateError(
    'schema_parity_cases.json not found (looked in: ${candidates.join(", ")}). '
    'Generate it with: node tool/parity/run_js_schema.mjs',
  );
}

void main() {
  final fixtures = _loadFixtures();
  final knexVersion = fixtures['knexVersion'];
  final entries = (fixtures['cases'] as List).cast<Map<String, dynamic>>();
  final fixtureIds = entries.map((e) => e['id'] as String).toSet();

  group('schema parity vs knex.js $knexVersion', () {
    test('every registered case has a fixture (regenerate if this fails)', () {
      final dartOnly = schemaParityCases.keys.toSet().difference(fixtureIds);
      expect(
        dartOnly,
        isEmpty,
        reason: 'Dart schema cases missing from the fixture — run '
            '`node tool/parity/run_js_schema.mjs`: $dartOnly',
      );
    });

    for (final entry in entries) {
      final id = entry['id'] as String;
      final dialect = entry['dialect'] as String;
      final key = '$id::$dialect';

      if (_skipDialects.contains(dialect)) {
        test(key, () {}, skip: 'dialect not driven by the core harness');
        continue;
      }

      final builder = schemaParityCases[id];
      if (builder == null) {
        test(key, () => fail('no knex-dart schema parity builder registered for "$id"'));
        continue;
      }

      final allowReason = schemaParityAllowlist[key];

      test(key, () {
        final divergence = _divergence(entry, dialect, builder);
        if (allowReason == null) {
          expect(divergence, isNull, reason: divergence);
        } else {
          expect(
            divergence,
            isNotNull,
            reason: 'Allowlisted divergence is no longer present — re-triage and '
                'remove this allowlist entry:\n  $allowReason',
          );
        }
      });
    }
  });
}
