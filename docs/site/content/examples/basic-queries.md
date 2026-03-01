---
title: Basic Examples
description: Common query patterns and real-world examples
---

# Basic Examples

Learn common patterns through practical examples. All examples assume a connected `db` instance:

```dart
import 'package:knex_dart_postgres/knex_dart_postgres.dart';

final db = await KnexPostgres.connect(
  host: 'localhost', database: 'myapp', username: 'user', password: 'pass',
);
```

## User Authentication

```dart
Future<Map?> authenticateUser(String email, String password) async {
  final rows = await db.select(
    db('users')
      .select(['id', 'email', 'password_hash', 'active'])
      .where('email', '=', email)
      .limit(1),
  );

  if (rows.isEmpty) return null;

  if (verifyPassword(password, rows[0]['password_hash'])) {
    return rows[0];
  }

  return null;
}
```

## Pagination

```dart
Future<List<Map>> getPaginatedUsers(int page, int perPage) async {
  return db.select(
    db('users')
      .select(['id', 'name', 'email'])
      .orderBy('created_at', 'desc')
      .limit(perPage)
      .offset(page * perPage),
  );
}
```

## Search with Multiple Conditions

```dart
Future<List<Map>> searchUsers({String? name, String? email, bool? active}) async {
  var query = db('users').select(['*']);

  if (name != null) query = query.where('name', 'like', '%$name%');
  if (email != null) query = query.where('email', '=', email);
  if (active != null) query = query.where('active', '=', active);

  return db.select(query);
}
```

## Related Data (JOINs)

```dart
// Users with their order count
final usersWithOrders = await db.select(
  db('users')
    .select(['users.id', 'users.name'])
    .select([db.raw('count(orders.id) as order_count')])
    .leftJoin('orders', 'users.id', '=', 'orders.user_id')
    .groupBy(['users.id', 'users.name']),
);
```

## Bulk Insert

```dart
await db.insert(
  db('users').insert([
    {'name': 'John', 'email': 'john@example.com'},
    {'name': 'Jane', 'email': 'jane@example.com'},
  ]),
);
```

## Soft Delete

```dart
Future<void> softDeleteUser(int userId) async {
  await db.update(
    db('users')
      .where('id', '=', userId)
      .update({'deleted_at': DateTime.now().toIso8601String()}),
  );
}

// Query only non-deleted users
final activeUsers = await db.select(
  db('users').select(['*']).whereNull('deleted_at'),
);
```

## Aggregation Report

```dart
// Sales by category
final salesReport = await db.select(
  db('orders')
    .select(['products.category'])
    .select([
      db.raw('count(*) as order_count'),
      db.raw('sum(orders.amount) as total_revenue'),
      db.raw('avg(orders.amount) as avg_order_value'),
    ])
    .join('products', 'orders.product_id', '=', 'products.id')
    .groupBy(['products.category'])
    .orderBy('total_revenue', 'desc'),
);
```

## Conditional Filtering

```dart
Future<List<Map>> buildDashboardQuery({
  String? status,
  DateTime? startDate,
  DateTime? endDate,
  int? userId,
}) async {
  var query = db('orders').select(['*']);

  if (status != null) query = query.where('status', '=', status);
  if (startDate != null) query = query.where('created_at', '>=', startDate.toIso8601String());
  if (endDate != null) query = query.where('created_at', '<=', endDate.toIso8601String());
  if (userId != null) query = query.where('user_id', '=', userId);

  return db.select(query.orderBy('created_at', 'desc'));
}
```

## Upsert

```dart
await db.insert(
  db('users')
    .insert({'email': 'alice@example.com', 'name': 'Alice'})
    .onConflict('email')
    .merge(),
);
```

## Get or Create

```dart
Future<Map> getOrCreateUser(String email, String name) async {
  final existing = await db.select(
    db('users').select(['*']).where('email', '=', email).limit(1),
  );

  if (existing.isNotEmpty) return existing[0];

  final inserted = await db.select(
    db('users')
      .insert({'email': email, 'name': name})
      .returning(['*']),
  );

  return inserted[0];
}
```

## Top N per Group (CTE + Window Function)

```dart
final topProducts = await db.select(
  db().withQuery(
    'ranked',
    db('products').select([
      '*',
      db.raw('row_number() over (partition by category order by sales desc) as rank'),
    ]),
  )
  .select(['*'])
  .from('ranked')
  .where('rank', '<=', 3),
);
```

## Next Steps

- [WHERE Clauses](/query-building/where-clauses) — All filtering methods
- [Subqueries](/query-building/subqueries) — Nested queries
- [CTEs](/query-building/ctes) — WITH clauses
- [Migration Guide](/migration/from-knex-js) — From Knex.js
