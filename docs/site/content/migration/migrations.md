---
title: Migrations
description: "Choose one migration source style explicitly: code, SQL directory, or external schema"
---

# Migrations

Knex Dart supports multiple migration source styles. Use one explicit entrypoint so intent is clear in code and docs.

## Source Matrix

| Source | Entrypoint | Best for |
|---|---|---|
| Code-first units | `db.migrate.fromCode([...])` | App-defined migration classes/objects in Dart |
| SQL files on disk | `db.migrate.fromSqlDir('./migrations')` | SQL-first teams and DBA-reviewed SQL |
| External schema input | `db.migrate.fromSchema(...)` | Converting JSON/OpenAPI/custom schema formats into Knex schema AST |

All three return a `Migrator` and share the same lifecycle:

```dart
await migrator.latest();
await migrator.rollback();
final status = await migrator.status();
```

## 1) Code-First (`fromCode`)

```dart
final migrator = db.migrate.fromCode([
  const SqlMigration(
    name: '001_create_users',
    upSql: ['create table users (id integer primary key, email varchar(255))'],
    downSql: ['drop table users'],
  ),
]);

await migrator.latest();
```

## 2) SQL Directory (`fromSqlDir`)

Directory convention:

- `name.up.sql` (required)
- `name.down.sql` (optional)

Example:

```dart
final migrator = db.migrate.fromSqlDir('./migrations');
await migrator.latest();
```

Notes:

- Migration id is derived from filename prefix (`001_init.up.sql` -> `001_init`).
- Files are loaded in lexicographic order.
- Missing `.down.sql` means rollback for that migration will fail with a clear error.

## 3) External Schema (`fromSchema`)

Convert external schema input to `KnexSchemaAst` via an adapter, then run as a migration unit.

```dart
final migrator = db.migrate.fromSchema(
  name: '001_bootstrap_schema',
  input: jsonSchemaMap,
  adapter: JsonSchemaAdapter(),
  ifNotExists: true,
);

await migrator.latest();
```

Use `dropOnDown: true` if you want generated rollback to `drop table if exists ...` for all projected tables.

## Duplicate Name Rules

Migration names must be unique across all configured units and sources. Duplicate names throw a `KnexMigrationException` before execution.

## Next Steps

- [Schema Builder](/query-building/schema-builder)
- [Transactions](/query-building/transactions)
- [From Knex.js](/migration/from-knex-js)
