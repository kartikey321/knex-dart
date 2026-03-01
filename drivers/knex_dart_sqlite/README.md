# knex_dart_sqlite

SQLite driver for [knex_dart](https://pub.dev/packages/knex_dart) — execute queries against a SQLite database using the knex_dart query builder.

[![Pub Version](https://img.shields.io/pub/v/knex_dart_sqlite)](https://pub.dev/packages/knex_dart_sqlite)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

## Installation

```yaml
dependencies:
  knex_dart_sqlite: ^0.0.1
```

## Usage

```dart
import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';

// File-based database
final db = await KnexSQLite.connect(filename: 'app.db');

// In-memory database
final db = await KnexSQLite.connect(filename: ':memory:');

// Schema
await db.executeSchema(
  db.schema.createTable('users', (t) {
    t.increments('id');
    t.string('name').notNullable();
    t.string('email').unique();
    t.timestamps();
  }),
);

// INSERT
await db.insert(
  db('users').insert({'name': 'Alice', 'email': 'alice@example.com'}),
);

// SELECT
final users = await db.select(
  db('users').where('active', '=', true).orderBy('name'),
);

// UPDATE
await db.update(
  db('users').where('id', '=', 1).update({'name': 'Bob'}),
);

// DELETE
await db.delete(
  db('users').where('id', '=', 1).delete(),
);

// Transactions
await db.trx((trx) async {
  await trx.insert(trx('accounts').insert({'balance': 100}));
  await trx.update(trx('accounts').where('id', '=', 1).update({'balance': 0}));
});

await db.destroy();
```

## SQLite-specific features

- `?` positional placeholders
- Double-quoted identifier quoting
- In-memory database support (`:memory:`)
- JSON operators via `json_extract()`

## See also

- [knex_dart](https://pub.dev/packages/knex_dart) — core query builder docs and full API reference
- [knex_dart_postgres](https://pub.dev/packages/knex_dart_postgres)
- [knex_dart_mysql](https://pub.dev/packages/knex_dart_mysql)
