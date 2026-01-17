---
title: Database Support
description: Supported databases and driver compatibility
---

# Database Support

Knex Dart currently supports SQL generation for all databases. Active database connections are planned.

## Query Builder (Available)

The query builder generates parameterized SQL compatible with PostgreSQL, MySQL, SQLite, and other databases.

```dart
final knex = Knex(client: MockClient());

final sql = knex('users')
  .select(['id', 'name'])
  .where('active', '=', true)
  .toSQL();

// sql.sql: select "id", "name" from "users" where "active" = $1
// sql.bindings: [true]
```

## Database Drivers

### PostgreSQL

**Status:** In development  
**Package:** `postgres` (pure Dart)

PostgreSQL will be the first supported database driver.

**Planned features:**
- Connection pooling
- Transaction support
- Prepared statements
- `RETURNING` clause
- Array types
- JSONB support

### MySQL / MariaDB

**Status:** Planned  
**Package:** `mysql_client` (pure Dart)

MySQL support planned after PostgreSQL implementation.

**Planned features:**
- Connection pooling
- Transaction support
- Prepared statements
- Binary protocol

### SQLite

**Status:** Planned  
**Package:** `sqlite3` (FFI)

SQLite support for embedded databases and Flutter applications.

**Planned features:**
- File-based databases
- In-memory databases
- Transaction support
- `RETURNING` clause (SQLite 3.35+)

### CockroachDB

**Status:** Under consideration  
**Compatibility:** PostgreSQL protocol

CockroachDB uses the PostgreSQL wire protocol. Support expected through PostgreSQL driver.

### Amazon Redshift

**Status:** Under consideration  
**Compatibility:** PostgreSQL-based

Redshift compatibility expected through PostgreSQL driver with potential dialect adjustments.

### Microsoft SQL Server

**Status:** Not currently planned  
**Package:** No production-ready driver available

MSSQL support blocked by lack of stable Dart drivers. Experimental packages exist but are not production-ready.

**Technical limitations:**
- No mature pure Dart driver
- FFI-based drivers require native dependencies
- TDS protocol implementation incomplete

**Alternative:** Generate SQL with query builder, execute with custom driver implementation.

### Oracle Database

**Status:** Evaluation phase  
**Package:** `oraffi` (new package, requires testing)

Oracle support depends on `oraffi` package maturity.

**Current status:**
- New Oracle driver package available
- Integration complexity assessment needed
- Production readiness to be determined

**Next steps:**
- Evaluate `oraffi` stability
- Test query compatibility
- Assess enterprise requirements

## Feature Matrix

| Feature | PostgreSQL | MySQL | SQLite |
|---------|-----------|-------|--------|
| Query Building | ✓ | ✓ | ✓ |
| Connection Pooling | Planned | Planned | N/A |
| Transactions | Planned | Planned | Planned |
| Prepared Statements | Planned | Planned | Planned |
| `RETURNING` | Planned | — | Planned |
| CTEs | ✓ | ✓ | ✓ |
| Window Functions | Planned | Planned | Planned |
| Recursive CTEs | ✓ | ✓ | ✓ |

## Architecture

```
Application Code
       ↓
Query Builder (current)
       ↓
Database Client (planned)
       ↓
Database Server
```

The query builder operates independently of database connections, enabling:

- SQL generation without database access
- Query validation and testing
- Cross-database compatibility
- Gradual migration from other query builders

## Configuration Examples

### PostgreSQL (Planned)

```dart
final knex = await Knex.postgres(
  host: 'localhost',
  port: 5432,
  database: 'myapp',
  username: 'user',
  password: 'password',
);

final users = await knex('users').select(['*']);
```

### MySQL (Planned)

```dart
final knex = await Knex.mysql(
  host: 'localhost',
  port: 3306,
  database: 'myapp',
  user: 'user',
  password: 'password',
);
```

### SQLite (Planned)

```dart
final knex = await Knex.sqlite('app.db');

// In-memory
final knex = await Knex.sqlite(':memory:');
```

## Current Limitations

**No Active Connections**  
Database drivers are not yet implemented. The query builder generates SQL but cannot execute queries.

**Workaround:**  
Execute generated SQL using native database packages:

```dart
import 'package:postgres/postgres.dart';

final knex = Knex(client: MockClient());
final query = knex('users').select(['*']).toSQL();

final conn = await Connection.open(/* config */);
final result = await conn.execute(query.sql, parameters: query.bindings);
```

## Testing Without Database

The query builder works without database connections:

```dart
test('generates correct SQL', () {
  final query = knex('users')
    .where('active', '=', true)
    .toSQL();
  
  expect(query.sql, contains('where "active" = \$1'));
  expect(query.bindings, [true]);
});
```

## Migration Path

### Step 1: SQL Generation (Current)
Use query builder for SQL generation and validation.

### Step 2: Manual Execution
Execute generated SQL with existing database packages.

### Step 3: Native Integration (Future)
Use built-in database drivers when available.

## Development Priority

1. PostgreSQL driver implementation
2. Connection pooling and transactions
3. MySQL driver implementation
4. SQLite driver implementation
5. Additional database dialects

## Compatibility Notes

### SQL Dialect Differences

The query builder generates standard SQL with parameterized queries (`$1`, `$2`, etc.). Database-specific features require dialect configuration.

**PostgreSQL-specific:**
- `RETURNING` clause
- Array operators
- JSONB functions

**MySQL-specific:**
- Backtick identifiers
- `LIMIT` syntax variations

**SQLite-specific:**
- Limited `ALTER TABLE` support
- Date/time handling

## Contributing

Database driver contributions welcome. See [GitHub repository](https://github.com/kartikey321/knex-dart) for contribution guidelines.

**Focus areas:**
- PostgreSQL driver implementation
- Connection pooling
- Transaction management
- Database-specific optimizations
