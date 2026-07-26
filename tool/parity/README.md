# Differential parity harness (knex-dart ⇄ knex.js)

knex-dart is a port of knex.js. Hand-written assertions only catch what someone
thought to check — and the port had a whole class of bugs nobody checked for
(the `$N` placeholder renumbering corruption, dropped WHERE guards, dropped
CTEs). This harness closes that gap: it builds the **same** query on both sides
and asserts the compiled SQL + bindings match, across every dialect, for a
corpus that grows over time.

## How it works

Cases are **dialect-agnostic**: each is written once as a builder function, then
the harness multiplies it across a **dialect matrix**. Add one case → coverage
for every dialect. Add one dialect → every existing case re-tested.

There are two parallel harnesses — query builder and schema DDL — because a
schema `.toSQL()` call returns a **list** of statements on both sides (e.g.
`createTable` can emit a CREATE TABLE plus deferred ALTER TABLE statements),
not the single `SqlString` a query builder call returns. Same design
(dialect-agnostic corpus × dialect matrix × ratcheting allowlist), different
fixture shape and comparator:

```
tool/parity/run_js.mjs                         # JS reference generator — QUERY builder
tool/parity/run_js_schema.mjs                  # JS reference generator — SCHEMA DDL
packages/knex_dart/test/parity/
  parity_cases.dart                            # query corpus (Dart side)
  parity_test.dart                             # query loader + normalizer + comparator + allowlist
  schema_parity_cases.dart                     # schema DDL corpus (Dart side)
  schema_parity_test.dart                      # schema DDL loader + normalizer + comparator + allowlist
  fixtures/parity_cases.json                   # COMMITTED knex.js query output (regenerated, not hand-edited)
  fixtures/schema_parity_cases.json            # COMMITTED knex.js schema DDL output (regenerated, not hand-edited)
```

The schema DDL harness exists because a `dart_mutant` mutation-testing pass on
`schema_compiler.dart` found its largest untested cluster by far was dialect
dispatch in schema DDL (sqlite/mysql/mssql branching for
primary/unique/foreign-key/index handling, ~215 surviving mutants) — the query
corpus never touched schema DDL at all. Building this harness immediately
surfaced two real bugs the mutation run had only pointed at abstractly:
foreign keys declared inside `createTable` were silently dropped on SQLite
(same bug family as the earlier `primary()` fix), and turso/d1 fell through to
Postgres-shaped SQL everywhere because most sqlite-dispatch checks tested
`driverName == 'sqlite' || 'sqlite3'` literally instead of the family-aware
`_isSqliteLike()` helper that already existed in the file.

The Dart tests read the **committed** fixtures — they never shell out to the
external knex.js checkout, so they run anywhere with no Node dependency.

## Dialect tiers

knex.js implements only 6 of knex-dart's dialects, so parity is tiered:

| Tier | Dialects | Reference | Comparison |
|------|----------|-----------|------------|
| **Direct** | postgres, cockroachdb, redshift, mysql | knex.js same client | strict (identical placeholders + quoting) |
| **Family** | sqlite, turso, d1 | knex.js `sqlite3` | strict + documented backtick→`"` quote-normalize |
| **Golden** | duckdb, bigquery, snowflake | none (knex.js has no client) | Dart-only reviewed snapshots *(TODO)* |
| **Driver** | mssql | knex.js `mssql` | deferred to the `knex_dart_mssql` package *(TODO)* |

Only **placeholder syntax** is normalized (per the tier). Everything else — a
casing difference, a missing clause, a wrong operator — is a real signal, so it
is either fixed or recorded in the allowlist with a reason. Nothing semantic is
normalized away.

## The allowlist is the triage ledger

`parityAllowlist` (query) / `schemaParityAllowlist` (schema DDL) holds every
accepted divergence, keyed `id::dialect`, each with a written reason and one
of three tags:

- **`[ACCEPTED]`** — knex-dart is right (often *more* correct than knex.js, which
  silently drops unsupported constructs — e.g. it emits a plain INSERT for
  `onConflict().merge()` on Redshift; knex-dart refuses). Also covers
  genuinely cosmetic differences verified to be semantically identical (e.g.
  MySQL `ADD COLUMN` vs `ADD` — both documented as equivalent grammar).
- **`[OPEN BUG]`** — a real knex-dart defect the harness caught. Fix it, then
  delete the entry (you have no choice — see the ratchet below).
- **`[UNVERIFIED]`** — a plausible divergence that needs a live database to
  triage confidently. Don't guess an `[ACCEPTED]`/`[OPEN BUG]` verdict you
  can't actually verify — leave it `[UNVERIFIED]` with what would resolve it.
  A CockroachDB-specific DROP INDEX vs DROP CONSTRAINT question started
  `[UNVERIFIED]` for exactly this reason, then got resolved to `[ACCEPTED]`
  once a `docker run cockroachdb/cockroach:latest start-single-node
  --insecure` container was available to check both statements against —
  that's the intended lifecycle: verify for real when you can, don't leave
  it guessed.

## Live-execution verification beyond SQL-text comparison

