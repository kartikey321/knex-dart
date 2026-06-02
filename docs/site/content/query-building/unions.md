---
title: UNION Operations
description: Combine results from multiple queries
---

# UNION Operations

Combine results from multiple queries using UNION and UNION ALL.

## Basic UNION

Combines results and removes duplicates:

```dart
final db = KnexQuery.forDialect(KnexDialect.postgres);

final q1 = db.from('users').select(['name']).where('active', '=', true);
final q = q1.union([
  db.from('users').select(['name']).where('role', '=', 'admin')
]).toSQL();
print(q.sql);
// select "name" from "users" where "active" = $1
// union
// select "name" from "users" where "role" = $2
```

Or chain directly:

```dart
final q = db.from('users')
    .select(['name'])
    .where('active', '=', true)
    .union([
      db.from('users').select(['name']).where('role', '=', 'admin')
    ])
    .toSQL();
print(q.sql);
```

## UNION ALL

Keeps all rows including duplicates:

```dart
final q = db.from('users')
    .select(['name'])
    .where('type', '=', 'customer')
    .unionAll([
      db.from('users').select(['name']).where('type', '=', 'admin')
    ])
    .toSQL();
print(q.sql);
// select "name" from "users" where "type" = $1
// union all
// select "name" from "users" where "type" = $2
```

## Multiple UNIONs

Combine more than two queries:

```dart
final q = db.from('users')
    .where('type', '=', 'customer')
    .union([
      db.from('users').where('type', '=', 'admin'),
      db.from('users').where('type', '=', 'moderator')
    ])
    .toSQL();
print(q.sql);
// select * from "users" where "type" = $1
// union select * from "users" where "type" = $2
// union select * from "users" where "type" = $3
```

## UNION with ORDER BY/LIMIT

Apply ordering and limiting to final result:

```dart
final q = db.from('users')
    .where('active', '=', true)
    .union([
      db.from('users').where('role', '=', 'admin')
    ])
    .orderBy('name')
    .limit(10)
    .toSQL();
print(q.sql);
// select * from "users" where "active" = $1
// union select * from "users" where "role" = $2
// order by "name" asc limit $3
```

## Column Alignment

All queries must have same number and type of columns:

```dart
// ✅ Correct - same columns
final q = db.from('users').select(['id', 'name'])
    .union([
      db.from('admins').select(['id', 'name'])
    ])
    .toSQL();
print(q.sql);

// ❌ Error - different columns
final q2 = db.from('users').select(['id', 'name'])
    .union([
      db.from('admins').select(['id'])  // Column mismatch!
    ])
    .toSQL();
print(q2.sql);
```

## UNION vs UNION ALL

| Feature | UNION | UNION ALL |
|---------|-------|-----------|
| Duplicates | Removed | Kept |
| Performance | Slower (deduplication) | Faster |
| Use when | Need unique results | All rows needed |

```dart
// UNION - removes duplicate names
final q = db.from('customers').select(['name'])
    .union([
      db.from('employees').select(['name'])
    ])
    .toSQL();
print(q.sql);
// Result: ['John', 'Jane', 'Bob'] (unique)

// UNION ALL - keeps all names
final q2 = db.from('customers').select(['name'])
    .unionAll([
      db.from('employees').select(['name'])
    ])
    .toSQL();
print(q2.sql);
// Result: ['John', 'Jane', 'Bob', 'John'] (with duplicates)
```

## Complex Example

```dart
// Get all active users from different sources
final regularUsers = db.from('users')
    .select(['id', 'email', db.raw("'regular' as type")])
    .where('active', '=', true);

final adminUsers = db.from('admins')
    .select(['id', 'email', db.raw("'admin' as type")])
    .where('active', '=', true);

final guestUsers = db.from('guests')
    .select(['id', 'email', db.raw("'guest' as type")])
    .where('session_active', '=', true);

final q = regularUsers
    .unionAll([adminUsers, guestUsers])
    .orderBy('type')
    .orderBy('email')
    .toSQL();
print(q.sql);
```

## UNION with CTEs

Combine UNION with CTEs for complex queries:

```dart
final q = db.queryBuilder()
    .withQuery('all_users',
      db.from('customers').select(['id', 'name'])
        .union([
          db.from('employees').select(['id', 'name'])
        ])
    )
    .from('all_users')
    .select(['*'])
    .where('name', 'like', 'J%')
    .toSQL();
print(q.sql);
```

## Parameter Handling

Knex Dart automatically:
- ✅ Renumbers parameters across UNIONs
- ✅ Merges bindings correctly
- ✅ Maintains parameter sequence

```dart
final q = db.from('users')
    .where('active', '=', true)   // $1
    .union([
      db.from('users').where('role', '=', 'admin')  // $2 (not $1!)
    ])
    .limit(10)  // $3
    .toSQL();
print(q.sql);
// Bindings: [true, 'admin', 10]
```

## Best Practices

1. **Match column count** - All UNIONed queries must have same columns
2. **Use UNION ALL** when possible - Faster if duplicates don't matter
3. **Apply ORDER BY/LIMIT at the end** - On final result, not individual queries
4. **Name columns consistently** - Use aliases for clarity

```dart
// Good
final q = db.from('table1').select(['id', 'name as full_name'])
    .union([
      db.from('table2').select(['id', 'username as full_name'])
    ])
    .toSQL();
print(q.sql);

// Bad - inconsistent naming
final q2 = db.from('table1').select(['id', 'name'])
    .union([
      db.from('table2').select(['id', 'username'])
    ])
    .toSQL();
print(q2.sql);
```

## Next Steps

- [CTEs](/query-building/ctes) - WITH clauses
- [Subqueries](/query-building/subqueries) - Nested queries
- [Examples](/examples/basic-queries) - Real-world patterns
