# knex_dart_mssql

Microsoft SQL Server driver for [knex_dart](https://pub.dev/packages/knex_dart) using the `mssql_connection` FreeTDS-based runtime.

[![Pub Version](https://img.shields.io/pub/v/knex_dart_mssql)](https://pub.dev/packages/knex_dart_mssql)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

## Installation

```yaml
dependencies:
  knex_dart_mssql: ^0.1.0
```

## Quick Start

```dart
import 'package:knex_dart_mssql/knex_dart_mssql.dart';

final db = await KnexMssql.connect(
  host: 'localhost',
  database: 'AdventureWorks',
  username: 'sa',
  password: 's3cr3t!',
);

final rows = await db.select(
  db
      .queryBuilder()
      .table('users')
      .where('active', '=', 1)
      .orderBy('id')
      .limit(10),
);

await db.close();
```

## Platform Requirements

- Native runtime only (uses FFI through `mssql_connection`).
- FreeTDS installation is required:
  - macOS: `brew install freetds`
  - Ubuntu/Debian: `sudo apt-get install -y freetds-dev libct4`

## Dialect Capabilities

`knex_dart_capabilities` does not currently include a dedicated `mssql` dialect entry, so static capability checks are not available yet for SQL Server.

Implemented driver/compiler highlights:

- MSSQL `OFFSET ... FETCH NEXT ...` pagination compilation for `.limit()` / `.offset()`.
- `having(...)` and `havingRaw(...)` compilation.
- Window-function SQL generation from query builder methods.

## Known Limitations

- No connection pooling in this driver (single shared connection runtime).
- Underlying `MssqlConnection` is singleton-based; operations are effectively serialized.
- SQL Server-specific bracket quoting (`[col]`) is not emitted by default query compiler; use `raw()` when exact bracketed SQL is needed.
- Alias aggregate expressions (for example `count(*) as total`) so result keys are predictable.

