---
title: Transactions
description: Run multiple queries atomically with automatic commit and rollback
---

# Transactions

Knex Dart supports database transactions through the `trx()` method on every driver. All queries inside the callback are wrapped in a single atomic unit — automatically committed on success and rolled back on any error.

## Basic Usage

<!-- doc:run scope=local expect_stdout='2' -->
```dart
import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';

final db = await KnexSQLite.connect(filename: ':memory:');
await db.executeSchema((schema) {
  schema.createTable('accounts', (t) {
    t.increments('id');
    t.string('owner');
    t.integer('balance');
  });
  schema.createTable('ledger', (t) {
    t.increments('id');
    t.string('action');
    t.integer('amount');
  });
});

await db.trx((trx) async {
  await trx.insert(
    trx.queryBuilder().table('accounts').insert({'owner': 'Alice', 'balance': 1000}),
  );
  await trx.insert(
    trx.queryBuilder().table('ledger').insert({'action': 'deposit', 'amount': 1000}),
  );
  // Both succeed → automatic COMMIT
});

final accounts = await db.select(db('accounts'));
final ledger = await db.select(db('ledger'));
print(accounts.length + ledger.length);
await db.close();
```

If any statement inside throws, **both** are rolled back automatically — nothing is partially written.

## Error Handling and Rollback

```dart
try {
  await db.trx((trx) async {
    await trx.update(
      trx.queryBuilder()
        .table('accounts')
        .where('id', '=', fromId)
        .update({'balance': trx.queryBuilder().client.raw('balance - ?', [amount])}),
    );

    // This throws → triggers automatic ROLLBACK
    await trx.update(
      trx.queryBuilder()
        .table('accounts')
        .where('id', '=', toId)
        .update({'balance': trx.queryBuilder().client.raw('balance + ?', [amount])}),
    );
  });
} catch (e) {
  print('Transfer failed, changes rolled back: $e');
}
```

## Reading Inside a Transaction

All queries — reads and writes — must go through `trx`, not the outer `db`, to execute inside the transaction:

```dart
await db.trx((trx) async {
  // READ inside transaction (sees uncommitted writes above)
  final balance = await trx.select(
    trx.queryBuilder()
        .table('accounts')
        .select(['balance'])
        .where('id', '=', accountId)
        .limit(1),
  );

  if (balance[0]['balance'] < amount) {
    throw Exception('Insufficient funds');  // triggers ROLLBACK
  }

  await trx.update(
    trx.queryBuilder()
      .table('accounts')
      .where('id', '=', accountId)
      .update({'balance': trx.queryBuilder().client.raw('balance - ?', [amount])}),
  );
});
```

## Returning Values from a Transaction

`trx()` returns whatever your callback returns:

```dart
final newId = await db.trx((trx) async {
  final rows = await trx.insert(
    trx.queryBuilder()
      .table('users')
      .insert({'name': 'Alice', 'email': 'alice@example.com'})
      .returning(['id']),
  );
  await trx.insert(
    trx.queryBuilder()
        .table('audit_log')
        .insert({'user_id': rows[0]['id'], 'action': 'signup'}),
  );
  return rows[0]['id'];
});

print('Created user $newId');
```

## Driver-Specific Details

### PostgreSQL

Uses the `postgres` package's native `runTx` internally — full PostgreSQL transaction semantics including isolation levels.

```dart
import 'package:knex_dart_postgres/knex_dart_postgres.dart';

final db = await KnexPostgres.connect(...);
await db.trx((trx) async { ... });
```

### MySQL

Uses native MySQL transaction with `START TRANSACTION` / `COMMIT` / `ROLLBACK`.

```dart
import 'package:knex_dart_mysql/knex_dart_mysql.dart';

final db = await KnexMySQL.connect(...);
await db.trx((trx) async { ... });
```

### SQLite

Uses `BEGIN` / `COMMIT` / `ROLLBACK` statements directly on the SQLite
connection. Nested `trx()` calls use savepoints, and concurrent top-level
transactions are serialized so unrelated async callers do not interleave on the
same SQLite connection.

```dart
import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';

final db = await KnexSQLite.connect(filename: ':memory:');
await db.trx((trx) async { ... });
```

On native SQLite, `watch()` update notifications are buffered until the outer
transaction commits, so reactive listeners do not see rolled-back writes.

