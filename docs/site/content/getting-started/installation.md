---
title: Installation
description: Install and set up Knex Dart in your project
---

# Installation

Get started with Knex Dart in your Dart or Flutter project.

## Requirements

- Dart SDK 3.0.0 or higher
- For Flutter: Flutter 3.10.0 or higher

## Add Dependency

Add Knex Dart to your `pubspec.yaml`:

```yaml
dependencies:
  knex_dart: ^1.0.0
```

## Install

Run:

```bash
dart pub get
```

Or for Flutter:

```bash
flutter pub get
```

## Verify Installation

Create a simple test file:

```dart
import 'package:knex_dart/knex_dart.dart';

Future<void> main() async {
  final db = await Knex.sqlite(filename: ':memory:');
  final query = db.queryBuilder().table('users').select(['*']);
  print(query.toSQL().sql);
  await db.close();
}
```

Run it:

```bash
dart run your_file.dart
```

## Next Steps

- [Quick Start](./quick-start) - Build your first query
- [WHERE Clauses](/query-building/where-clauses) - Learn query filtering
- [Examples](/examples/basic-queries) - Real-world patterns
