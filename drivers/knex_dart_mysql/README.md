# knex_dart_mysql

MySQL driver for [knex_dart](https://pub.dev/packages/knex_dart) — execute queries against a MySQL database using the knex_dart query builder.

[![Pub Version](https://img.shields.io/pub/v/knex_dart_mysql)](https://pub.dev/packages/knex_dart_mysql)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

## Installation

```yaml
dependencies:
  knex_dart_mysql: ^0.0.1
```

## Usage

```dart
import 'package:knex_dart_mysql/knex_dart_mysql.dart';

final db = await KnexMySQL.connect(
  host: 'localhost',
  port: 3306,
  database: 'mydb',
  user: 'user',
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

## MySQL-specific features

- `?` positional placeholders
- Backtick identifier quoting
- Full-text search (`whereFullText` with IN BOOLEAN MODE / IN NATURAL LANGUAGE MODE)

## See also

- [knex_dart](https://pub.dev/packages/knex_dart) — core query builder docs and full API reference
- [knex_dart_postgres](https://pub.dev/packages/knex_dart_postgres)
- [knex_dart_sqlite](https://pub.dev/packages/knex_dart_sqlite)
