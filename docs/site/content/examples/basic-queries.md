---
title: Basic Examples
description: Common query patterns and real-world examples
---

# Basic Examples

Learn common patterns through practical examples.

## User Authentication

```dart
Future<Map?> authenticateUser(String email, String password) async {
  final user = await knex('users')
    .select(['id', 'email', 'password_hash', 'active'])
    .where('email', '=', email)
    .limit(1);
  
  if (user.isEmpty) return null;
  
  // Verify password (using your hash function)
  if (verifyPassword(password, user[0]['password_hash'])) {
    return user[0];
  }
  
  return null;
}
```

## Pagination

```dart
Future<List<Map>> getPaginatedUsers(int page, int perPage) async {
  return await knex('users')
    .select(['id', 'name', 'email'])
    .orderBy('created_at', 'desc')
    .limit(perPage)
    .offset(page * perPage);
}
```

## Search with Multiple Conditions

```dart
QueryBuilder searchUsers(String? name, String? email, bool? active) {
  var query = knex('users').select(['*']);
  
  if (name != null) {
    query = query.where('name', 'like', '%$name%');
  }
  
  if (email != null) {
    query = query.where('email', '=', email);
  }
  
  if (active != null) {
    query = query.where('active', '=', active);
  }
  
  return query;
}
```

## Related Data (JOINs)

```dart
// Get users with their order count
final usersWithOrders = await knex('users')
  .select([
    'users.id',
    'users.name',
    client.raw('count(orders.id) as order_count')
  ])
  .leftJoin('orders', 'users.id', 'orders.user_id')
  .groupBy('users.id')
  .groupBy('users.name');
```

## Bulk Insert

```dart
Future<void> importUsers(List<Map<String, dynamic>> users) async {
  await knex('users').insert(users);
}

// Usage
await importUsers([
  {'name': 'John', 'email': 'john@example.com'},
  {'name': 'Jane', 'email': 'jane@example.com'},
]);
```

## Update with Conditions

```dart
// Activate all users who verified email
Future<int> activateVerifiedUsers() async {
  return await knex('users')
    .update({'active': true})
    .where('email_verified', '=', true)
    .where('active', '=', false);
}
```

## Soft Delete

```dart
Future<void> softDeleteUser(int userId) async {
  await knex('users')
    .update({'deleted_at': DateTime.now().toIso8601String()})
    .where('id', '=', userId);
}

// Query only non-deleted users
final activeUsers = await knex('users')
  .select(['*'])
  .whereNull('deleted_at');
```

## Aggregation Report

```dart
// Sales by category
final salesReport = await knex('orders')
  .select([
    'products.category',
    client.raw('count(*) as order_count'),
    client.raw('sum(orders.amount) as total_revenue'),
    client.raw('avg(orders.amount) as avg_order_value')
  ])
  .join('products', 'orders.product_id', 'products.id')
  .groupBy('products.category')
  .orderBy(client.raw('total_revenue'), 'desc');
```

## Conditional Filtering

```dart
QueryBuilder buildDashboardQuery({
  String? status,
  DateTime? startDate,
  DateTime? endDate,
  int? userId,
}) {
  var query = knex('orders')
    .select(['*']);
  
  if (status != null) {
    query = query.where('status', '=', status);
  }
  
  if (startDate != null) {
    query = query.where('created_at', '>=', startDate.toIso8601String());
  }
  
  if (endDate != null) {
    query = query.where('created_at', '<=', endDate.toIso8601String());
  }
  
  if (userId != null) {
    query = query.where('user_id', '=', userId);
  }
  
  return query.orderBy('created_at', 'desc');
}
```

## Exists Check

```dart
// Check if user has any orders
Future<bool> userHasOrders(int userId) async {
  final exists = await knex('orders')
    .select([client.raw('1')])
    .where('user_id', '=', userId)
    .limit(1);
  
  return exists.isNotEmpty;
}
```

## Get or Create

```dart
Future<Map> getOrCreateUser(String email, String name) async {
  // Try to find existing
  final existing = await knex('users')
    .select(['*'])
    .where('email', '=', email)
    .limit(1);
  
  if (existing.isNotEmpty) {
    return existing[0];
  }
  
  // Create new
  final inserted = await knex('users')
    .insert({'email': email, 'name': name})
    .returning(['*']);
  
  return inserted[0];
}
```

## Top N per Group

```dart
// Top 3 products per category by sales
final topProducts = await knex.withQuery('ranked',
  knex('products')
    .select([
      '*',
      client.raw('''
        row_number() over (
          partition by category 
          order by sales desc
        ) as rank
      ''')
    ])
)
.select(['*'])
.from('ranked')
.where('rank', '<=', 3);
```

## Next Steps

- [WHERE Clauses](/query-building/where-clauses) - All 23 methods
- [Subqueries](/query-building/subqueries) - Nested queries  
- [CTEs](/query-building/ctes) - WITH clauses
- [Migration Guide](/migration/from-knex-js) - From Knex.js
