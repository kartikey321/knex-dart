# knex_dart_snowflake

Snowflake driver for [knex_dart](https://pub.dev/packages/knex_dart) using the Snowflake SQL API v2.

[![Pub Version](https://img.shields.io/pub/v/knex_dart_snowflake)](https://pub.dev/packages/knex_dart_snowflake)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

## Installation

```yaml
dependencies:
  knex_dart_snowflake: ^0.1.0
```

## Quick Start

```dart
import 'package:knex_dart_snowflake/knex_dart_snowflake.dart';

final db = KnexSnowflake(
  account: 'myorg-myaccount',
  token: 'oauth_or_jwt_token',
  database: 'MY_DATABASE',
  schema: 'PUBLIC',
  warehouse: 'COMPUTE_WH',
);

final rows = await db.select(
  db.queryBuilder().table('SALES').where('REGION', '=', 'EMEA').limit(25),
);

db.close();
```

## Platform Requirements

- Works on Dart VM and web runtimes (HTTP-based driver).
- Requires Snowflake OAuth or JWT bearer token authentication.

## Dialect Capabilities

Based on `knex_dart_capabilities` (`snowflake` dialect):

| Capability | Support |
|---|---|
| `returning` | No |
| `fullOuterJoin` | Yes |
| `lateralJoin` | Yes |
| `onConflictMerge` | No |
| `cte` | Yes |
| `windowFunctions` | Yes |
| `json` | Yes |
| `intersectExcept` | Yes |

## Known Limitations

- No transaction helper in this driver.
- With `asyncExecution: true`, query methods return immediately and async results must be polled via `getAsyncResult(statementHandle)`.
- Binding type conversion is limited to boolean/integer/real/text mapping.
- Result values are returned as Snowflake API payload values (commonly string-typed).

