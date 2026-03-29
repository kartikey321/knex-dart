# knex_dart_bigquery

Google BigQuery driver for [knex_dart](https://pub.dev/packages/knex_dart) using the BigQuery Jobs REST API.

[![Pub Version](https://img.shields.io/pub/v/knex_dart_bigquery)](https://pub.dev/packages/knex_dart_bigquery)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

## Installation

```yaml
dependencies:
  knex_dart_bigquery: ^0.1.0
```

## Quick Start

```dart
import 'package:knex_dart_bigquery/knex_dart_bigquery.dart';

final db = KnexBigQuery(
  projectId: 'my-gcp-project',
  token: 'ya29.oauth_token',
  defaultDataset: 'analytics',
  location: 'US',
);

final rows = await db.select(
  db.queryBuilder().table('events').where('event_type', '=', 'signup').limit(50),
);

db.close();
```

## Platform Requirements

- Works on Dart VM and web runtimes (HTTP-based driver).
- Requires a valid Google OAuth bearer token with BigQuery permissions.

## Dialect Capabilities

Based on `knex_dart_capabilities` (`bigquery` dialect):

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

- No interactive transaction API in this driver.
- Each query is submitted as a separate BigQuery job.
- Large result pagination is not yet surfaced by this client (single result fetch path).
- Parameter type mapping is basic (`BOOL`, `INT64`, `FLOAT64`, `STRING`).

