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

```
tool/parity/run_js.mjs                         # JS reference generator
packages/knex_dart/test/parity/
  parity_cases.dart                            # the corpus (Dart side)
  parity_test.dart                             # loader + normalizer + comparator + allowlist
  fixtures/parity_cases.json                   # COMMITTED knex.js output (regenerated, not hand-edited)
```

The Dart test reads the **committed** fixture — it never shells out to the
external knex.js checkout, so it runs anywhere with no Node dependency.

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

`parityAllowlist` in `parity_test.dart` holds every accepted divergence, keyed
`id::dialect`, each with a written reason and one of two tags:

- **`[ACCEPTED]`** — knex-dart is right (often *more* correct than knex.js, which
  silently drops unsupported constructs — e.g. it emits a plain INSERT for
  `onConflict().merge()` on Redshift; knex-dart refuses).
- **`[OPEN BUG]`** — a real knex-dart defect the harness caught. Fix it, then
  delete the entry (you have no choice — see the ratchet below).

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

1. Add a case to `run_js.mjs` `cases`: `['category/name', (k) => k('t')...]`.
2. Add the mirror to `parity_cases.dart` under the **same id**, ending in `.toSQL()`.
3. Regenerate the fixture:
   ```
   node tool/parity/run_js.mjs
   ```
4. Run the harness:
   ```
   cd packages/knex_dart && dart test test/parity/parity_test.dart
   ```
5. Triage every new failure: fix the bug, or add an allowlist entry with a reason.

Prioritise the bug-dense shapes: nested subqueries, EXISTS, UNION/INTERSECT,
CTEs, window functions, and DML with RETURNING/onConflict — these are where the
port diverged most.

## Regenerating on a knex.js upgrade

Bump the knex.js checkout, rerun `node tool/parity/run_js.mjs`, and review the
fixture diff. `knexVersion` is recorded in the fixture header so a regeneration
that shifts expected output is visible in review.
