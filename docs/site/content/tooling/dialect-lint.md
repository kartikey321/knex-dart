---
title: Dialect Lint (Optional)
description: Optional custom_lint plugin for dialect-aware API diagnostics
---

# Dialect Lint (Optional)

`knex_dart_lint` is an optional `custom_lint` plugin that reports dialect-incompatible query API usage at analysis time.

## What It Catches

Dialect capability rules:
- `.returning()` on MySQL and SQLite
- `fullOuterJoin(...)` on dialects without support
- `joinLateral(...)` on dialects without support
- `onConflict(...).merge()` on dialects without support
- `withQuery(...)` / `withRecursive(...)` where CTE support is unavailable
- window-function methods where unsupported
- JSON methods where unsupported
- `intersect(...)` / `except(...)` where unsupported

Query-argument correctness rules:
- invalid operators like `where('age', '==', 18)`
- `where('col', null)` patterns that should be `whereNull('col')`
- invalid order direction strings (must be `asc`/`desc`)
- wrong static types for `limit/offset` and `insert(...)`

## Install

```yaml
dev_dependencies:
  custom_lint: ^0.8.1
  knex_dart_lint: ^0.1.0
```

Enable the plugin:

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

// Reported by dialect lint
db.queryBuilder().table('users').insert({'name': 'A'}).returning(['id']);
```

## Confidence policy

Dialect compatibility rules only emit when dialect inference is high-confidence.
When the dialect cannot be resolved safely, no compatibility diagnostic is emitted.

## CLI Check

Run lints in CI/local:

```bash
dart run custom_lint
```

## IDE Notes

If custom lints appear in CLI but not IDE, verify the IDE process can resolve `dart` from its environment `PATH`.
