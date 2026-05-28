# Knex Dart Lint MVP Rules

Status: Draft locked for implementation
Last updated: 2026-03-02

## Purpose

Define stable lint rule IDs and behavior for the first release of `knex_dart_lint`.
This document is phase 0 and should be treated as the source of truth for MVP scope.

## Principles

1. Runtime validation in `knex_dart` remains authoritative.
2. Lints are optional developer-experience tooling.
3. Prefer no lint over wrong lint.
4. Emit only when dialect inference confidence is high.
5. Keep MVP narrow: high-signal, low-noise incompatibilities only.

## Severity Defaults

Default severity for all MVP rules: `warning`.

Rationale: each rule indicates likely runtime incompatibility, not style preference.
Projects may override severity in `analysis_options.yaml`.

## Confidence Policy

Every diagnostic is gated by dialect resolution confidence:

1. `high`: emit lint (default path).
2. `medium`: do not emit in MVP.
3. `unknown`: do not emit.

MVP intentionally avoids medium-confidence diagnostics to minimize false positives.

## Dialect Tokens

MVP uses these canonical dialect keys:

1. `postgres`
2. `mysql`
3. `sqlite`

## Rule Set (MVP)

### 1) `dialect_unsupported_returning`

Summary: flags `.returning(...)` when the resolved dialect does not support RETURNING in this library.

Triggers:

1. Method invocation name is `returning`.
2. Invocation target is a query chain rooted in a resolvable Knex instance.
3. Dialect confidence is `high`.
4. Capability check fails for `returning`.

Default message template:

`The .returning() method is not supported by the resolved {dialect} driver.`

Suggested help text:

`Use PostgreSQL for RETURNING support or refactor to a follow-up SELECT.`

Notes:

1. No auto code mutation quick-fix in MVP.
2. Message-only assist is allowed.

### 2) `dialect_unsupported_full_outer_join`

Summary: flags `.fullOuterJoin(...)` when unsupported for resolved dialect.

Triggers:

1. Method invocation name is `fullOuterJoin`.
2. Root dialect confidence is `high`.
3. Capability check fails for `fullOuterJoin`.

Default message template:

`FULL OUTER JOIN is not supported by the resolved {dialect} driver.`

Suggested help text:

`Consider LEFT JOIN + UNION strategy where appropriate.`

### 3) `dialect_unsupported_lateral_join`

Summary: flags lateral join methods when unsupported for resolved dialect.

Methods covered:

1. `joinLateral`
2. `leftJoinLateral`
3. `crossJoinLateral`

Triggers:

1. Method invocation name is in the method list above.
2. Root dialect confidence is `high`.
3. Capability check fails for `lateralJoin`.

Default message template:

`LATERAL JOIN is not supported by the resolved {dialect} driver.`

### 4) `dialect_unsupported_on_conflict_merge`

Summary: flags `onConflict(...).merge(...)` chain when unsupported for resolved dialect in this library.

Triggers:

1. Method invocation name is `merge`.
2. Immediate chain includes `onConflict(...)` on a query builder.
3. Root dialect confidence is `high`.
4. Capability check fails for `onConflictMerge`.

Default message template:

`onConflict().merge() is not supported by the resolved {dialect} driver.`

Suggested help text:

`Use dialect-specific upsert support available for your driver or refactor query strategy.`

## Non-Goals (MVP)

1. JSON-operator compatibility lints.
2. Full-text compatibility lints.
3. Medium-confidence diagnostics.
4. Automatic code rewrite quick-fixes.
5. Cross-file global dataflow beyond straightforward local inference.

## Rule IDs Are Stable

The following IDs are locked for MVP and should not be renamed:

1. `dialect_unsupported_returning`
2. `dialect_unsupported_full_outer_join`
3. `dialect_unsupported_lateral_join`
4. `dialect_unsupported_on_conflict_merge`

## Analyzer Integration Expectations

Users enable the plugin via `custom_lint`.

MVP rules must support:

1. standard severity overrides in `analysis_options.yaml`
2. `// ignore: <rule_id>`
3. `// ignore_for_file: <rule_id>`

## Test Acceptance Criteria

Per-rule tests must include:

1. Positive case with high-confidence dialect and unsupported method.
2. Negative case for supported dialect.
3. No diagnostic when dialect is unknown.
4. No diagnostic when dialect confidence is medium.

Dialect resolver tests must include:

1. `KnexPostgres.connect(...)` high-confidence mapping.
2. `KnexMySQL.connect(...)` high-confidence mapping.
3. `KnexSQLite.connect(...)` high-confidence mapping.
4. unresolved factory/param path yielding unknown.

## Next Implementation Step

After this document:

1. Create `packages/knex_dart_capabilities` (zero dependencies).
2. Add enum + dialect capability matrix there.
3. Build lint scaffold package and implement inference + these four rules.
