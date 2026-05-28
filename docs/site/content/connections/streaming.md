---
title: Streaming
description: Stream large result sets row-by-row with streamQuery() for memory-efficient processing
---

# Streaming

For large result sets, loading all rows into memory at once with `db.select()` may be impractical. Use `streamQuery()` (or the driver's `.stream()` method) to process rows one at a time as they arrive from the database.

## Basic Usage

```dart
final stream = db.streamQuery(
  db('events').where('processed', '=', false).orderBy('id'),
);

await for (final row in stream) {
  await processEvent(row);
}
```

Each `row` is a `Map<String, dynamic>` — the same type returned by `db.select()`.

## Why Stream Instead of Select?

| `db.select()` | `streamQuery()` |
|---|---|
| Loads all rows into a `List` | Yields rows one at a time |
| Simple for small result sets | Memory-efficient for large sets |
| Easier to use with `await` | Requires `await for` or `Stream` APIs |

For a table with millions of rows, `db.select()` allocates a large list up-front. `streamQuery()` holds only the current row in memory.

## Supported Drivers

| Driver | Streaming support |
|---|---|
| PostgreSQL | `streamQuery()` via cursor |
| MySQL | `streamQuery()` via row streaming |
| SQLite | `streamQuery()` via statement cursor |
| DuckDB | `streamQuery()` via `fetchAllStream()` |
| MSSQL | Not supported |
| BigQuery | Not supported |
| Snowflake | Not supported |
| Turso | Not supported |
| D1 | Not supported |

## PostgreSQL Example

```dart
import 'package:knex_dart_postgres/knex_dart_postgres.dart';

final db = await KnexPostgres.connect(
  host: 'localhost',
  database: 'analytics',
  username: 'user',
  password: 'pass',
);

final stream = db.streamQuery(
  db('events')
    .select(['id', 'type', 'payload', 'created_at'])
    .where('created_at', '>', '2024-01-01')
    .orderBy('id'),
);

int count = 0;
await for (final row in stream) {
  count++;
  if (count % 10000 == 0) print('Processed $count rows...');
  await handleEvent(row);
}

print('Done — $count events processed');
await db.destroy();
```

## SQLite Example

```dart
import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';

final db = await KnexSQLite.connect(filename: 'app.db');

final stream = db.streamQuery(
  db('logs').orderBy('timestamp'),
);

await for (final row in stream) {
  print('[${row['timestamp']}] ${row['message']}');
}

await db.destroy();
```

## DuckDB Example

DuckDB is particularly well-suited for streaming large analytical queries:

```dart
import 'package:knex_dart_duckdb/knex_dart_duckdb.dart';

final db = await KnexDuckDB.file('/data/warehouse.db');

final stream = db.streamQuery(
  db.queryBuilder()
    .from('sales')
    .select(['region', 'product_id'])
    .sum('amount as total')
    .groupBy(['region', 'product_id'])
    .orderBy('total', 'desc'),
);

await for (final row in stream) {
  await writeSummary(row);
}

await db.close();
```

## Error Handling

```dart
try {
  await for (final row in db.streamQuery(db('events').orderBy('id'))) {
    await process(row);
  }
} catch (e) {
  print('Stream error: $e');
}
```

Any database error during streaming will throw inside the `await for` loop and can be caught normally.

## Streaming Inside a Transaction

The driver-level `.stream()` method works inside transactions:

```dart
await db.trx((trx) async {
  final stream = trx.stream(
    trx.queryBuilder().table('jobs').where('status', '=', 'pending').orderBy('id'),
  );

  await for (final row in stream) {
    await trx.update(
      trx.queryBuilder()
        .table('jobs')
        .where('id', '=', row['id'])
        .update({'status': 'processing'}),
    );
    await doWork(row);
  }
});
```

## Next Steps

- [Connection Pooling](/connections/pooling) — Configure pool size for high-throughput streaming workloads
- [Transactions](/query-building/transactions) — Streaming inside atomic operations
- [DuckDB](/database-support#duckdb) — OLAP driver optimized for large analytical result sets
