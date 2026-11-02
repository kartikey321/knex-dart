## 0.5.0

Two breaking changes, split out of the six fixes in 0.4.2 so those — all
non-breaking — reach everyone pinned at `^0.4.x` without waiting on a
constraint bump. Under pub's 0.x rules a minor bump is not picked up by
`^0.4.x`, so bundling these would have withheld the OPFS data-loss fix and the
rest until each user widened their constraint by hand.

- **`rawSql()` / `rawQuery()` now reject more than one statement.** SQLite
  compiles only the first statement of a string, so
  `rawSql('CREATE TABLE a (...); CREATE TABLE b (...)')` created `a`, discarded
  `b` and reported success. Passing several statements throws `ArgumentError`
  rather than applying part of the input silently.

  A trailing semicolon on a single statement is still accepted. For several
  statements, call `rawSql()` once per statement, or use `executeSchema()`,
  which already sends them one at a time — every `schemaBuilder` operation
  emits single statements, so schema code is unaffected.

- **Web: the default `storageMode` is now `indexedDb`, not `memory`.** Calling
  `KnexSQLite.connect(filename: 'app.db')` on web with no `webStorageMode`
  returned an in-memory database that looked persistent and discarded
  everything on close — the same silent non-persistence as the OPFS bug fixed
  in 0.4.2, reached by omission rather than by a broken path. A filename is a
  request for storage that outlives the page, so the default now persists.

  `indexedDb` rather than `auto`, despite `auto` preferring the faster OPFS
  backend: `auto` falls back on *any* OPFS failure, and OPFS holds exclusive
  `FileSystemSyncAccessHandle`s. A second connection to the same name while
  the first still holds them doesn't fail — it quietly lands on IndexedDB
  instead, so two connections read and write two different stores, each
  believing it has the database, with writes from one invisible to the other
  and to later OPFS reopens. That is the same class of silent divergence this
  release removes elsewhere, so it does not belong on the default path.
  IndexedDB persists, works on a page as well as in a worker (OPFS requires a
  dedicated worker), and has no exclusive-handle contention, so one name
  always resolves to one store.

  `auto` and `opfs` remain available explicitly. The explicit `opfs` mode never
  falls back, and `auto` no longer falls back on contention either — see the
  next entry.

  `:memory:` still means in-memory, matching the native driver. Pass
  `webStorageMode: 'memory'` explicitly to keep the old behavior for a named
  database.

- **Web: `auto` mode no longer silently switches backends on an OPFS lock
  conflict.** OPFS sync access handles are exclusive, and `auto` caught every
  OPFS failure before falling back, so a second connection to a database
  another connection already held did not fail — it succeeded on IndexedDB. A
  *different store*. Both sides then read and wrote their own copy of the
  database, each invisible to the other and to any later OPFS reopen, with
  nothing raised anywhere.

  `auto` now distinguishes "OPFS is unusable in this context" — which still
  falls back to IndexedDB, then memory, and is the common case on a page's main
  thread where `createSyncAccessHandle` is worker-only — from "OPFS is held by
  someone else", which now propagates. The lock conflict is recognised by the
  `NoModificationAllowedError` the File System standard requires when a lock
  cannot be taken; the wording was read off a real Chrome run rather than
  assumed, and a worker test holds one connection open and asserts the second
  raises instead of landing elsewhere.

  Two limitations worth knowing, neither removed by this change:

  The thrown value arrives as an opaque `JSObject`, so this is a match on a DOM
  error *name* in the message text, verified against Chrome. A browser that
  reports lock contention differently would still fall back and could still
  diverge.

  More importantly, `auto` remains unsafe for a database shared between a page
  and a dedicated worker. A page cannot take an OPFS sync access handle at all
  — the API is worker-only — so `auto` on a page falls back to IndexedDB even
  while a worker holds the same name open in OPFS, leaving two stores and no
  error. That is not a lock conflict and cannot be detected as one; it follows
  from `auto` resolving per execution context. Use `indexedDb` when a page and
  a worker share one database.

## 0.4.2

Six bugs found by an adversarial review of this driver. All six failed
silently — wrong results or a hung stream, never an error — and each is covered
by a regression test confirmed to fail before the fix.

