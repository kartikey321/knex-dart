# knex_dart_d1

Cloudflare D1 driver for [knex_dart](https://pub.dev/packages/knex_dart) via the Cloudflare D1 REST API.

[![Pub Version](https://img.shields.io/pub/v/knex_dart_d1)](https://pub.dev/packages/knex_dart_d1)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

## Installation

```yaml
dependencies:
  knex_dart_d1: ^0.1.0
```

## Quick Start

```dart
import 'package:knex_dart_d1/knex_dart_d1.dart';

final db = KnexD1(
  accountId: 'cloudflare-account-id',
  databaseId: 'd1-database-id',
  apiToken: 'cloudflare-api-token',
);

final rows = await db.select(
  db.queryBuilder().table('users').where('active', '=', 1).limit(20),
);

await db.batch((b) {
  b.add(db.queryBuilder().table('audit').insert({'action': 'read_users'}));
  b.addRaw('insert into metrics(name, value) values(?, ?)', ['reads', 1]);
});

db.close();
```

## Platform Requirements

- Works on Dart VM and web runtimes (HTTP-based driver).
- Requires Cloudflare account ID, D1 database ID, and API token.

## Dialect Capabilities

Based on `knex_dart_capabilities` (`d1` dialect):

| Capability | Support |
|---|---|
| `returning` | No |
| `fullOuterJoin` | No |
| `lateralJoin` | No |
| `onConflictMerge` | Yes |
| `cte` | Yes |
| `windowFunctions` | Yes |
| `json` | No |
| `intersectExcept` | Yes |

## Known Limitations

- No interactive transaction protocol over REST.
- `trx()` buffers statements and sends them as one atomic batch after callback completion.
- Individual query return values inside `trx()` are empty placeholders until batch execution completes.
- No connection pooling (request-based HTTP transport).