Text matching (this harness) proves knex-dart matches knex.js's *output*. It
can't prove either side's output actually executes — a mutated column type,
a subtly wrong constraint clause, or a syntax choice that merely *parses* but
doesn't create the constraint it claims to would all pass a text-only check.
Where a real database is available (Docker, or an ad-hoc single-node
container for a dialect not in docker-compose), driver integration tests
under `drivers/*/test/integration/` run the exact generated SQL against a
live engine and assert on *behavior*, not just success:

- `drivers/knex_dart_turso/test/integration/turso_schema_ddl_test.dart` —
  confirms the SQLite-family inline-FK-fold fix produces FKs that are
  actually *enforced* (orphan inserts rejected, `ON DELETE CASCADE` actually
  cascades), not just syntax that parses.
- `drivers/knex_dart_mysql/test/integration/mysql_schema_ddl_cosmetic_test.dart` —
  confirms every MySQL "cosmetic syntax alternative" allowlist claim
  (`ADD`/`ADD COLUMN`, unique/index/primary-key alternate forms) actually
  enforces the constraint it claims to.

When you resolve an `[UNVERIFIED]` entry or fix an `[OPEN BUG]` that touches
a dialect with no docker-compose service, prefer a throwaway `docker run`
against the dialect's official image over guessing from documentation alone
— see the CockroachDB example above.

### D1 (Cloudflare) — no docker, no automated test file, but live-verified anyway

`knex_dart_d1`'s driver only talks to Cloudflare's real REST API (account ID
+ database ID + API token) — it has no local-binding execution path, so it
can't be dockerized or wired into a permanent `dart test` file the way
turso/mysql/postgres can without first building a Workers HTTP shim (out of
scope for a verification pass).

D1's schema-compiler code path is nonetheless byte-identical to turso's
(`_isSqliteLike()`, zero D1-specific branches anywhere in
`schema_compiler.dart`/`table_builder.dart`), so the turso live verification
above is strong evidence by itself. It was additionally checked directly:
`wrangler d1 execute <db> --local` runs against a real local SQLite file
(`.wrangler/state/v3/d1/<id>.sqlite`) — no Cloudflare login or account
required for `--local` mode (confirmed: `wrangler whoami` reported "Not
logged in" throughout). Per Cloudflare's own D1 docs, the only documented
local-vs-production difference is performance/distributed-storage behavior,
not SQL/DDL semantics — exactly what this needed to be a faithful check.
Ran knex-dart's exact `d1`-dialect generated SQL (inline-folded FK, inline
composite PK, dropUnique) through `wrangler d1 execute --local`: FK rejected
an orphan insert (`FOREIGN KEY constraint failed: SQLITE_CONSTRAINT`),
composite PK rejected a duplicate (`UNIQUE constraint failed`), and
dropUnique's `drop index` genuinely removed the constraint (duplicate insert
succeeded afterward). All confirmed correct on real local D1, not just
inferred from turso.

**The allowlist ratchets.** A listed entry is *not* skipped: the test runs in
reverse and asserts the divergence is **still present**. The moment a bug is
fixed (or an `[ACCEPTED]` behavior drifts), that test fails with "divergence no
longer present — re-triage and remove", forcing the entry out in the same
change. So a green suite means "every diff is fixed **or** still-diverging
exactly as documented" — never "silently ok". The goal is not zero diffs but
zero *undocumented* diffs.

Binding comparison is by value for numbers (int-vs-double width is not
distinguished — JSON collapses it anyway) and strict otherwise (`"1"` ≠ `1`).

## Extending the corpus (the whole point — do this often)

**Query builder:**
1. Add a case to `run_js.mjs` `cases`: `['category/name', (k) => k('t')...]`.
2. Add the mirror to `parity_cases.dart` under the **same id**, ending in `.toSQL()`.
3. Regenerate: `node tool/parity/run_js.mjs`
4. Run: `cd packages/knex_dart && dart test test/parity/parity_test.dart`
5. Triage every new failure: fix the bug, or add an allowlist entry with a reason.

**Schema DDL:**
1. Add a case to `run_js_schema.mjs` `cases`: `['schema/category-name', (k) => k.schema.createTable(...)]`.
2. Add the mirror to `schema_parity_cases.dart` under the **same id**, ending in `.toSQL()`.
3. Regenerate: `node tool/parity/run_js_schema.mjs`
4. Run: `cd packages/knex_dart && dart test test/parity/schema_parity_test.dart`
5. Triage every new failure: fix the bug, or add an allowlist entry with a reason.

Prioritise the bug-dense shapes. Query builder: nested subqueries, EXISTS,
UNION/INTERSECT, CTEs, window functions, and DML with RETURNING/onConflict.
Schema DDL: dialect-dispatch branches (anything that checks `driverName`) —
check every one uses the family-aware helpers (`_isSqliteLike`,
`_isPostgresLike`, `_isMySqlLike`) rather than a hand-rolled comparison, since
that's exactly the bug class the turso/d1 gap above was.

## Regenerating on a knex.js upgrade

Bump the knex.js checkout, rerun `node tool/parity/run_js.mjs` **and**
`node tool/parity/run_js_schema.mjs`, and review both fixture diffs.
`knexVersion` is recorded in each fixture header so a regeneration that shifts
expected output is visible in review.
