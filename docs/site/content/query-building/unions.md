---
title: UNION Operations
description: Combine results from multiple queries
---

# UNION Operations

Combine results from multiple queries using UNION and UNION ALL.

## Basic UNION

Combines results and removes duplicates:

```dart
final query1 = knex('users').select(['name']).where('active', '=', true);
final query2 = knex('users').select(['name']).where('role', '=', 'admin');

knex.from(query1).union([query2]);
// select "name" from "users" where "active" = $1
// union
// select "name" from "users" where "role" = $2
```

Or chain directly:

```dart
knex('users')
  .select(['name'])
  .where('active', '=', true)
  .union([
    knex('users').select(['name']).where('role', '=', 'admin')
  ]);
```

## UNION ALL

Keeps all rows including duplicates:

```dart
knex('users')
  .select(['name'])
  .where('type', '=', 'customer')
  .unionAll([
    knex('users').select(['name']).where('type', '=', 'admin')
  ]);
// select "name" from "users" where "type" = $1
// union all
// select "name" from "users" where "type" = $2
```

## Multiple UNIONs

Combine more than two queries:

```dart
knex('users')
  .where('type', '=', 'customer')
  .union([
    knex('users').where('type', '=', 'admin'),
    knex('users').where('type', '=', 'moderator')
  ]);
// select * from "users" where "type" = $1
// union select * from "users" where "type" = $2
// union select * from "users" where "type" = $3
```

## UNION with ORDER BY/LIMIT

Apply ordering and limiting to final result:

```dart
knex('users')
  .where('active', '=', true)
  .union([
    knex('users').where('role', '=', 'admin')
  ])
  .orderBy('name')
  .limit(10);
// select * from "users" where "active" = $1
// union select * from "users" where "role" = $2
// order by "name" asc limit $3
```

## Column Alignment

All queries must have same number and type of columns:

```dart
// ✅ Correct - same columns
knex('users').select(['id', 'name'])
  .union([
    knex('admins').select(['id', 'name'])
  ]);

// ❌ Error - different columns
knex('users').select(['id', 'name'])
  .union([
    knex('admins').select(['id'])  // Column mismatch!
  ]);
```

## UNION vs UNION ALL

| Feature | UNION | UNION ALL |
|---------|-------|-----------|
| Duplicates | Removed | Kept |
| Performance | Slower (deduplication) | Faster |
| Use when | Need unique results | All rows needed |

```dart
// UNION - removes duplicate names
knex('customers').select(['name'])
  .union([
    knex('employees').select(['name'])
  ]);
// Result: ['John', 'Jane', 'Bob'] (unique)

// UNION ALL - keeps all names
knex('customers').select(['name'])
  .unionAll([
    knex('employees').select(['name'])
  ]);
// Result: ['John', 'Jane', 'Bob', 'John'] (with duplicates)
```

## Complex Example

```dart
// Get all active users from different sources
final regularUsers = knex('users')
  .select(['id', 'email', client.raw("'regular' as type")])
  .where('active', '=', true);

final adminUsers = knex('admins')
  .select(['id', 'email', client.raw("'admin' as type")])
  .where('active', '=', true);

final guestUsers = knex('guests')
  .select(['id', 'email', client.raw("'guest' as type")])
  .where('session_active', '=', true);

knex.from(regularUsers)
  .unionAll([adminUsers, guestUsers])
  .orderBy('type')
  .orderBy('email');
```

## UNION with CTEs

Combine UNION with CTEs for complex queries:

```dart
knex
  .withQuery('all_users',
    knex('customers').select(['id', 'name'])
      .union([
        knex('employees').select(['id', 'name'])
      ])
  )
  .select(['*'])
  .from('all_users')
  .where('name', 'like', 'J%');
```

## Parameter Handling

Knex Dart automatically:
- ✅ Renumbers parameters across UNIONs
- ✅ Merges bindings correctly
- ✅ Maintains parameter sequence

```dart
knex('users')
  .where('active', '=', true)   // $1
  .union([
    knex('users').where('role', '=', 'admin')  // $2 (not $1!)
  ])
  .limit(10);  // $3
// Bindings: [true, 'admin', 10]
```

## Best Practices

1. **Match column count** - All UNIONed queries must have same columns
2. **Use UNION ALL** when possible - Faster if duplicates don't matter
3. **Apply ORDER BY/LIMIT at the end** - On final result, not individual queries
4. **Name columns consistently** - Use aliases for clarity

```dart
// Good
knex('table1').select(['id', 'name as full_name'])
  .union([
    knex('table2').select(['id', 'username as full_name'])
  ]);

// Bad - inconsistent naming
knex('table1').select(['id', 'name'])
  .union([
    knex('table2').select(['id', 'username'])
  ]);
```

## Next Steps

- [CTEs](/query-building/ctes) - WITH clauses
- [Subqueries](/query-building/subqueries) - Nested queries
- [Examples](/examples/basic-queries) - Real-world patterns
