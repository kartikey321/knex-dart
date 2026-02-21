---
title: Knex Dart
description: A Knex.js port for Dart with broad API parity
---

# Knex Dart

A powerful, flexible SQL query builder for Dart, ported from **[Knex.js](https://knexjs.org)**.

## ✨ Features

- ✅ **Complete Query Building** - SELECT, INSERT, UPDATE, DELETE with full support
- ✅ **23 WHERE Methods** - basic, grouped, BETWEEN, EXISTS, IN, NULL, column comparisons
- ✅ **All JOIN Types** - INNER, LEFT, RIGHT, FULL OUTER, CROSS
- ✅ **Advanced JOIN Clauses** - `onVal`, `onIn`, `onBetween`, `onExists`, `using`, `onJsonPathEquals`
- ✅ **Subqueries** - In WHERE IN, FROM, and SELECT clauses
- ✅ **UNION Operations** - UNION and UNION ALL
- ✅ **CTEs** - Common Table Expressions (WITH clauses) including recursive
- ✅ **Aggregates** - COUNT, SUM, AVG, MIN, MAX with DISTINCT variants
- ✅ **first/pluck + lock modes** - `first`, `pluck`, `forUpdate`, `forShare`, `skipLocked`, `noWait`
- ✅ **411 Tests Passing** - comprehensive test coverage with Knex.js comparison tests
- ✅ **DB Wrappers Available** - PostgreSQL, MySQL, SQLite

## 🚀 Quick Start

```dart
import 'package:knex_dart/knex_dart.dart';

final knex = Knex(KnexConfig(
  client: 'sqlite3',
  connection: {'filename': ':memory:'},
));

// Build a query
final users = knex('users')
  .select(['id', 'name', 'email'])
  .where('active', '=', true)
  .where('role', '=', 'admin')
  .orderBy('name');

print(users.toSQL().sql);
// Output: select "id", "name", "email" from "users" 
//         where "active" = $1 and "role" = $2 
//         order by "name" asc
```

## 📦 Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  knex_dart: ^1.0.0
```

Then:

```bash
dart pub get
```

## 🎯 Why Knex Dart?

### Familiar API
Coming from Node.js/Knex.js? Most query-building patterns transfer directly.

### Type-Safe
Leverages Dart's strong typing while maintaining the flexibility of dynamic query building.

### Well-Tested
411 tests ensuring correctness and behavioral parity checks.

### Production-Ready Query Building
Complex queries? We've got you covered with subqueries, CTEs, JOINs, and more.

## 📚 Documentation

- [Getting Started](/getting-started/installation) - Install and configure
- [WHERE Clauses](/query-building/where-clauses) - All 23 methods
- [Subqueries](/query-building/subqueries) - Nested queries
- [CTEs (WITH)](/query-building/ctes) - Common table expressions
- [Migration Guide](/migration/from-knex-js) - Coming from Knex.js?
- [Examples](/examples/basic-queries) - Real-world examples

## 🔗 Links

- [GitHub Repository](https://github.com/kartikey321/knex-dart)
- [pub.dev Package](https://pub.dev/packages/knex_dart)
- [Report Issues](https://github.com/kartikey321/knex-dart/issues)

## 📊 Current Status

**Query API**: broad Knex.js-style coverage with known remaining gaps  
**Tests**: 411 passing  
**Execution**: PostgreSQL, MySQL, SQLite wrappers available

## 🤝 Contributing

Contributions welcome! Check out our [GitHub repository](https://github.com/kartikey321/knex-dart).

## 📄 License

MIT License - see LICENSE file for details.
