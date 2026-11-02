# knex_dart_sqlite

SQLite driver for [knex_dart](https://pub.dev/packages/knex_dart) — execute queries against a SQLite database using the knex_dart query builder.

[![Pub Version](https://img.shields.io/pub/v/knex_dart_sqlite)](https://pub.dev/packages/knex_dart_sqlite)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

## Installation

```yaml
dependencies:
  knex_dart_sqlite: ^0.5.0
```

## Usage

```dart
import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';

// Pick one connection style for your app:
final db = await KnexSQLite.connect(filename: 'app.db');
// final db = await KnexSQLite.connect(filename: ':memory:');
// final db = await KnexSQLite.connect(
//   filename: 'app.db',
//   webStorageMode: 'auto', // auto | opfs | indexedDb | memory
// );

// Schema
await db.executeSchema(
  (schema) {
    schema.createTable('users', (t) {
      t.increments('id');
      t.string('name').notNullable();
      t.string('email').unique();
      t.timestamps();
    });
  },
);

// INSERT
await db.insert(
  db('users').insert({'name': 'Alice', 'email': 'alice@example.com'}),
);

// SELECT
final users = await db.select(
  db('users').where('active', '=', true).orderBy('name'),
);

// UPDATE
await db.update(
  db('users').where('id', '=', 1).update({'name': 'Bob'}),
);

// DELETE
await db.delete(
  db('users').where('id', '=', 1).delete(),
);

// Transactions
await db.trx((trx) async {
  await trx.insert(trx('accounts').insert({'balance': 100}));
  await trx.update(trx('accounts').where('id', '=', 1).update({'balance': 0}));
});

// Reactive query watching
final sub = db.watch(
  db('users').where('active', '=', true).orderBy('name'),
  debounce: const Duration(milliseconds: 100),
).listen((rows) {
  print('Active users changed: ${rows.length}');
});

await sub.cancel();
await db.close();
```

## SQLite-specific features

- `?` positional placeholders
- Double-quoted identifier quoting
- In-memory database support (`:memory:`)
- Browser/WASM storage modes: `memory`, `indexedDb`, `opfs`, `auto`
- JSON operators via `json_extract()`
- Nested transactions via savepoints
- Top-level transaction serialization on SQLite's single connection
- Reactive `watch()` query streams

`webStorageMode` is only supported on web/WASM. On native SQLite, passing it to
`connect()` throws `UnsupportedError`.


### Raw SQL takes one statement

`rawSql()` / `rawQuery()` accept exactly one statement. Several separated by
`;` throw `ArgumentError`: SQLite compiles only the first, so before 0.5.0 the
remainder was silently discarded and the call still reported success. A
trailing semicolon on a single statement is fine. Send multiple statements with
one call each, or through `executeSchema()`, which already does that.

### Default web storage mode

Omitting `webStorageMode` resolves to `indexedDb` for any filename other than
`:memory:`. Before 0.5.0 the default was `memory`, so a named database looked
persistent and lost everything on close.

Not `auto`, even though it would prefer the faster OPFS backend: `auto` falls
back on any OPFS failure, and OPFS holds exclusive file handles, so a second
connection to the same name quietly lands on IndexedDB and ends up reading a
different store than the first — silently. IndexedDB persists, works on a page
as well as in a worker, and has no such contention.

Use `webStorageMode: 'opfs'` or `'auto'` if you want OPFS, with one caveat
below. `opfs` never falls back, so it always uses the OPFS store or raises. As
of 0.5.0 `auto` propagates an OPFS *lock conflict* instead of falling back, so
two dedicated workers cannot end up on different stores.

**`auto` is still unsafe for a database shared between a page and a worker.** A
page cannot take an OPFS sync access handle at all — that API is
dedicated-worker only — so `auto` on a page falls back to IndexedDB. If a
worker holds the same name open in OPFS, the two contexts then read and write
different stores and nothing is raised. This is not lock contention, so it
cannot be detected the way 0.5.0 detects that; it is inherent to `auto`
resolving per context. Use `webStorageMode: 'indexedDb'` when a page and a
worker must share one database.

Pass `webStorageMode: 'memory'` for the pre-0.5.0 behavior.

### One writer per database name

Neither web backend is safe for more than one connection to the same database
name, and the driver cannot make it safe.

OPFS enforces single access: the second connection cannot take the file handles
and fails (loudly, as of 0.5.0). IndexedDB does not enforce it at all — its
`xLock` delegates to a per-connection in-memory mirror, and `sqlite3` documents
that "no guarantees on durability can be made... file changes are written at
some point after the database is changed". Two connections on one name
therefore interleave asynchronous block write-back into a single store, which
is corruption rather than divergence, and silent.

So a single writer per name is a precondition of web persistence. Where several
contexts need the same database, elect one owner — a Web Lock held over a
dedicated worker, with other contexts proxying to it, is the established
pattern — and note that OPFS additionally requires that owner to be a
*dedicated* worker, never a page or a shared worker. Where contexts only need
their own scratch space, give each its own name, or use `memory`.

### OPFS persistence

Each named database opened with `webStorageMode: 'opfs'` lives in its own OPFS
directory, stored at the fixed path `SimpleOpfsFileSystem` persists. Before
0.4.2 a named OPFS database took writes and lost them on close, with no error —
upgrade if you depended on OPFS persistence.

## Documentation

- Docs home: https://docs.knex.mahawarkartikey.in/
- Transactions: https://docs.knex.mahawarkartikey.in/query-building/transactions
- Migrations: https://docs.knex.mahawarkartikey.in/migration/migrations
- Schema Builder: https://docs.knex.mahawarkartikey.in/query-building/schema-builder

## See also

- [knex_dart](https://pub.dev/packages/knex_dart) — core package
- [knex_dart_postgres](https://pub.dev/packages/knex_dart_postgres)
- [knex_dart_mysql](https://pub.dev/packages/knex_dart_mysql)
