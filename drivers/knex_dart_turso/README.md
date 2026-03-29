# knex_dart_turso

Turso (libSQL) driver for [knex_dart](https://pub.dev/packages/knex_dart) over the libSQL HTTP pipeline API.

[![Pub Version](https://img.shields.io/pub/v/knex_dart_turso)](https://pub.dev/packages/knex_dart_turso)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

## Installation

```yaml
dependencies:
  knex_dart_turso: ^0.1.0
```

## Quick Start

```dart
import 'package:knex_dart_turso/knex_dart_turso.dart';

final db = KnexTurso(
  url: 'https://my-db-org.turso.io',
  authToken: 'eyJ...',
);

final rows = await db.select(
  db.queryBuilder().table('users').where('active', '=', 1).limit(20),
);

await db.trx((trx) async {
  await trx.insert(db.queryBuilder().table('audit').insert({'action': 'read_users'}));
});

db.close();
```

## Platform Requirements

- Works on Dart VM and web runtimes (HTTP-based driver).
- Requires a Turso/libSQL endpoint URL.
- `authToken` is optional for public/local endpoints and required for protected databases.

## Dialect Capabilities

Based on `knex_dart_capabilities` (`turso` dialect):

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

- Transactions are HTTP-session based (`BEGIN`/`COMMIT`/`ROLLBACK`) and depend on network reliability between calls.
- No connection pool (request-based HTTP transport).
- For strict interactive transaction guarantees, Turso's native SDK/WebSocket flow is recommended.