- **Web/OPFS: a named database never persisted anything.** Opening with
  `webStorageMode: 'opfs'` accepted `CREATE TABLE` and `INSERT` without
  complaint and had lost everything by the next open. The driver passed the
  caller's filename as both the OPFS directory *and* the sqlite path, but
  `SimpleOpfsFileSystem` persists exactly two paths — `/database` and
  `/database-journal` — and its `xOpen` falls through to an in-memory overlay
  for any other path, so every write went to memory and was dropped on close.
  The sqlite path is now fixed at `/database`, chosen from the filesystem
  actually in use rather than from the requested mode, so `auto` mode is
  covered whenever it selects OPFS. Databases stay separated by the OPFS
  directory, which is still keyed by name. (#35)

- **`WITH ... SELECT` queries returned no rows.** The statement kind was
  guessed from the SQL text — `startsWith('SELECT')`, `startsWith('PRAGMA')`,
  `contains('RETURNING')` — and a CTE matches none of them, so it took the
  no-rows branch and returned `[]` for a query that had rows. Reachable from
  the typed builder, not just raw SQL: `.withQuery(...)` was affected. SQL led
  by a comment (`/* ... */ SELECT`) was misread the same way. The kind is no
  longer inferred from the text at all; every statement goes through
  `select()`, which returns whatever result columns the statement declares and
  applies DDL/DML side effects exactly as before.

- **One client's transaction made another client think it was nested.** The
  "already inside a transaction" marker was a `static` field, so it was shared
  by every client instance. A top-level `trx()` on client B, called from inside
  client A's transaction, saw A's marker, skipped B's own serialization queue
  and issued `SAVEPOINT`/`RELEASE` without ever having run `BEGIN` — failing
  with `no such savepoint`. The marker and the savepoint counter are now
  per-instance, matching the fix already made in `knex_dart_postgres`.

- **`watch()` never ended when the database closed.** Its subscription had no
  `onDone`, so the stream stayed open after `close()`: `await for` over a watch
  stream never returned and the subscription was never released. Stream
  completion is now forwarded, and so are errors.

- **`streamQuery()` leaked its statement when the stream was cancelled early,
  locking the table.** The stream was `Stream.fromIterable` over a `sync*`
  generator; cancelling abandons that iterator without running the generator's
  `finally`, so the prepared statement was never closed and its cursor kept a
  read lock. A later `DROP TABLE` on that table then failed with `database
  table is locked` (`SqliteException(6)`). It is now an `async*` generator,
  which is terminated on cancel and does run `finally`. The web client already
  used `async*` and was never affected.

- **The prepared-statement cache was unbounded.** It is keyed by SQL text, so
  SQL assembled per request — an `IN` list whose length varies, a predicate
  built from user input — produced a new key every time, and neither the map
  nor the native statements behind it ever stopped growing. Now capped at 128
  entries, evicting least-recently-used and closing what it evicts.

Known limitation, unchanged and pre-existing: concurrent *nested* transactions
on a single client (`db.trx((t) => Future.wait([t.trx(...), t.trx(...)]))`)
still fail with `no such savepoint`. Only outermost scopes are serialized, and
SQLite savepoints form a stack, so interleaved nested scopes release each
other's. Serializing the nested branch risks deadlocking a nested transaction
that awaits another, so it is left alone here rather than changed under a bug
fix.

## 0.4.1

- Bumped `sqlite3` to `^3.0.0` and `sqlite3_web` to `^0.9.0`; replaced
  deprecated `.dispose()` calls with `.close()` in the native and web
  clients.
- Bumped `lints` to `^6.1.0` and `test` to `^1.31.0`.

## 0.4.0

- Added `watch()` reactive query streams for SQLite based on `UPDATE_HOOK`.
- Added web/WASM storage mode selection via `webStorageMode` / `storageMode`
  with `memory`, `indexedDb`, `opfs`, and `auto` modes.
- Serialized concurrent top-level transactions across native and web clients.
- Buffered web SQLite update notifications through transaction boundaries to
  match native `watch()` semantics.
- Added coverage for concurrent transactions, reactive query behavior, and
  native/web storage mode handling.

## 0.3.0

- Added `QueryInterceptor` pipeline support: attach OTel, logging, or custom
  interceptors via the `interceptors` parameter on `KnexSQLite.connect()`.
- Fixed `destroyPool()` idempotency — double close no longer throws.
- Fixed `StateError` on query after close with a clear message.
- Improved exception propagation in transaction rollback using
  `Error.throwWithStackTrace` to preserve original stack traces.
- Fixed savepoint ID generation to use a per-instance counter instead of
  timestamp-based IDs, avoiding collisions under concurrent transactions.

## 0.2.1

- Reduced wrapper overhead by reusing compiled SQL through the interceptor
  pipeline instead of compiling the same query twice.
- Removed redundant async wrappers in low-level query dispatch while preserving
  public `Future` semantics and error propagation.
- Optimized native SQLite row mapping by reading `ResultSet` column names and
  rows directly.
- No query result shape, binding behavior, or SQL execution semantics changed.

## 0.2.0

- Added web/WASM SQLite support with conditional web client loading.
- Added async web client initialization and configurable WASM URL support via
  `connection['wasmUri']`, including fallback URI behavior.
- Added prepared statement caching in native SQLite client execution path.
- Added stream query support in native SQLite client.
- Updated dependencies for web/WASM compatibility (`sqlite3` update, `sqlite3_web`,
  and `universal_io`).

## 0.1.1

- Updated dependency to `knex_dart: ^1.1.0`.
- Uses core `runInTransaction(...)` migration transaction path with SQLite-safe behavior.

## 0.1.0

- Initial release.
- SQLite driver for `knex_dart` using the `sqlite3` package.
- `KnexSQLite.connect()` factory supporting file-based and in-memory databases.
- Full query execution: select, insert, update, delete.
- Transaction support via `trx()`.
- Schema execution via `executeSchema()`.
