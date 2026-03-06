# knex_dart

A faithful port of [Knex.js](https://knexjs.org/) to Dart — a powerful, fluent SQL query builder for Dart backends.

[![Pub Version](https://img.shields.io/pub/v/knex_dart)](https://pub.dev/packages/knex_dart)
[![codecov](https://codecov.io/gh/kartikey321/knex-dart/branch/main/graph/badge.svg)](https://codecov.io/gh/kartikey321/knex-dart)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

## Packages

| Package | Description | Version |
|---|---|---|
| [knex_dart](https://pub.dev/packages/knex_dart) | Core query builder (this package) | [![pub](https://img.shields.io/pub/v/knex_dart)](https://pub.dev/packages/knex_dart) |
| [knex_dart_postgres](https://pub.dev/packages/knex_dart_postgres) | PostgreSQL driver | [![pub](https://img.shields.io/pub/v/knex_dart_postgres)](https://pub.dev/packages/knex_dart_postgres) |
| [knex_dart_mysql](https://pub.dev/packages/knex_dart_mysql) | MySQL driver | [![pub](https://img.shields.io/pub/v/knex_dart_mysql)](https://pub.dev/packages/knex_dart_mysql) |
| [knex_dart_sqlite](https://pub.dev/packages/knex_dart_sqlite) | SQLite driver | [![pub](https://img.shields.io/pub/v/knex_dart_sqlite)](https://pub.dev/packages/knex_dart_sqlite) |
| [knex_dart_capabilities](https://pub.dev/packages/knex_dart_capabilities) | Shared dialect capability matrix | [![pub](https://img.shields.io/pub/v/knex_dart_capabilities)](https://pub.dev/packages/knex_dart_capabilities) |
| [knex_dart_lint](https://pub.dev/packages/knex_dart_lint) | Optional static dialect lint plugin | [![pub](https://img.shields.io/pub/v/knex_dart_lint)](https://pub.dev/packages/knex_dart_lint) |

`knex_dart` is the core package — it contains the query builder, schema builder, and compiler logic but no database connectivity. Pick the driver package for your database.

## Documentation

Full documentation is available at:

- https://docs.knex.mahawarkartikey.in/
- Migrations: https://docs.knex.mahawarkartikey.in/migration/migrations
- Dialect Lint (optional): https://docs.knex.mahawarkartikey.in/tooling/dialect-lint
- Transactions: https://docs.knex.mahawarkartikey.in/query-building/transactions
- Schema Builder: https://docs.knex.mahawarkartikey.in/query-building/schema-builder

## Installation

```yaml
dependencies:
  knex_dart_postgres: ^0.1.1  # or mysql / sqlite
```

The driver package pulls in `knex_dart` automatically.

## Quick Start

### PostgreSQL

```dart
import 'package:knex_dart_postgres/knex_dart_postgres.dart';

final db = await KnexPostgres.connect(
  host: 'localhost',
  database: 'mydb',
  username: 'user',
  password: 'pass',
);

final users = await db.select(
  db('users').where('active', '=', true).limit(10),
);

await db.destroy();
```

### SQLite

```dart
import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';

final db = await KnexSQLite.connect(filename: ':memory:');

await db.executeSchema(
  db.schema.createTable('users', (t) {
    t.increments('id');
    t.string('name');
  }),
);

await db.insert(db('users').insert({'name': 'Alice'}));
```

### MySQL

```dart
import 'package:knex_dart_mysql/knex_dart_mysql.dart';

final db = await KnexMySQL.connect(
  host: 'localhost',
  database: 'mydb',
  user: 'user',
  password: 'pass',
);
```

## Query Builder

All driver packages expose the same `Knex` query builder API.

### SELECT

```dart
// Basic
db('users').select(['id', 'name']).where('active', '=', true);

// Joins
db('users')
  .join('orders', 'users.id', '=', 'orders.user_id')
  .select(['users.name', 'orders.total'])
  .where('orders.status', '=', 'completed');

// Aggregates
db('sales')
  .count('* as total')
  .sum('amount as revenue')
  .where('status', '=', 'completed');
```

### INSERT / UPDATE / DELETE

```dart
db('users').insert({'name': 'Alice', 'email': 'alice@example.com'});

db('users').where('id', '=', 1).update({'name': 'Bob'});

db('users').where('id', '=', 1).delete();
```

### Advanced

```dart
// CTEs
db('active_users')
  .withRecursive('active_users', db('users').where('active', '=', true))
  .select(['*']);

// Upsert
db('users')
  .insert({'email': 'alice@example.com', 'name': 'Alice'})
  .onConflict('email')
  .merge();

// Raw
db.raw('select * from users where id = ?', [1]);
```

### Schema Builder

```dart
await db.executeSchema(
  db.schema.createTable('posts', (t) {
    t.increments('id');
    t.string('title').notNullable();
    t.text('body');
    t.integer('user_id').references('id').inTable('users');
    t.timestamps();
  }),
);
```

### Transactions

```dart
await db.trx((trx) async {
  await trx.insert(trx('accounts').insert({'balance': 100}));
  await trx.update(trx('accounts').where('id', '=', 1).update({'balance': 0}));
});
```

Nested transactions are supported via savepoints (`SAVEPOINT`, `ROLLBACK TO SAVEPOINT`, `RELEASE SAVEPOINT`).

### Migrations

Knex Dart supports explicit migration source styles:

- `fromCode(...)` for in-code migration units
- `fromSqlDir(...)` for filesystem `*.up.sql` / `*.down.sql` migrations
- `fromConfig()` to read `MigrationConfig.directory` (default `./migrations`)
- `fromSchema(...)` for external schema input mapped to `KnexSchemaAst`

```dart
// 1) Code-first (SQL migration unit)
await db.migrate.fromCode([
  const SqlMigration(
    name: '001_create_users',
    upSql: ['create table users (id integer primary key, email varchar(255))'],
    downSql: ['drop table users'],
  ),
]).latest();

// 2) SQL directory
await db.migrate.fromSqlDir('./migrations').latest();

// 3) From config.migrations.directory
await db.migrate.fromConfig().latest();
```

Schema builder style is also supported by implementing a migration unit:

```dart
class CreateUsersMigration implements MigrationUnit {
  @override
  String get name => '002_create_users_with_builder';

  @override
  Future<void> up(Knex db) async {
    final schema = db.schema;
    schema.createTable('users', (t) {
      t.increments('id');
      t.string('email', 255).notNullable().unique();
    });
    await schema.execute();
  }

  @override
  Future<void> down(Knex db) async {
    final schema = db.schema;
    schema.dropTableIfExists('users');
    await schema.execute();
  }
}
```

### Optional Dialect Lint Plugin

`knex_dart_lint` is optional and provides static diagnostics for dialect-incompatible query APIs.

Example warnings:
- `.returning()` on MySQL/SQLite
- `fullOuterJoin()` on SQLite/MySQL
- `joinLateral()` on SQLite

Setup:

```yaml
dev_dependencies:
  custom_lint: ^0.8.1
  knex_dart_lint: ^0.1.0
```

```yaml
# analysis_options.yaml
analyzer:
  plugins:
    - custom_lint
```

## Side-by-Side: Knex.js vs knex_dart

**Knex.js**
```javascript
knex('users')
  .select('name', 'email')
  .where('age', '>', 18)
  .orderBy('created_at', 'desc')
  .limit(10);
```

**knex_dart**
```dart
db('users')
  .select(['name', 'email'])
  .where('age', '>', 18)
  .orderBy('created_at', 'desc')
  .limit(10);
```

## Features

- SELECT, INSERT, UPDATE, DELETE
- WHERE — basic, IN, NULL, BETWEEN, EXISTS, OR, raw
- JOINs — INNER, LEFT, RIGHT, FULL OUTER, CROSS, with callback builder
- Aggregates — COUNT, SUM, AVG, MIN, MAX with DISTINCT variants
- ORDER BY, GROUP BY, HAVING, LIMIT, OFFSET
- Raw queries with `?`, `:name`, `??` binding formats
- RETURNING clause (PostgreSQL)
- CTEs (WITH / WITH RECURSIVE)
- UNIONs, INTERSECTs, EXCEPTs
- Subqueries
- JSON operators (`whereJsonPath`, `whereJsonSupersetOf`, etc.)
- Full-text search (`whereFullText`)
- Upserts (`onConflict().merge()`)
- Schema builder — createTable, alterTable, dropTable, foreign keys, indexes
- Migrations — code-first, SQL-directory, and external-schema sources
- Dialect-aware SQL (PostgreSQL `$1`, MySQL/SQLite `?`)

## Acknowledgments

This project is a port of [Knex.js](https://knexjs.org/), created by Tim Griesser and contributors.

## License

MIT — see [LICENSE](LICENSE).
