---
name: knex-schema-and-transactions
description: Use when creating tables, altering schema, or running atomic write flows with knex_dart driver wrappers.
metadata:
  knex_dart_version: 1.2.1
---

This skill assumes a live driver wrapper such as `KnexSQLite`, `KnexPostgres`, or `KnexMySQL`.

## Schema Execution

Use `executeSchema((schema) { ... })` on the driver wrapper:

```dart
await db.executeSchema((schema) {
  schema.createTable('users', (table) {
    table.increments('id');
    table.string('name').notNullable();
    table.string('email').unique();
    table.boolean('active').defaultTo(true);
    table.timestamps();
  });
});
```

Add follow-up schema operations in the same callback when needed:

```dart
await db.executeSchema((schema) {
  schema.alterTable('users', (table) {
    table.index(['email']);
  });
});
```

## Basic Transaction Pattern

Use `trx(...)` on the driver wrapper. Inside the callback, run everything through the transaction-scoped client:

```dart
await db.trx((trx) async {
  await trx.insert(
    trx.queryBuilder().table('accounts').insert({
      'owner': 'Alice',
      'balance': 1000,
    }),
  );

  await trx.insert(
    trx.queryBuilder().table('ledger').insert({
      'action': 'deposit',
      'amount': 1000,
    }),
  );
});
```

## Reads Inside a Transaction

```dart
await db.trx((trx) async {
  final rows = await trx.select(
    trx.queryBuilder()
        .table('accounts')
        .select(['id', 'balance'])
        .where('id', '=', 1)
        .limit(1),
  );

  if ((rows.first['balance'] as num) < 100) {
    throw Exception('Insufficient balance');
  }
});
```

## Nested Transactions

Nested `trx(...)` calls create savepoints on the drivers that support them:

```dart
await db.trx((outer) async {
  await outer.insert(
    outer.queryBuilder().table('accounts').insert({'owner': 'Alice'}),
  );

  try {
    await outer.trx((inner) async {
      await inner.insert(
        inner.queryBuilder().table('accounts').insert({'owner': 'Bob'}),
      );
      throw Exception('rollback inner only');
    });
  } catch (_) {
    // outer transaction is still open here
  }
});
```

## Practical Rules

- Use `executeSchema(...)` for DDL on the driver wrapper
- Use `trx(...)` for atomic sequences of live queries
- Inside a transaction, always use the transaction object, not the outer `db`
- End pure query-building examples with `.toSQL()`; use driver execution helpers only when you actually need to run the query

## Docs

- Schema builder: `https://docs.knex.mahawarkartikey.in/raw/query-building/schema-builder.md`
- Transactions: `https://docs.knex.mahawarkartikey.in/raw/query-building/transactions.md`
- Migrations: `https://docs.knex.mahawarkartikey.in/raw/migration/migrations.md`
