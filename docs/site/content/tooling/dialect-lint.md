---
title: Dialect Lint (Optional)
description: Optional custom_lint plugin for dialect-aware API diagnostics
---

# Dialect Lint (Optional)

`knex_dart_lint` is an optional `custom_lint` plugin that reports dialect-incompatible query API usage at analysis time — before you run your code.

## What It Catches

Dialect capability rules:

| Rule | What it flags |
|---|---|
| `dialect_unsupported_returning` | `.returning()` on MySQL or SQLite (not supported) |
| `dialect_unsupported_full_outer_join` | `.fullOuterJoin()` on MySQL or SQLite |
| `dialect_unsupported_lateral_join` | `.joinLateral()` / `.leftJoinLateral()` / `.crossJoinLateral()` on SQLite |
| `dialect_unsupported_on_conflict_merge` | `.onConflict().merge()` on PostgreSQL (not supported) |
| `dialect_unsupported_cte` | CTE APIs on dialects without supported CTE behavior |
| `dialect_unsupported_window_functions` | Window-function builder APIs on unsupported dialects |
| `dialect_unsupported_json` | JSON query helpers on unsupported dialects |
| `dialect_unsupported_intersect_except` | `INTERSECT` / `EXCEPT` query APIs on unsupported dialects |

Query argument correctness rules:

| Rule | What it flags |
|---|---|
| `invalid_where_operator` | Invalid SQL operators passed to `.where(...)` |
| `where_null_value` | `.where(...)` comparisons using `null` instead of null-aware APIs |
| `invalid_order_direction` | Invalid direction values in `.orderBy(...)` |
| `limit_non_int_argument` | Non-integer values passed to `.limit(...)` |
| `insert_wrong_value_type` | Invalid value type passed to `.insert(...)` |
| `where_null_typed_value` | Null typed-values in `.where(...)` that should use null-aware methods |

Rules only fire when dialect inference is **high-confidence** — i.e., the driver type is statically resolvable from a top-level variable declaration. When the dialect cannot be determined, no diagnostic is emitted (no false positives).

Current scope: `knex_dart_lint` targets query builder usage; schema builder APIs are not linted yet.

## Install

```bash
dart pub add --dev custom_lint
dart pub add --dev knex_dart_lint
```

Enable the plugin in `analysis_options.yaml`:

```yaml
analyzer:
  plugins:
    - custom_lint
```

## Example

```dart
final db = await KnexMySQL.connect(
  host: 'localhost',
  database: 'demo',
  user: 'root',
  password: 'root',
);

// ⚠️ dialect_unsupported_returning — MySQL does not support RETURNING
db.queryBuilder().table('users').insert({'name': 'Alice'}).returning(['id']);

// ⚠️ dialect_unsupported_full_outer_join — MySQL does not support FULL OUTER JOIN
db.queryBuilder().table('users').fullOuterJoin('orders', 'users.id', 'orders.user_id');
```

## CLI Check

Run lints in CI or locally:

```bash
dart run custom_lint
```

## IDE Notes

- **CLI**: Works in any project with a `package_config.json` (run `dart pub get` first).
- **IDE**: Requires the IDE's Dart process to resolve `dart` from its `PATH`. If custom lints appear in CLI but not in the IDE, check the IDE's environment configuration.
- **Standalone packages**: `dart run custom_lint` works from the package directory. Monorepo workspace members may need to be run from the member's own directory rather than the workspace root.

## Runtime Guards

In addition to the static lint plugin, `knex_dart` itself throws a `StateError` at query-compile time (when `.toSQL()` is called) for unsupported dialect combinations. This provides a second layer of protection at runtime even without the lint plugin installed.
