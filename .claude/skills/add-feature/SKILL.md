# Skill: add-feature

Add a new query-building feature to knex_dart — covering core implementation, tests, docs, and playground.

## Steps

### 1. Implement in core (`packages/knex_dart/`)

- Add the method(s) to `QueryBuilder` or `SchemaBuilder`.
- Add compilation logic in `QueryCompiler` / `SchemaCompiler` base classes.
- If the feature is dialect-specific (e.g. Postgres-only), override in the relevant driver's compiler, not the base.
- If support varies by dialect, add an entry to `knex_dart_capabilities` so lint rules can flag misuse.

### 2. Write unit tests

In `packages/knex_dart/test/`, add SQL-shape tests for the affected dialects.

Test at least:

- happy path per affected dialect
- edge cases such as empty lists or null handling
- unsupported dialect behavior when the feature is not universally available

### 3. Export if new public API

If you added new types or classes, export them from `packages/knex_dart/lib/knex_dart.dart`.

### 4. Write a docs page (or update existing)

In `docs/site/content/query-building/`:
- New concept → new `.md` file
- Extension of existing concept → update the relevant page

Structure:
```markdown
---
title: Feature Name
description: One-line description
---

# Feature Name

Brief description.

## Basic usage

```dart
// example
```

## Dialect notes

| Dialect | Support | Notes |
|---------|---------|-------|
| postgres | ✅ | |
| mysql | ✅ | |
| sqlite | ⚠️ | limited |
```

### 5. Add a playground example

In `playground/src/`:

- Add or update the example registration where the current examples live
- Keep the example runnable against the embedded engines already used by the playground

### 6. Check the docs playground link component

If the new docs page has runnable code blocks, verify [playground_link.dart](/Users/kartik/StudioProjects/knex/knex-dart/docs/site/lib/components/playground_link.dart) still generates valid playground snippets.

### 7. Verify end-to-end

```bash
melos run analyze
make test-unit
cd docs/site && dart run jaspr build
cd playground && npm run check && npm run build
```
