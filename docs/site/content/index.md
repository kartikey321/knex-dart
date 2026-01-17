---
title: Knex Dart
description: A powerful SQL query builder for Dart with 100% Knex.js API parity
---

# Knex Dart

A powerful, flexible SQL query builder for Dart, providing near-complete API parity with **[Knex.js](https://knexjs.org)**.

## ✨ Features

- ✅ **Complete Query Building** - SELECT, INSERT, UPDATE, DELETE with full support
- ✅ **16 WHERE Clause Variants** - All Knex.js WHERE methods implemented
- ✅ **All JOIN Types** - INNER, LEFT, RIGHT, FULL OUTER, CROSS with callback support  
- ✅ **Subqueries** - In WHERE IN, FROM, and SELECT clauses
- ✅ **UNION Operations** - UNION and UNION ALL
- ✅ **CTEs** - Common Table Expressions (WITH clauses) including recursive
- ✅ **Aggregates** - COUNT, SUM, AVG, MIN, MAX with DISTINCT variants
- ✅ **302 Tests Passing** - Comprehensive test coverage with Knex.js comparison tests
- 🔶 **PostgreSQL Support** - Coming soon
- 🔶 **MySQL & SQLite** - Planned

## 🚀 Quick Start

```dart
import 'package:knex_dart/knex_dart.dart';

final knex = Knex(client: MockClient());

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
Coming from Node.js/Knex.js? You already know how to use Knex Dart. We maintain API parity wherever possible.

### Type-Safe
Leverages Dart's strong typing while maintaining the flexibility of dynamic query building.

### Well-Tested
302 tests ensuring correctness and Knex.js behavioral parity.

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
- [pub.dev Package](https://pub.dev/packages/knex_dart) (coming soon)
- [Report Issues](https://github.com/kartikey321/knex-dart/issues)

## 📊 Current Status

**Query API**: ~90% Knex.js parity  
**Tests**: 302 passing  
**Features**: 18 implemented

## 🤝 Contributing

Contributions welcome! Check out our [GitHub repository](https://github.com/kartikey321/knex-dart).

## 📄 License

MIT License - see LICENSE file for details.
