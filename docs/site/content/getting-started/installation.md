---
title: Installation
description: Install and set up Knex Dart in your project
---

# Installation

Get started with Knex Dart in your Dart or Flutter project.

## Requirements

- Dart SDK 3.10.0 or higher
- For Flutter: Flutter 3.22.0 or higher

## Packages

`knex_dart` is the core query builder. To connect to a database, add the driver package for your database — it pulls in `knex_dart` automatically.

| Database | Package | Install |
|---|---|---|
| PostgreSQL | `knex_dart_postgres` | `dart pub add knex_dart_postgres` |
| MySQL | `knex_dart_mysql` | `dart pub add knex_dart_mysql` |
| SQLite | `knex_dart_sqlite` | `dart pub add knex_dart_sqlite` |

## Add a Driver

Pick the driver for your database and add it to `pubspec.yaml`:

### PostgreSQL

```yaml
dependencies:
  knex_dart_postgres: ^0.1.0
```

### MySQL

```yaml
dependencies:
  knex_dart_mysql: ^0.1.0
```

### SQLite

```yaml
dependencies:
  knex_dart_sqlite: ^0.1.0
```

Then run:

```bash
dart pub get
```

## Query Builder Only

If you only need SQL generation (no database connection), add the core package directly:

```yaml
dependencies:
  knex_dart: ^1.0.0
```

This is useful for testing, SQL snapshots, or generating queries to pass to another layer.

## Verify Installation

### With a driver (SQLite example)

```dart
import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';

Future<void> main() async {
  final db = await KnexSQLite.connect(filename: ':memory:');
  print(db('users').select(['id', 'name']).toSQL().sql);
  // select "id", "name" from "users"
  await db.destroy();
}
```

### Query builder only

```dart
import 'package:knex_dart/knex_dart.dart';

void main() {
  // Use a mock client for query generation
  final db = Knex(MockClient());
  print(db('users').select(['id', 'name']).toSQL().sql);
}
```

## Next Steps

- [Quick Start](./quick-start) - Connect and run your first query
- [WHERE Clauses](/query-building/where-clauses) - Learn query filtering
- [Examples](/examples/basic-queries) - Real-world patterns
