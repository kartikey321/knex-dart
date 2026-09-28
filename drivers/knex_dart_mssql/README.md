# knex_dart_mssql

Microsoft SQL Server driver for [knex_dart](https://pub.dev/packages/knex_dart) using [`mssql`](https://pub.dev/packages/mssql), a pure-Dart TDS 7.4/8.0 implementation — no native dependencies.

[![Pub Version](https://img.shields.io/pub/v/knex_dart_mssql)](https://pub.dev/packages/knex_dart_mssql)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

## Installation

```yaml
dependencies:
  knex_dart_mssql: ^0.3.1
```

## Quick Start

```dart
import 'package:knex_dart_mssql/knex_dart_mssql.dart';

final db = await KnexMssql.connect(
  host: 'localhost',
  database: 'AdventureWorks',
  username: 'sa',
  password: 's3cr3t!',
  // Defaults: encrypt: true, trustServerCertificate: true — TLS is on, but
  // the server's certificate isn't validated, matching most local/on-prem
  // SQL Server instances, which present a self-signed certificate. Set
  // trustServerCertificate: false for a server with a certificate from a
  // trusted CA (e.g. Azure SQL).
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

- Pure Dart — no native library or system dependency required (no FreeTDS
  install step). Works anywhere a Dart `Socket`/`SecureSocket` does.

## Dialect Capabilities

`knex_dart_capabilities` does not currently include a dedicated `mssql` dialect entry, so static capability checks are not available yet for SQL Server.

Implemented driver/compiler highlights:

- MSSQL `OFFSET ... FETCH NEXT ...` pagination compilation for `.limit()` / `.offset()`.
- `having(...)` and `havingRaw(...)` compilation.
- Window-function SQL generation from query builder methods.

## Known Limitations

- One physical connection per `KnexMssql`/`MssqlClient` instance — no
  connection pooling wired into this driver yet (the underlying `mssql`
  package has its own `MssqlPool`, not yet adopted here). Unlike the
  previous driver, this connection is *not* a process-wide singleton:
  separate `KnexMssql.connect()` calls are fully independent.
- SQL Server-specific bracket quoting (`[col]`) is not emitted by default query compiler; use `raw()` when exact bracketed SQL is needed.
- Alias aggregate expressions (for example `count(*) as total`) so result keys are predictable.

