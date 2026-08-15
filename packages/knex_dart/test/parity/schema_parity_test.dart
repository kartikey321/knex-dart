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
  'schema/alter-table-add-index-composite::redshift':
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
  //   ADD INDEX name (cols)  ==  CREATE INDEX name ON table (cols)
  //   DROP INDEX name ON table  ==  ALTER TABLE table DROP INDEX name
  //
  // (UNIQUE/PRIMARY KEY used to be listed here too — knex-dart previously
  // emitted the generic `ADD CONSTRAINT name UNIQUE/PRIMARY KEY (cols)` form
  // on every dialect including MySQL; it now matches knex.js's MySQL-native
  // `ADD UNIQUE name(cols)` / `ADD PRIMARY KEY name(cols)` exactly, so those
  // cases are no longer listed below.)
  'schema/alter-table-add-column::mysql':
      '[ACCEPTED] MySQL: `ADD col_def` vs `ADD COLUMN col_def` — COLUMN is optional, both valid.',
  'schema/default-string-embedded-quote::mysql':
      '[ACCEPTED] MySQL: knex.js uses backslash quote escaping while knex-dart '
          'uses standard doubled quotes; both produce the same string literal. '
          'Also `ADD` vs `ADD COLUMN` — see schema/alter-table-add-column::mysql.',
  'schema/default-null::mysql':
      '[ACCEPTED] MySQL: knex.js omits `DEFAULT NULL` (the implicit default); '
          'knex-dart states it explicitly. Also `ADD` vs `ADD COLUMN`.',
  'schema/default-string-not-null::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql — `ADD` vs `ADD COLUMN` only.',
  'schema/default-raw-current-timestamp::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql — `ADD` vs `ADD COLUMN` only.',
  'schema/default-boolean-false::mysql':
      '[ACCEPTED] MySQL BOOLEAN is a TINYINT(1) synonym; also `ADD` vs `ADD COLUMN` '
          '(see schema/alter-table-add-column::mysql).',
  'schema/default-json-object::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql — `ADD` vs `ADD COLUMN` only.',
  'schema/default-jsonb-object::mysql':
      '[ACCEPTED] see schema/default-json-object::mysql (MySQL maps JSONB to JSON).',
  'schema/alter-table-drop-column::mysql':
      '[ACCEPTED] MySQL: `DROP col` vs `DROP COLUMN col` — COLUMN is optional, both valid.',
  'schema/alter-table-add-index::mysql':
      '[ACCEPTED] MySQL: `ALTER TABLE ADD INDEX` vs `CREATE INDEX` are equivalent ways to add an index.',
  'schema/alter-table-add-index-named::mysql':
      '[ACCEPTED] see schema/alter-table-add-index::mysql.',
  'schema/alter-table-add-index-composite::mysql':
      '[ACCEPTED] see schema/alter-table-add-index::mysql.',
  'schema/create-table-unique-composite-named::mysql':
      '[ACCEPTED] MySQL INTEGER is an INT synonym — see grouped note above (2).',
  'schema/create-table-column-primary::redshift':
      '[ACCEPTED] knex.js defers this Redshift primary key and adds NOT NULL; '
          'knex-dart emits the valid inline informational constraint. See '
          'schema/create-table-primary-composite::redshift.',
  'schema/alter-table-add-column-foreign::mysql':
      '[ACCEPTED] MySQL INTEGER is an INT synonym and `ADD COLUMN` is equivalent '
          'to `ADD`; the generated foreign-key constraint matches.',
  'schema/alter-table-add-column-foreign::sqlite':
      '[ACCEPTED] SQLite: knex.js starts its PRAGMA-based table rebuild; '
          'knex-dart refuses ALTER TABLE ADD FOREIGN KEY rather than silently '
          'dropping it.',
  'schema/alter-table-add-column-foreign::turso':
      '[ACCEPTED] see schema/alter-table-add-column-foreign::sqlite (sqlite-family).',
  'schema/alter-table-add-column-foreign::d1':
      '[ACCEPTED] see schema/alter-table-add-column-foreign::sqlite (sqlite-family).',
  'schema/alter-table-drop-index::mysql':
      '[ACCEPTED] MySQL: `DROP INDEX name ON table` vs `ALTER TABLE table DROP INDEX name` are equivalent.',
  'schema/alter-table-drop-index-named::mysql':
      '[ACCEPTED] see schema/alter-table-drop-index::mysql.',

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
  // (6) ON DELETE/ON UPDATE clause order when BOTH are set on the same FK:
  //     knex.js always emits `on update ... on delete ...`; knex-dart always
  //     emits `on delete ... on update ...`. Standard SQL does not mandate
  //     an order between the two referential-action clauses in a FOREIGN
  //     KEY constraint definition (verified: both orderings parse and
  //     enforce identically) — cosmetic ordering only, not a semantic
  //     difference. (Caught by an adversarial review after the initial
  //     grouped note (1) was written covering only the casing difference —
  //     that note was accurate but incomplete for the both-actions-set case.)
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
  'schema/create-table-foreign-both-actions::postgres':
      '[ACCEPTED] FK action casing + ON DELETE/ON UPDATE clause order — see grouped note above (1)(6).',
  'schema/create-table-foreign-both-actions::cockroachdb':
      '[ACCEPTED] see schema/create-table-foreign-both-actions::postgres.',
  'schema/create-table-foreign-both-actions::redshift':
      '[ACCEPTED] see schema/create-table-foreign-both-actions::postgres.',
  'schema/create-table-foreign-both-actions::mysql':
      '[ACCEPTED] int/integer synonym + implicit NOT NULL + FK action casing + clause order — see grouped note above (1)(2)(3)(6).',
  'schema/create-table-foreign-both-actions::sqlite':
      '[ACCEPTED] implicit NOT NULL + FK action casing + inline-FK whitespace + clause order — see grouped note above (1)(3)(4)(6).',
  'schema/create-table-foreign-both-actions::turso':
      '[ACCEPTED] see schema/create-table-foreign-both-actions::sqlite (turso is sqlite-family).',
  'schema/create-table-foreign-both-actions::d1':
      '[ACCEPTED] see schema/create-table-foreign-both-actions::sqlite (d1 is sqlite-family).',
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

  // ── ACCEPTED: verified live against a real CockroachDB v26.2.4 instance
  // (docker run cockroachdb/cockroach:latest start-single-node --insecure).
  // Both forms actually work: created a UNIQUE constraint via `ALTER TABLE
  // ADD CONSTRAINT ... UNIQUE`, then confirmed each drop form genuinely
  // removes it (not just "doesn't error") by inserting a duplicate value
  // afterward and getting success, not a unique-violation. knex-dart's
  // simpler `ALTER TABLE ... DROP CONSTRAINT name` is correct on current
  // CockroachDB — the DROP CONSTRAINT support for UNIQUE constraints added
  // in v21.2 covers this. Not version-gating; CockroachDB versions old
  // enough to lack it are well past any support the "cockroachdb" dialect
  // targets.
  'schema/alter-table-drop-unique::cockroachdb':
      '[ACCEPTED] verified live against real CockroachDB v26.2.4: '
          '`ALTER TABLE ... DROP CONSTRAINT name` genuinely drops the unique '
          "constraint (confirmed via duplicate-insert after drop). knex.js's "
          'DROP INDEX "t"@"name" CASCADE also works — both are correct, '
          'different spelling.',
  'schema/alter-table-drop-unique-named::cockroachdb':
      '[ACCEPTED] see schema/alter-table-drop-unique::cockroachdb.',

  // ── ACCEPTED: unsigned() column-modifier dispatch — same int/integer
  // synonym (grouped note (2)) and ADD/ADD COLUMN spelling (grouped note
  // above) as elsewhere; the `unsigned` keyword itself matches identically
  // on both sides in both createTable and alterTable-add-column forms,
  // confirming the unsigned dispatch itself (MySQL-only grammar; postgres/
  // sqlite silently ignore it, verified against real knex.js output) is
  // correct — only the pre-existing cosmetic spelling differences repeat.
  'schema/create-table-column-unsigned::mysql':
      '[ACCEPTED] MySQL INTEGER is an INT synonym — see grouped note above (2).',
  'schema/alter-table-column-unsigned::mysql':
      '[ACCEPTED] MySQL: int/integer synonym + `ADD` vs `ADD COLUMN` — see '
          'grouped note above (2) and schema/alter-table-add-column::mysql.',

  // ── ACCEPTED: schema-mining batch 5 (round-2 recovery) — new cases hitting
  // the SAME already-documented cosmetic MySQL divergences above (ADD vs ADD
  // COLUMN, implicit NOT NULL on AUTO_INCREMENT, int/integer, BOOLEAN/TINYINT(1)),
  // just on column types the earlier corpus didn't happen to cover.
  'schema/alter-table-add-bigincrements::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql and grouped notes above (2)(3) — ADD/ADD COLUMN, implicit NOT NULL, int/integer, or BOOLEAN/TINYINT(1) only.',
  'schema/alter-table-add-bigincrements::sqlite':
      '[ACCEPTED] see grouped note above (3) — implicit NOT NULL on SQLite INTEGER PRIMARY KEY only.',
  'schema/alter-table-add-bigincrements::turso':
      '[ACCEPTED] see schema/alter-table-add-bigincrements::sqlite (turso is sqlite-family).',
  'schema/alter-table-add-bigincrements::d1':
      '[ACCEPTED] see schema/alter-table-add-bigincrements::sqlite (d1 is sqlite-family).',
  'schema/alter-table-add-increments::sqlite':
      '[ACCEPTED] see grouped note above (3) — implicit NOT NULL on SQLite INTEGER PRIMARY KEY only.',
  'schema/alter-table-add-increments::turso':
      '[ACCEPTED] see schema/alter-table-add-increments::sqlite (turso is sqlite-family).',
  'schema/alter-table-add-increments::d1':
      '[ACCEPTED] see schema/alter-table-add-increments::sqlite (d1 is sqlite-family).',
  'schema/column-bigincrements::sqlite':
      '[ACCEPTED] see grouped note above (3) — implicit NOT NULL on SQLite INTEGER PRIMARY KEY only.',
  'schema/column-bigincrements::turso':
      '[ACCEPTED] see schema/column-bigincrements::sqlite (turso is sqlite-family).',
  'schema/column-bigincrements::d1':
      '[ACCEPTED] see schema/column-bigincrements::sqlite (d1 is sqlite-family).',
  'schema/column-increments::sqlite':
      '[ACCEPTED] see grouped note above (3) — implicit NOT NULL on SQLite INTEGER PRIMARY KEY only.',
  'schema/column-increments::turso':
      '[ACCEPTED] see schema/column-increments::sqlite (turso is sqlite-family).',
  'schema/column-increments::d1':
      '[ACCEPTED] see schema/column-increments::sqlite (d1 is sqlite-family).',
  'schema/column-uuid::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql — ADD vs ADD COLUMN only.',
  'schema/alter-table-add-biginteger::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql and grouped notes above (2)(3) — ADD/ADD COLUMN, implicit NOT NULL, int/integer, or BOOLEAN/TINYINT(1) only.',
  'schema/alter-table-add-binary::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql and grouped notes above (2)(3) — ADD/ADD COLUMN, implicit NOT NULL, int/integer, or BOOLEAN/TINYINT(1) only.',
  'schema/alter-table-add-boolean::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql and grouped notes above (2)(3) — ADD/ADD COLUMN, implicit NOT NULL, int/integer, or BOOLEAN/TINYINT(1) only.',
  'schema/alter-table-add-date::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql and grouped notes above (2)(3) — ADD/ADD COLUMN, implicit NOT NULL, int/integer, or BOOLEAN/TINYINT(1) only.',
  'schema/alter-table-add-datetime::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql and grouped notes above (2)(3) — ADD/ADD COLUMN, implicit NOT NULL, int/integer, or BOOLEAN/TINYINT(1) only.',
  'schema/alter-table-add-decimal::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql and grouped notes above (2)(3) — ADD/ADD COLUMN, implicit NOT NULL, int/integer, or BOOLEAN/TINYINT(1) only.',
  'schema/alter-table-add-double::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql and grouped notes above (2)(3) — ADD/ADD COLUMN, implicit NOT NULL, int/integer, or BOOLEAN/TINYINT(1) only.',
  'schema/alter-table-add-enum::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql and grouped notes above (2)(3) — ADD/ADD COLUMN, implicit NOT NULL, int/integer, or BOOLEAN/TINYINT(1) only.',
  'schema/alter-table-add-increments::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql and grouped notes above (2)(3) — ADD/ADD COLUMN, implicit NOT NULL, int/integer, or BOOLEAN/TINYINT(1) only.',
  'schema/alter-table-add-json::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql and grouped notes above (2)(3) — ADD/ADD COLUMN, implicit NOT NULL, int/integer, or BOOLEAN/TINYINT(1) only.',
  'schema/alter-table-add-jsonb::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql and grouped notes above (2)(3) — ADD/ADD COLUMN, implicit NOT NULL, int/integer, or BOOLEAN/TINYINT(1) only.',
  'schema/alter-table-add-text::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql and grouped notes above (2)(3) — ADD/ADD COLUMN, implicit NOT NULL, int/integer, or BOOLEAN/TINYINT(1) only.',
  'schema/alter-table-add-time::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql and grouped notes above (2)(3) — ADD/ADD COLUMN, implicit NOT NULL, int/integer, or BOOLEAN/TINYINT(1) only.',
  'schema/alter-table-add-timestamp::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql and grouped notes above (2)(3) — ADD/ADD COLUMN, implicit NOT NULL, int/integer, or BOOLEAN/TINYINT(1) only.',
  'schema/alter-table-add-uuid::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql and grouped notes above (2)(3) — ADD/ADD COLUMN, implicit NOT NULL, int/integer, or BOOLEAN/TINYINT(1) only.',
  'schema/column-bigincrements::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql and grouped notes above (2)(3) — ADD/ADD COLUMN, implicit NOT NULL, int/integer, or BOOLEAN/TINYINT(1) only.',
  'schema/column-biginteger::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql and grouped notes above (2)(3) — ADD/ADD COLUMN, implicit NOT NULL, int/integer, or BOOLEAN/TINYINT(1) only.',
  'schema/column-binary::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql and grouped notes above (2)(3) — ADD/ADD COLUMN, implicit NOT NULL, int/integer, or BOOLEAN/TINYINT(1) only.',
  'schema/column-boolean-default::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql and grouped notes above (2)(3) — ADD/ADD COLUMN, implicit NOT NULL, int/integer, or BOOLEAN/TINYINT(1) only.',
  'schema/column-date::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql and grouped notes above (2)(3) — ADD/ADD COLUMN, implicit NOT NULL, int/integer, or BOOLEAN/TINYINT(1) only.',
  'schema/column-datetime::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql and grouped notes above (2)(3) — ADD/ADD COLUMN, implicit NOT NULL, int/integer, or BOOLEAN/TINYINT(1) only.',
  'schema/column-decimal::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql and grouped notes above (2)(3) — ADD/ADD COLUMN, implicit NOT NULL, int/integer, or BOOLEAN/TINYINT(1) only.',
  'schema/column-double::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql and grouped notes above (2)(3) — ADD/ADD COLUMN, implicit NOT NULL, int/integer, or BOOLEAN/TINYINT(1) only.',
  'schema/column-enum::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql and grouped notes above (2)(3) — ADD/ADD COLUMN, implicit NOT NULL, int/integer, or BOOLEAN/TINYINT(1) only.',
  'schema/column-float::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql and grouped notes above (2)(3) — ADD/ADD COLUMN, implicit NOT NULL, int/integer, or BOOLEAN/TINYINT(1) only.',
  'schema/column-increments::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql and grouped notes above (2)(3) — ADD/ADD COLUMN, implicit NOT NULL, int/integer, or BOOLEAN/TINYINT(1) only.',
  'schema/column-integer::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql and grouped notes above (2)(3) — ADD/ADD COLUMN, implicit NOT NULL, int/integer, or BOOLEAN/TINYINT(1) only.',
  'schema/column-json-default-notnull::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql and grouped notes above (2)(3) — ADD/ADD COLUMN, implicit NOT NULL, int/integer, or BOOLEAN/TINYINT(1) only.',
  'schema/column-jsonb::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql and grouped notes above (2)(3) — ADD/ADD COLUMN, implicit NOT NULL, int/integer, or BOOLEAN/TINYINT(1) only.',
  'schema/column-specifictype-unique-notnull::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql and grouped notes above (2)(3) — ADD/ADD COLUMN, implicit NOT NULL, int/integer, or BOOLEAN/TINYINT(1) only.',
  'schema/column-string-default::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql and grouped notes above (2)(3) — ADD/ADD COLUMN, implicit NOT NULL, int/integer, or BOOLEAN/TINYINT(1) only.',
  'schema/column-string-length::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql and grouped notes above (2)(3) — ADD/ADD COLUMN, implicit NOT NULL, int/integer, or BOOLEAN/TINYINT(1) only.',
  'schema/column-text::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql and grouped notes above (2)(3) — ADD/ADD COLUMN, implicit NOT NULL, int/integer, or BOOLEAN/TINYINT(1) only.',
  'schema/column-time::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql and grouped notes above (2)(3) — ADD/ADD COLUMN, implicit NOT NULL, int/integer, or BOOLEAN/TINYINT(1) only.',
  'schema/column-timestamp::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql and grouped notes above (2)(3) — ADD/ADD COLUMN, implicit NOT NULL, int/integer, or BOOLEAN/TINYINT(1) only.',

  // ── ACCEPTED: SQLite-family multi-column ALTER TABLE — same PRAGMA-based
  // table-rebuild precedent as schema/alter-table-drop-column::sqlite, just for
  // the multi-column drop() and dropTimestamps() forms. SQLite's ALTER TABLE
  // grammar also only allows one operation per statement, so a comma-joined
  // multi-drop (valid on other dialects) isn't an option either — knex-dart
  // emits one valid DROP COLUMN statement per column instead of knex.js's
  // PRAGMA rebuild.
  'schema/alter-table-drop-columns-multiple::sqlite':
      '[ACCEPTED] see schema/alter-table-drop-column::sqlite — same PRAGMA-based table-rebuild precedent, multi-column form.',
  'schema/alter-table-drop-columns-multiple::turso':
      '[ACCEPTED] see schema/alter-table-drop-columns-multiple::sqlite (turso is sqlite-family).',
  'schema/alter-table-drop-columns-multiple::d1':
      '[ACCEPTED] see schema/alter-table-drop-columns-multiple::sqlite (d1 is sqlite-family).',
  'schema/alter-table-drop-timestamps::sqlite':
      '[ACCEPTED] see schema/alter-table-drop-column::sqlite — same PRAGMA-based table-rebuild precedent, multi-column form.',
  'schema/alter-table-drop-timestamps::turso':
      '[ACCEPTED] see schema/alter-table-drop-timestamps::sqlite (turso is sqlite-family).',
  'schema/alter-table-drop-timestamps::d1':
      '[ACCEPTED] see schema/alter-table-drop-timestamps::sqlite (d1 is sqlite-family).',

  // ── ACCEPTED: SQLite-family — knex-dart refuses ALTER TABLE ADD/DROP
  // FOREIGN KEY / PRIMARY KEY on an existing table rather than silently routing
  // through knex.js's PRAGMA-based table-rebuild dance (same precedent as
  // schema/alter-table-add-column-foreign::sqlite).
  'schema/alter-table-drop-foreign-null-columns-named::sqlite':
      '[ACCEPTED] see schema/alter-table-add-column-foreign::sqlite — knex-dart refuses rather than routing through a PRAGMA-based table rebuild.',
  'schema/alter-table-drop-foreign-null-columns-named::turso':
      '[ACCEPTED] see schema/alter-table-drop-foreign-null-columns-named::sqlite (turso is sqlite-family).',
  'schema/alter-table-drop-foreign-null-columns-named::d1':
      '[ACCEPTED] see schema/alter-table-drop-foreign-null-columns-named::sqlite (d1 is sqlite-family).',
  'schema/alter-table-primary-single-column::sqlite':
      '[ACCEPTED] see schema/alter-table-add-column-foreign::sqlite — knex-dart refuses rather than routing through a PRAGMA-based table rebuild.',
  'schema/alter-table-primary-single-column::turso':
      '[ACCEPTED] see schema/alter-table-primary-single-column::sqlite (turso is sqlite-family).',
  'schema/alter-table-primary-single-column::d1':
      '[ACCEPTED] see schema/alter-table-primary-single-column::sqlite (d1 is sqlite-family).',
  'schema/alter-table-primary-named::sqlite':
      '[ACCEPTED] see schema/alter-table-add-column-foreign::sqlite — knex-dart refuses rather than routing through a PRAGMA-based table rebuild.',
  'schema/alter-table-primary-named::turso':
      '[ACCEPTED] see schema/alter-table-primary-named::sqlite (turso is sqlite-family).',
  'schema/alter-table-primary-named::d1':
      '[ACCEPTED] see schema/alter-table-primary-named::sqlite (d1 is sqlite-family).',

  // ── ACCEPTED: CockroachDB — same verified-live DROP CONSTRAINT vs DROP INDEX
  // ... CASCADE equivalence as schema/alter-table-drop-unique::cockroachdb, on
  // the composite-columns and null-columns-named forms.
  'schema/alter-table-drop-unique-composite::cockroachdb':
      '[ACCEPTED] see schema/alter-table-drop-unique::cockroachdb.',
  'schema/alter-table-drop-unique-null-columns-named::cockroachdb':
      '[ACCEPTED] see schema/alter-table-drop-unique::cockroachdb.',

  // ── ACCEPTED: same DROP INDEX form-choice divergence as
  // schema/alter-table-drop-index::mysql, on the null-columns-explicit-name form.
  'schema/alter-table-drop-index-null-columns-named::mysql':
      '[ACCEPTED] see schema/alter-table-drop-index::mysql.',
  'schema/alter-table-drop-index-null-columns-named::redshift':
      '[ACCEPTED] see schema/alter-table-drop-index::redshift — knex.js silently no-ops (empty statement list) for every Redshift dropIndex call, including this null-columns-named form; knex-dart throws instead of silently doing nothing.',

  // ── OPEN BUG: knex.js batches every column added via alterTable() into a
  // single comma-joined ALTER TABLE statement (`add col1, add col2`);
  // knex-dart emits one ALTER TABLE per column. Both are valid SQL and both
  // add the same columns, but the *statement count* differs, so the harness
  // flags it as a real (structural, not cosmetic) divergence. Fixing this
  // means restructuring `_alterTable`'s "handle added columns" loop to
  // collect all added columns into one statement per dialect's ADD syntax —
  // deferred as a separate, non-trivial pass (same architectural scope as
  // the FK-column-list gap already noted in run_js_schema.mjs). Affects any
  // multi-column add, not just timestamps() — these are just the cases the
  // corpus happens to cover.
  'schema/alter-table-add-timestamps::postgres':
      '[OPEN BUG] knex.js batches multi-column ADD into one ALTER TABLE '
          'statement; knex-dart emits one per column. See grouped OPEN BUG '
          'note above this block.',
  'schema/alter-table-add-timestamps::cockroachdb':
      '[OPEN BUG] see schema/alter-table-add-timestamps::postgres.',
  'schema/alter-table-add-timestamps::mysql':
      '[OPEN BUG] see schema/alter-table-add-timestamps::postgres (plus the '
          'already-accepted ADD/ADD COLUMN cosmetic spelling on top).',
  'schema/column-timestamps-basic::postgres':
      '[OPEN BUG] see schema/alter-table-add-timestamps::postgres.',
  'schema/column-timestamps-basic::cockroachdb':
      '[OPEN BUG] see schema/alter-table-add-timestamps::postgres.',
  'schema/column-timestamps-basic::mysql':
      '[OPEN BUG] see schema/alter-table-add-timestamps::mysql.',
  'schema/column-timestamps-defaults::postgres':
      '[OPEN BUG] see schema/alter-table-add-timestamps::postgres.',
  'schema/column-timestamps-defaults::cockroachdb':
      '[OPEN BUG] see schema/alter-table-add-timestamps::postgres.',
  'schema/column-timestamps-defaults::mysql':
      '[OPEN BUG] see schema/alter-table-add-timestamps::mysql.',

  // ── OPEN BUG: createTableLike unconditionally emits Postgres's `LIKE ...
  // INCLUDING ALL` even when no extra columns/dialect calls for it, and
  // folds extra columns into the same CREATE TABLE statement instead of
  // knex.js's separate ALTER TABLE ADD COLUMN statements after. Redshift
  // has no `INCLUDING ALL` clause at all (bare `LIKE source`) and, like
  // Postgres, adds extra columns via follow-up ALTER TABLE statements, not
  // inline in the CREATE TABLE. Needs a real per-dialect rework of
  // `_createTableLike`, not a one-line fix — deferred.
  'schema/create-table-like-basic::redshift':
      '[OPEN BUG] knex-dart always emits `including all`; knex.js\'s '
          'Redshift LIKE clause has no such option (bare `like source`).',
  'schema/create-table-like-with-columns::redshift':
      '[OPEN BUG] see schema/create-table-like-basic::redshift, plus extra '
          'columns need separate ALTER TABLE ADD COLUMN statements after, '
          'not inline in the CREATE TABLE.',
  'schema/create-table-like-with-columns::mysql':
      '[OPEN BUG] knex-dart folds extra createTableLike columns into '
          'separate single-column ALTER TABLE statements with `ADD COLUMN`; '
          'knex.js batches them into one `ALTER TABLE ... ADD col1, ADD '
          'col2` statement (same batching gap as '
          'schema/alter-table-add-timestamps::postgres) using MySQL\'s bare '
          '`ADD` spelling.',

  // ── OPEN BUG: when an incrementing column (`t.increments()`) is also a
  // member of a composite `t.primary([...])`, knex.js suppresses the
  // column's own inline "primary key" (it can only belong to one PK
  // clause) and defers entirely to the composite constraint — on MySQL this
  // additionally requires a second `ALTER TABLE ... MODIFY COLUMN ...
  // AUTO_INCREMENT` statement, since MySQL requires the auto_increment
  // column to be *some* key before it can carry AUTO_INCREMENT, and the
  // inline `int auto_increment primary key` form can't be used once the
  // column joins a composite key instead. knex-dart's ColumnBuilder has no
  // way to know at column-definition time whether it will later be folded
  // into a composite primary() — needs cross-referencing increments()
  // columns against the table's primary() call before emitting the column
  // type string. Real, but a cross-column-aware refactor, not a local fix —
  // deferred.
  'schema/create-table-primary-composite-with-increments::postgres':
      '[OPEN BUG] increments() column should omit its own inline "primary '
          'key" once it participates in a composite primary(); see grouped '
          'note above this block.',
  'schema/create-table-primary-composite-with-increments::cockroachdb':
      '[OPEN BUG] see schema/create-table-primary-composite-with-increments::postgres.',
  'schema/create-table-primary-composite-with-increments::redshift':
      '[OPEN BUG] see schema/create-table-primary-composite-with-increments::postgres.',
  'schema/create-table-primary-composite-with-increments::sqlite':
      '[OPEN BUG] SQLite additionally converts the composite PK (once an '
          'autoincrement column is involved, since SQLite only allows '
          '`INTEGER PRIMARY KEY AUTOINCREMENT` on a single column) into a '
          'plain UNIQUE constraint instead — not implemented.',
  'schema/create-table-primary-composite-with-increments::turso':
      '[OPEN BUG] see schema/create-table-primary-composite-with-increments::sqlite (turso is sqlite-family).',
  'schema/create-table-primary-composite-with-increments::d1':
      '[OPEN BUG] see schema/create-table-primary-composite-with-increments::sqlite (d1 is sqlite-family).',
  'schema/create-table-primary-composite-with-increments::mysql':
      '[OPEN BUG] see schema/create-table-primary-composite-with-increments::postgres, '
          'plus MySQL needs a second `ALTER TABLE ... MODIFY COLUMN ... '
          'AUTO_INCREMENT` statement since the increments() column can no '
          'longer carry an inline `auto_increment primary key`.',

  // ── OPEN BUG: CREATE VIEW/CREATE MATERIALIZED VIEW definitions bind their
  // WHERE-clause values as query parameters ($1/?), but DDL statements
  // can't carry bindings on every driver — knex.js inlines the literal
  // value directly into the view's SELECT text instead. A fix for this
  // (an `_inlineBindings()` helper on the compiled SELECT before emitting
  // the CREATE VIEW statement) already exists, verified correct, on the
  // separate `fix/mariadb-mysql-family-dispatch` branch (commit 643f4d9) —
  // not reimplemented here to avoid two independent fixes for the same bug
  // landing in two branches that then have to merge. Merge that branch (or
  // port just that helper) to close these.
  'schema/view-create-basic::postgres':
      '[OPEN BUG] view SELECT bindings not inlined — fix exists on '
          'fix/mariadb-mysql-family-dispatch (_inlineBindings, commit '
          '643f4d9); see grouped note above this block.',
  'schema/view-create-basic::cockroachdb':
      '[OPEN BUG] see schema/view-create-basic::postgres.',
  'schema/view-create-basic::redshift':
      '[OPEN BUG] see schema/view-create-basic::postgres.',
  'schema/view-create-basic::mysql':
      '[OPEN BUG] see schema/view-create-basic::postgres.',
  'schema/view-create-basic::sqlite':
      '[OPEN BUG] see schema/view-create-basic::postgres.',
  'schema/view-create-basic::turso':
      '[OPEN BUG] see schema/view-create-basic::postgres (turso is sqlite-family).',
  'schema/view-create-basic::d1':
      '[OPEN BUG] see schema/view-create-basic::postgres (d1 is sqlite-family).',
  'schema/view-create-or-replace::postgres':
      '[OPEN BUG] see schema/view-create-basic::postgres.',
  'schema/view-create-or-replace::cockroachdb':
      '[OPEN BUG] see schema/view-create-basic::postgres.',
  'schema/view-create-or-replace::redshift':
      '[OPEN BUG] see schema/view-create-basic::postgres.',
  'schema/view-create-or-replace::mysql':
      '[OPEN BUG] see schema/view-create-basic::postgres.',
  'schema/view-create-or-replace::sqlite':
      '[OPEN BUG] see schema/view-create-basic::postgres.',
  'schema/view-create-or-replace::turso':
      '[OPEN BUG] see schema/view-create-basic::postgres (turso is sqlite-family).',
  'schema/view-create-or-replace::d1':
      '[OPEN BUG] see schema/view-create-basic::postgres (d1 is sqlite-family).',
  'schema/view-create-materialized::postgres':
      '[OPEN BUG] see schema/view-create-basic::postgres.',
  'schema/view-create-materialized::cockroachdb':
      '[OPEN BUG] see schema/view-create-basic::postgres.',
  'schema/view-create-materialized::redshift':
      '[OPEN BUG] see schema/view-create-basic::postgres.',

  // ── ACCEPTED: schema-mining batch 6 (postgres.js) — new cases hitting the
  // SAME already-documented divergence patterns above, just via API shapes
  // (withSchema()-qualified index drops, fluent column-level .primary(),
  // multiple deferred FK statements in one createTable) the earlier corpus
  // didn't happen to exercise.

  // "drop index, with schema": MySQL's already-documented ADD/DROP INDEX
  // spelling choice, plus Redshift's already-documented index-deletion
  // refusal — now exercised with withSchema() in play too.
  'schema/alter-table-drop-index-with-schema::mysql':
      '[ACCEPTED] see schema/alter-table-drop-index::mysql.',
  'schema/alter-table-drop-index-with-schema::redshift':
      '[ACCEPTED] see schema/alter-table-drop-index::redshift — knex.js '
          'silently no-ops (empty statement list) for Redshift dropIndex, '
          'including the withSchema() form; knex-dart throws instead.',

  // "drop primary takes constraint name" / bare "adding primary key"
  // (unnamed single column): same SQLite PRAGMA-table-rebuild precedent as
  // the existing alter-table-drop-primary / alter-table-primary-single-column
  // entries — just the named-constraint and bare-unnamed-column variants of
  // those same two operations.
  'schema/alter-table-drop-primary-named::sqlite':
      '[ACCEPTED] see schema/alter-table-drop-primary::sqlite.',
  'schema/alter-table-drop-primary-named::turso':
      '[ACCEPTED] see schema/alter-table-drop-primary::sqlite (turso is sqlite-family).',
  'schema/alter-table-drop-primary-named::d1':
      '[ACCEPTED] see schema/alter-table-drop-primary::sqlite (d1 is sqlite-family).',
  'schema/alter-table-primary-single-column-unnamed::sqlite':
      '[ACCEPTED] see schema/alter-table-primary-single-column::sqlite.',
  'schema/alter-table-primary-single-column-unnamed::turso':
      '[ACCEPTED] see schema/alter-table-primary-single-column::sqlite (turso is sqlite-family).',
  'schema/alter-table-primary-single-column-unnamed::d1':
      '[ACCEPTED] see schema/alter-table-primary-single-column::sqlite (d1 is sqlite-family).',

  // "adds foreign key with onUpdate and onDelete": two FK columns in one
  // createTable, each with a single action — same FK-action-casing (1),
  // int/integer synonym (2), implicit NOT NULL (3), and inline-FK whitespace
  // (4) grouped notes as the existing single-action FK cases, just with two
  // deferred FK statements instead of one.
  'schema/create-table-foreign-mixed-actions::postgres':
      '[ACCEPTED] FK action casing only — see grouped note above (1).',
  'schema/create-table-foreign-mixed-actions::cockroachdb':
      '[ACCEPTED] see schema/create-table-foreign-mixed-actions::postgres.',
  'schema/create-table-foreign-mixed-actions::redshift':
      '[ACCEPTED] see schema/create-table-foreign-mixed-actions::postgres.',
  'schema/create-table-foreign-mixed-actions::mysql':
      '[ACCEPTED] int/integer synonym + FK action casing — see grouped note above (1)(2).',
  'schema/create-table-foreign-mixed-actions::sqlite':
      '[ACCEPTED] implicit NOT NULL + FK action casing + inline-FK whitespace — see grouped note above (1)(3)(4).',
  'schema/create-table-foreign-mixed-actions::turso':
      '[ACCEPTED] see schema/create-table-foreign-mixed-actions::sqlite (turso is sqlite-family).',
  'schema/create-table-foreign-mixed-actions::d1':
      '[ACCEPTED] see schema/create-table-foreign-mixed-actions::sqlite (d1 is sqlite-family).',

  // "alter with primary" > "liquid argument" / "liquid argument with name":
  // fluent column.primary() on a newly ADDed column. Redshift forces NOT
  // NULL on the new column because it will carry a primary key (same
  // "Redshift disallows nullable PK columns" reasoning as
  // create-table-column-primary::redshift, just manifesting on an ADD
  // COLUMN statement instead of an inline CREATE TABLE column def); MySQL
  // is the already-documented ADD/ADD COLUMN spelling choice; SQLite-family
  // is the already-documented PRAGMA-table-rebuild refusal.
  'schema/alter-table-add-column-primary-fluent::redshift':
      '[ACCEPTED] Redshift forces NOT NULL on a column that will carry a '
          'primary key — same reasoning as schema/create-table-column-primary::redshift, '
          'here on an ADD COLUMN statement rather than an inline CREATE TABLE column def.',
  'schema/alter-table-add-column-primary-fluent::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql — ADD vs ADD COLUMN only.',
  'schema/alter-table-add-column-primary-fluent::sqlite':
      '[ACCEPTED] see schema/alter-table-add-column-foreign::sqlite — knex-dart refuses rather than routing through a PRAGMA-based table rebuild.',
  'schema/alter-table-add-column-primary-fluent::turso':
      '[ACCEPTED] see schema/alter-table-add-column-primary-fluent::sqlite (turso is sqlite-family).',
  'schema/alter-table-add-column-primary-fluent::d1':
      '[ACCEPTED] see schema/alter-table-add-column-primary-fluent::sqlite (d1 is sqlite-family).',
  'schema/alter-table-add-column-primary-fluent-named::redshift':
      '[ACCEPTED] see schema/alter-table-add-column-primary-fluent::redshift.',
  'schema/alter-table-add-column-primary-fluent-named::mysql':
      '[ACCEPTED] see schema/alter-table-add-column::mysql — ADD vs ADD COLUMN only.',
  'schema/alter-table-add-column-primary-fluent-named::sqlite':
      '[ACCEPTED] see schema/alter-table-add-column-primary-fluent::sqlite.',
  'schema/alter-table-add-column-primary-fluent-named::turso':
      '[ACCEPTED] see schema/alter-table-add-column-primary-fluent::sqlite (turso is sqlite-family).',
  'schema/alter-table-add-column-primary-fluent-named::d1':
      '[ACCEPTED] see schema/alter-table-add-column-primary-fluent::sqlite (d1 is sqlite-family).',

  // "#1430" second part — fluent column.primary(name) inside createTable, on
  // Redshift: same deferred-primary-key-with-forced-NOT-NULL reasoning as
  // create-table-column-primary::redshift, just with an explicit constraint
  // name instead of the auto-generated `<table>_pkey`.
  'schema/create-table-primary-fluent-named::redshift':
      '[ACCEPTED] see schema/create-table-column-primary::redshift.',

  // ── ACCEPTED: schema-mining batch 7 — MSSQL wired into the parity harness
  // for the first time (previously entirely skipped, see _skipDialects below).
  // knex.js's mssql client is the only client that emits DDL keywords in
  // UPPERCASE (CREATE TABLE, ALTER TABLE, ADD, CONSTRAINT, PRIMARY KEY, DROP,
  // ...); knex-dart uses lowercase uniformly across every dialect, matching SQL's
  // own case-insensitivity for keywords (same precedent as the MySQL ADD/ADD
  // COLUMN spelling difference above) — not chased here, it would mean
  // case-migrating every string literal in the compiler against the codebase's
  // uniform convention for zero behavioral gain. Several of these also repeat
  // the existing int/integer synonym grouped note (2).
  'schema/alter-table-add-bigincrements::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/alter-table-add-biginteger::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/alter-table-add-binary::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/alter-table-add-boolean::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/alter-table-add-column::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/alter-table-add-column-foreign::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/alter-table-add-date::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/alter-table-add-datetime::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/alter-table-add-decimal::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/alter-table-add-double::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/alter-table-add-enum::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/alter-table-add-increments::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/alter-table-add-index::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/alter-table-add-index-composite::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/alter-table-add-index-named::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/alter-table-add-json::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/alter-table-add-jsonb::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/alter-table-add-text::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/alter-table-add-time::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/alter-table-add-timestamp::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/alter-table-add-unique::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/alter-table-add-unique-composite::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/alter-table-add-unique-named::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/alter-table-add-uuid::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/alter-table-column-unsigned::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/alter-table-drop-foreign::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/alter-table-drop-foreign-null-columns-named::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/alter-table-drop-index::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/alter-table-drop-index-named::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/alter-table-drop-index-null-columns-named::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/alter-table-drop-primary::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/alter-table-drop-unique::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/alter-table-drop-unique-composite::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/alter-table-drop-unique-named::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/alter-table-drop-unique-null-columns-named::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/alter-table-foreign::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/alter-table-primary::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/alter-table-primary-named::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/alter-table-primary-single-column::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/alter-table-unique-single-column::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/column-bigincrements::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/column-biginteger::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/column-binary::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/column-boolean-default::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/column-date::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/column-datetime::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/column-decimal::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/column-double::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/column-enum::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/column-float::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/column-increments::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/column-integer::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/column-json-default-notnull::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/column-jsonb::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/column-specifictype-unique-notnull::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/column-string-default::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/column-string-length::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/column-text::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/column-time::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/column-timestamp::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/column-uuid::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/create-table-basic::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/create-table-column-primary::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/create-table-column-unsigned::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/create-table-comment::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/create-table-default-raw-timestamp::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/create-table-foreign-column::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/create-table-foreign-fluent-cascade::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/create-table-foreign-onupdate::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/create-table-primary-composite::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/create-table-primary-named::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/create-table-unique-column::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/create-table-unique-composite-named::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/create-table-unique-named::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/default-boolean-false::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/default-json-object::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/default-jsonb-object::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/default-null::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/default-raw-current-timestamp::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/default-string-embedded-quote::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/default-string-not-null::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',
  'schema/drop-table::mssql':
      '[ACCEPTED] MSSQL: knex.js emits UPPERCASE DDL keywords, knex-dart emits lowercase uniformly across every dialect — cosmetic only, SQL keywords are case-insensitive. Also int/integer synonym where applicable.',

  // ── ACCEPTED: same ON DELETE/ON UPDATE clause-order divergence as grouped
  // note (6) above (knex.js: ON UPDATE ... ON DELETE ...; knex-dart: on delete
  // ... on update ...), on MSSQL's inline CREATE TABLE foreign key form.
  'schema/create-table-foreign-both-actions::mssql':
      '[ACCEPTED] MSSQL casing + ON DELETE/ON UPDATE clause order — see grouped note above (6) and the MSSQL casing note above this block.',

  // ── ACCEPTED: knex.js's setNullable()/dropNullable() on MSSQL is a live-DB
  // operation, not a static compile — the base TableCompiler's
  // _setNullableState() (lib/schema/tablecompiler.js, which mssql doesn't
  // override) queries columnInfo() against a real connected database to
  // discover the column's current type before restating it in the ALTER COLUMN
  // clause (MSSQL requires the full column definition, not just
  // NULL/NOT NULL — verified by reading the knex.js source directly, not just
  // comparing output). knex-dart's SQL generation is deliberately connectionless
  // (KnexQuery.forDialect has no live DB to query) and has no way to know
  // `email` is `nvarchar(255)` from `t.setNullable("email")` alone — an
  // architectural boundary, not an oversight.
  'schema/alter-table-set-nullable::mssql':
      '[ACCEPTED] knex.js\'s mssql setNullable requires a live DB query (columnInfo) to restate the column\'s type; knex-dart is connectionless and cannot replicate this statically. See grouped note above this block.',
  'schema/alter-table-drop-nullable::mssql':
      '[ACCEPTED] see schema/alter-table-set-nullable::mssql.',

  // ── OPEN BUG: same increments()-inside-composite-primary() suppression gap
  // as the other dialects' create-table-primary-composite-with-increments
  // entries — MSSQL additionally needs the same bare (no inline PK) IDENTITY
  // column shape as Postgres here.
  'schema/create-table-primary-composite-with-increments::mssql':
      '[OPEN BUG] see schema/create-table-primary-composite-with-increments::postgres.',

  // ── OPEN BUG: same CREATE VIEW binding-inlining gap as the other dialects'
  // view-create-* entries — fix exists, verified correct, on
  // fix/mariadb-mysql-family-dispatch (commit 643f4d9), not reimplemented here.
  'schema/view-create-basic::mssql':
      '[OPEN BUG] see schema/view-create-basic::postgres.',
  'schema/view-create-or-replace::mssql':
      '[OPEN BUG] see schema/view-create-basic::postgres.',

  // ── OPEN BUG: same multi-column ALTER TABLE ADD batching gap as the other
  // dialects' alter-table-add-timestamps/column-timestamps-* entries — knex.js
  // combines every added column into one comma-joined ALTER TABLE ADD
  // statement; knex-dart emits one per column. createTableLike's extra-columns
  // step hits the same gap on MSSQL specifically (its own ALTER TABLE ADD call,
  // separate from the batching issue in the two SELECT INTO statements).
  'schema/create-table-like-with-columns::mssql':
      '[OPEN BUG] see schema/alter-table-add-timestamps::postgres — multi-column ALTER TABLE ADD batching, on createTableLike\'s extra-columns step.',
  'schema/alter-table-add-timestamps::mssql':
      '[OPEN BUG] see schema/alter-table-add-timestamps::postgres.',
  'schema/column-timestamps-basic::mssql':
      '[OPEN BUG] see schema/alter-table-add-timestamps::postgres.',
  'schema/column-timestamps-defaults::mssql':
      '[OPEN BUG] see schema/alter-table-add-timestamps::postgres.',

  // ── OPEN BUG: MSSQL won't DROP COLUMN a column that has a bound DEFAULT
  // constraint without dropping that constraint first — knex.js emits a
  // dynamic-SQL dance (DECLARE @constraint = (SELECT ... FROM
  // sys.default_constraints ...); EXEC('ALTER TABLE ... DROP CONSTRAINT ' +
  // @constraint); ALTER TABLE ... DROP COLUMN ...) to look up and drop it at
  // runtime. knex-dart emits a bare DROP COLUMN, which will fail against a real
  // SQL Server database if the column has a default (as most of these mined
  // cases do, since they were created via defaultTo() elsewhere in the corpus) —
  // a genuine runtime-risk gap, not just cosmetic. Implementing knex.js's
  // dynamic-SQL lookup is real scope (same complexity class as SQLite's
  // PRAGMA-based table rebuild, which knex-dart also doesn't implement),
  // deferred rather than attempted here.
  'schema/alter-table-drop-column::mssql':
      '[OPEN BUG] knex-dart emits a bare DROP COLUMN; knex.js emits a dynamic-SQL dance to find and drop any bound DEFAULT constraint first. See grouped note above this block — a real runtime-risk gap on SQL Server, not cosmetic.',
  'schema/alter-table-drop-columns-multiple::mssql':
      '[OPEN BUG] see schema/alter-table-drop-column::mssql.',
  'schema/alter-table-drop-timestamps::mssql':
      '[OPEN BUG] see schema/alter-table-drop-column::mssql.',

  // ── ACCEPTED: batch 6's postgres.js-mined cases, run against MSSQL for the
  // first time now that batch 7 wired it into the harness — same MSSQL
  // casing/int-integer divergence as the MSSQL casing note above, just on
  // API shapes (withSchema()-qualified drops, mixed-action foreign keys,
  // fluent column-level primary()) the mssql.js mining pass didn't happen
  // to exercise directly.
  'schema/drop-table-with-schema::mssql':
      '[ACCEPTED] see the MSSQL casing note above (schema-mining batch 7).',
  'schema/alter-table-drop-index-with-schema::mssql':
      '[ACCEPTED] see the MSSQL casing note above (schema-mining batch 7).',
  'schema/alter-table-drop-primary-named::mssql':
      '[ACCEPTED] see the MSSQL casing note above (schema-mining batch 7).',
  'schema/alter-table-primary-single-column-unnamed::mssql':
      '[ACCEPTED] see the MSSQL casing note above (schema-mining batch 7).',
  'schema/create-table-foreign-mixed-actions::mssql':
      '[ACCEPTED] MSSQL casing + int/integer synonym — see the MSSQL casing '
          'note above (schema-mining batch 7).',
  'schema/alter-table-add-column-primary-fluent::mssql':
      '[ACCEPTED] see the MSSQL casing note above (schema-mining batch 7).',
  'schema/alter-table-add-column-primary-fluent-named::mssql':
      '[ACCEPTED] see the MSSQL casing note above (schema-mining batch 7).',
  'schema/create-table-primary-fluent-named::mssql':
      '[ACCEPTED] see the MSSQL casing note above (schema-mining batch 7).',

  // ── OPEN BUG: real knex-dart defects to fix (then delete these) ────────────
};

// Previously {'mssql'} — mssql was skipped entirely because it was never
// wired into the JS-side fixture generator either (see run_js_schema.mjs's
// DIALECTS map). Both are now fixed; mssql runs like every other dialect.
const Set<String> _skipDialects = {};

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
