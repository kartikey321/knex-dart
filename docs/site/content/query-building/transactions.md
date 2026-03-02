---
title: Transactions
description: Run multiple queries atomically with automatic commit and rollback
---

# Transactions

Knex Dart supports database transactions through the `trx()` method on every driver. All queries inside the callback are wrapped in a single atomic unit — automatically committed on success and rolled back on any error.

## Basic Usage

```dart
await db.trx((trx) async {
  await trx.insert(
    trx('accounts').insert({'owner': 'Alice', 'balance': 1000}),
  );
  await trx.update(
    trx('ledger').insert({'action': 'deposit', 'amount': 1000}),
  );
  // Both succeed → automatic COMMIT
});
```

If any statement inside throws, **both** are rolled back automatically — nothing is partially written.

## Error Handling and Rollback

```dart
try {
  await db.trx((trx) async {
    await trx.update(
      trx('accounts')
        .where('id', '=', fromId)
        .update({'balance': db.raw('balance - ?', [amount])}),
    );

    // This throws → triggers automatic ROLLBACK
    await trx.update(
      trx('accounts')
        .where('id', '=', toId)
        .update({'balance': db.raw('balance + ?', [amount])}),
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
    trx('accounts').select(['balance']).where('id', '=', accountId).limit(1),
  );

  if (balance[0]['balance'] < amount) {
    throw Exception('Insufficient funds');  // triggers ROLLBACK
  }

  await trx.update(
    trx('accounts')
      .where('id', '=', accountId)
      .update({'balance': db.raw('balance - ?', [amount])}),
  );
});
```

## Returning Values from a Transaction

`trx()` returns whatever your callback returns:

```dart
final newId = await db.trx((trx) async {
  final rows = await trx.select(
    trx('users')
      .insert({'name': 'Alice', 'email': 'alice@example.com'})
      .returning(['id']),
  );
  await trx.insert(
    trx('audit_log').insert({'user_id': rows[0]['id'], 'action': 'signup'}),
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

Uses `BEGIN` / `COMMIT` / `ROLLBACK` statements directly on the synchronous SQLite connection.

```dart
import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';

final db = await KnexSQLite.connect(filename: ':memory:');
await db.trx((trx) async { ... });
```

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
      trx('accounts')
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
      trx('accounts')
        .where('id', '=', fromAccountId)
        .update({'balance': db.raw('balance - ?', [amount])}),
    );

    // Credit
    await trx.update(
      trx('accounts')
        .where('id', '=', toAccountId)
        .update({'balance': db.raw('balance + ?', [amount])}),
    );

    // Audit
    await trx.insert(
      trx('transfers').insert({
        'from_account_id': fromAccountId,
        'to_account_id': toAccountId,
        'amount': amount,
        'created_at': DateTime.now().toIso8601String(),
      }),
    );
  });
}
```

## Limitations

- Nested transactions are supported using savepoints (`SAVEPOINT`, `ROLLBACK TO SAVEPOINT`, `RELEASE SAVEPOINT`).
- Transactions are connection-pinned: each outer `trx()` acquires one pooled connection for its full scope.

## Next Steps

- [Write Operations](/query-building/write-operations) — INSERT, UPDATE, DELETE
- [Schema Builder](/query-building/schema-builder) — Creating tables inside transactions
- [Examples](/examples/basic-queries) — More real-world patterns
