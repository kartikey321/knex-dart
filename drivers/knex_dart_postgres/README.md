# knex_dart_postgres

PostgreSQL driver for [knex_dart](https://pub.dev/packages/knex_dart) — execute queries against a PostgreSQL database using the knex_dart query builder.

[![Pub Version](https://img.shields.io/pub/v/knex_dart_postgres)](https://pub.dev/packages/knex_dart_postgres)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

## Installation

```yaml
dependencies:
  knex_dart_postgres: ^0.1.0
```

## Usage

```dart
import 'package:knex_dart_postgres/knex_dart_postgres.dart';

final db = await KnexPostgres.connect(
  host: 'localhost',
  port: 5432,
  database: 'mydb',
  username: 'user',
  password: 'pass',
);

// SELECT
final users = await db.select(
  db('users').where('active', '=', true).orderBy('name').limit(10),
);

// INSERT
await db.insert(
  db('users').insert({'name': 'Alice', 'email': 'alice@example.com'}),
);

// UPDATE
await db.update(
  db('users').where('id', '=', 1).update({'name': 'Bob'}),
);

// DELETE
await db.delete(
  db('users').where('id', '=', 1).delete(),
);

// Schema
await db.executeSchema(
  db.schema.createTable('posts', (t) {
    t.increments('id');
    t.string('title').notNullable();
    t.integer('user_id').references('id').inTable('users');
    t.timestamps();
  }),
);

// Transactions
await db.trx((trx) async {
  await trx.insert(trx('accounts').insert({'balance': 100}));
  await trx.update(trx('accounts').where('id', '=', 1).update({'balance': 0}));
});

await db.destroy();
```

## PostgreSQL-specific features

- Named parameter placeholders (`$1, $2, ...`)
- `RETURNING` clause support
- JSON operators (`whereJsonPath`, `whereJsonSupersetOf`, `whereJsonSubsetOf`)
- Full-text search (`whereFullText` with language option)
- Connection pooling support
- Nested transactions via savepoints

## Documentation

- Docs home: https://docs.knex.mahawarkartikey.in/
- Transactions: https://docs.knex.mahawarkartikey.in/query-building/transactions
- Migrations: https://docs.knex.mahawarkartikey.in/migration/migrations
- Schema Builder: https://docs.knex.mahawarkartikey.in/query-building/schema-builder

## See also

- [knex_dart](https://pub.dev/packages/knex_dart) — core package
- [knex_dart_mysql](https://pub.dev/packages/knex_dart_mysql)
- [knex_dart_sqlite](https://pub.dev/packages/knex_dart_sqlite)