## Real-World Example: Bank Transfer

```dart
Future<void> transfer({
  required int fromAccountId,
  required int toAccountId,
  required double amount,
}) async {
  await db.trx((trx) async {
    // Lock both rows and read balances
    final accounts = await trx.select(
      trx.queryBuilder()
        .table('accounts')
        .whereIn('id', [fromAccountId, toAccountId])
        .select(['id', 'balance']),
    );

    final from = accounts.firstWhere((r) => r['id'] == fromAccountId);
    final to = accounts.firstWhere((r) => r['id'] == toAccountId);

    if ((from['balance'] as num) < amount) {
      throw Exception('Insufficient balance');
    }

    // Debit
    await trx.update(
      trx.queryBuilder()
        .table('accounts')
        .where('id', '=', fromAccountId)
        .update({'balance': trx.queryBuilder().client.raw('balance - ?', [amount])}),
    );

    // Credit
    await trx.update(
      trx.queryBuilder()
        .table('accounts')
        .where('id', '=', toAccountId)
        .update({'balance': trx.queryBuilder().client.raw('balance + ?', [amount])}),
    );

    // Audit
    await trx.insert(
      trx.queryBuilder().table('transfers').insert({
        'from_account_id': fromAccountId,
        'to_account_id': toAccountId,
        'amount': amount,
        'created_at': DateTime.now().toIso8601String(),
      }),
    );
  });
}
```

## Nested Transactions (Savepoints)

Calling `trx()` inside an already-open transaction creates a **savepoint** instead of a new `BEGIN`. This allows partial rollback without rolling back the entire outer transaction.

<!-- doc:run scope=local expect_stdout='Outer,partial_rollback_demo' -->
```dart
import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';

final db = await KnexSQLite.connect(filename: ':memory:');
await db.executeSchema((schema) {
  schema.createTable('accounts', (t) {
    t.integer('id').primary();
    t.string('owner');
    t.integer('balance');
  });
  schema.createTable('audit_log', (t) {
    t.increments('id');
    t.string('action');
  });
});

await db.trx((outer) async {
  // Outer insert
  await outer.insert(
    outer.queryBuilder().table('accounts').insert({
      'id': 1,
      'owner': 'Outer',
      'balance': 1000,
    }),
  );

  try {
    await outer.trx((inner) async {
      await inner.insert(
        inner.queryBuilder().table('accounts').insert({
          'id': 2,
          'owner': 'Inner',
          'balance': 500,
        }),
      );
      throw Exception('something went wrong');  // inner rolls back to savepoint
    });
  } catch (_) {
    // inner rolled back — outer is still open
  }

  // Alice's row is still there; Bob's row was rolled back
  await outer.insert(
    outer.queryBuilder().table('audit_log').insert({'action': 'partial_rollback_demo'}),
  );
  // COMMIT — only Alice's row and the audit log entry are written
});

final accountRows = await db.select(db('accounts').select(['owner']).orderBy('id'));
final auditRows = await db.select(db('audit_log').select(['action']).orderBy('id'));
print('${accountRows.first['owner']},${auditRows.first['action']}');
await db.close();
```

If the inner exception is **not caught**, it propagates to the outer callback and rolls back everything:

```dart
// Everything rolled back — both Alice and Bob rows are gone
await db.trx((outer) async {
  await outer.insert(
    outer.queryBuilder().table('accounts').insert({'owner': 'Alice', 'balance': 1000}),
  );
  await outer.trx((inner) async {
    await inner.insert(
      inner.queryBuilder().table('accounts').insert({'owner': 'Bob', 'balance': 500}),
    );
    throw Exception('bubble up');  // not caught → outer also rolls back
  });
});
```

Savepoints are supported on PostgreSQL, MySQL, SQLite, and DuckDB. The savepoint name is generated automatically (`sp_` + microseconds in base-36).

## Notes

- Transactions are connection-pinned: each outer `trx()` acquires one pooled connection for its full scope.
- Nesting depth is unlimited — each nested call adds one more savepoint level.

## Next Steps

- [Write Operations](/query-building/write-operations) — INSERT, UPDATE, DELETE
- [Schema Builder](/query-building/schema-builder) — Creating tables inside transactions
- [Examples](/examples/basic-queries) — More real-world patterns
