# knex_dart_duckdb

DuckDB driver for [knex_dart](https://pub.dev/packages/knex_dart) for in-process analytical SQL workloads.

[![Pub Version](https://img.shields.io/pub/v/knex_dart_duckdb)](https://pub.dev/packages/knex_dart_duckdb)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

## Installation

```yaml
dependencies:
  knex_dart_duckdb: ^0.1.0
```

## Quick Start

```dart
import 'package:knex_dart_duckdb/knex_dart_duckdb.dart';

final db = await KnexDuckDB.memory();
// final db = await KnexDuckDB.file('analytics.db');

await db.executeSchema((schema) {
  schema.createTable('events', (t) {
    t.increments('id');
    t.string('name');
    t.integer('value');
  });
});

await db.insert(
  db.queryBuilder().table('events').insert({'name': 'signup', 'value': 1}),
);

final rows = await db.select(
  db.queryBuilder().table('events').orderBy('id').limit(10),
);

await db.close();
```

## Platform Requirements

- Native Dart/Flutter runtime (FFI).
- macOS/Linux/Windows: install `libduckdb` (for example `brew install duckdb` on macOS).
- Android/iOS: uses the `dart_duckdb` plugin runtime.
- Browser/Web: not supported by this driver.

## Dialect Capabilities

Based on `knex_dart_capabilities` (`duckdb` dialect):

| Capability | Support |
|---|---|
| `returning` | Yes |
| `fullOuterJoin` | Yes |
| `lateralJoin` | Yes |
| `onConflictMerge` | Yes |
| `cte` | Yes |
| `windowFunctions` | Yes |
| `json` | Yes |
| `intersectExcept` | Yes |

## Known Limitations

- `knex_dart_duckdb` web build throws `UnsupportedError` (web stub).
- `DuckDBClient` is not thread-safe; use one client per isolate.
- On desktop/server, `libduckdb` must be discoverable at runtime.

