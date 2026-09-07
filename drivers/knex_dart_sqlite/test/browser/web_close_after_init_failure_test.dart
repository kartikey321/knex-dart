/// Regression test for `destroyPool()` (sqlite_client_web.dart): `close()`
/// must complete cleanly even when this client's own `initialize()` failed.
///
/// Before this was guarded, `destroyPool()`'s `try { await initialize(); }
/// finally { ...cleanup... }` had no catch — cleanup ran correctly (the
/// finally block always executes), but the original init error then
/// propagated out of `destroyPool()` uncaught, so `close()` rethrew it to
/// whoever called close(). A caller treating close() as a safe,
/// always-succeeds cleanup call — the whole premise of this PR's fix — would
/// be surprised to see it throw.
///
/// Uses a deliberately-unreachable `wasmUri` to force a genuine
/// `_loadSqlite3()` failure — no OPFS/Worker/dedicated-worker machinery
/// needed for this one, `_loadSqlite3()` runs before any storage-mode-
/// specific setup.
@TestOn('browser')
@Retry(0)
library;

import 'package:knex_dart/knex_dart.dart';
import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';
import 'package:test/test.dart';

SQLiteClient _clientWithUnreachableWasm(String filename) {
  return SQLiteClient.fromConfig(
    KnexConfig(
      client: 'sqlite3',
      connection: {
        'filename': filename,
        'storageMode': 'memory',
        'wasmUri': '/does-not-exist-sqlite3.wasm',
      },
    ),
  );
}

void main() {
  test('initialize() genuinely fails against an unreachable wasmUri '
      '(sanity check for the rest of this file)', () async {
    final client = _clientWithUnreachableWasm('init-fail-sanity');
    await expectLater(client.initialize(), throwsA(anything));
  });

  test(
    'close() completes without throwing after initialize() failed',
    () async {
      final client = _clientWithUnreachableWasm('init-fail-close');
      try {
        await client.initialize();
      } on Object {
        // Expected — asserted by the sanity check above.
      }

      // The actual point of this test: close() itself must not rethrow
      // the init failure. It should complete normally.
      await client.close();
      expect(client.isClosed, isTrue);

      // A second close() must also stay a safe no-op.
      await client.close();
    },
  );
}
