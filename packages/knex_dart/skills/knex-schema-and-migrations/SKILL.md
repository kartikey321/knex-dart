---
name: knex-schema-and-migrations
description: Use when defining database migrations with knex_dart's Migrator — code-first, SQL-directory, or schema-input styles.
metadata:
  knex_dart_version: 1.2.0
---

Migrations run through the `Migrator` class accessed via `knex.migrate`. The `Knex` facade (not the driver wrappers like `KnexPostgres`) is the entry point.

## Getting a Knex Facade

Driver wrappers (`KnexPostgres`, `KnexSQLite`, etc.) expose the low-level `Client` subclass publicly. Wrap it in `Knex` to access migrations.

```dart
import 'package:knex_dart/knex_dart.dart';
import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';

final client = await SQLiteClient.connect(filename: 'app.db');
final db = Knex(client);

// Now db.migrate is available
```

```dart
import 'package:knex_dart/knex_dart.dart';
import 'package:knex_dart_postgres/knex_dart_postgres.dart';

final client = await PostgresClient.connect(
  host: 'localhost', port: 5432,
  database: 'myapp', username: 'user', password: 'pass',
);
final db = Knex(client);
```

## Migration Lifecycle

All three source styles share the same three lifecycle methods:

```dart
await migrator.latest();               // run all pending migrations
await migrator.rollback();             // revert the latest batch
final status = await migrator.status(); // [{name, status: 'completed'|'pending'}]
```

## Style 1 — Code-First

Use `SqlMigration` for plain SQL up/down pairs. Name migrations with a sortable prefix (e.g. `001_`, `002_`).

```dart
final migrator = db.migrate.fromCode([
  const SqlMigration(
    name: '001_create_users',
    upSql: [
      'CREATE TABLE users (id SERIAL PRIMARY KEY, email VARCHAR(255) UNIQUE NOT NULL)',
    ],
    downSql: ['DROP TABLE users'],
  ),
  const SqlMigration(
    name: '002_add_active_column',
    upSql: ['ALTER TABLE users ADD COLUMN active BOOLEAN NOT NULL DEFAULT true'],
    downSql: ['ALTER TABLE users DROP COLUMN active'],
  ),
]);

await migrator.latest();
```

## Style 2 — SQL Directory

Files must follow the naming convention `<name>.up.sql` / `<name>.down.sql`. Units run in lexicographic order.

```
migrations/
  001_create_users.up.sql
  001_create_users.down.sql
  002_add_index.up.sql
```

```dart
final migrator = db.migrate.fromSqlDir('./migrations');
await migrator.latest();
```

Use `fromConfig()` to read the directory from `MigrationConfig.directory` (default `./migrations`).

```dart
await db.migrate.fromConfig().latest();
```

## Style 3 — External Schema Input

Converts a JSON Schema (or any registered adapter) into `CREATE TABLE` DDL and runs it as a migration.

```dart
final migrator = db.migrate.fromSchema(
  name: '001_bootstrap',
  input: {
    'type': 'object',
    'title': 'users',
    'properties': {
      'id':    {'type': 'integer'},
      'email': {'type': 'string'},
    },
  },
  ifNotExists: true,
  dropOnDown: true,
);

await migrator.latest();
```

`JsonSchemaAdapter` is auto-registered when no `adapter` or `registry` is passed.

## Migration State Table

The migrator creates a `knex_migrations` table in the target database to track applied migrations. Override via `MigrationConfig`:

```dart
final client = await SQLiteClient.connect(filename: 'app.db');
final db = Knex(
  client,
  // Knex accepts a KnexConfig — configure via client.config before wrapping
);
```

Default table name is `knex_migrations`. Default directory is `./migrations`.

## Transaction Wrapping

`disableTransactions` defaults to `true`. Set it to `false` only for single-connection drivers (like SQLite) where transactional correctness is guaranteed.

```dart
// SQLite: safe to enable transactions
final client = await SQLiteClient.connect(filename: 'app.db');
// Supply MigrationConfig via KnexConfig at client creation time
```

## Rules

- Migration names must be unique — duplicate names throw `KnexMigrationException` before any SQL runs.
- Missing `.down.sql` means `rollback()` will throw for that migration.
- `SchemaAstMigration` requires `dropOnDown: true` for automatic rollback, otherwise rollback throws.

## Docs

- Migrations: `https://docs.knex.mahawarkartikey.in/raw/migration/migrations.md`
- Schema builder: `https://docs.knex.mahawarkartikey.in/raw/query-building/schema-builder.md`
- From Knex.js: `https://docs.knex.mahawarkartikey.in/raw/migration/from-knex-js.md`
