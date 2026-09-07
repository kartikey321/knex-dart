/// Confirms `IndexedDbFileSystem` (and `InMemoryFileSystem`) have no
/// dedicated-worker requirement — unlike `SimpleOpfsFileSystem`, whose class
/// doc comment in sqlite3's `lib/src/wasm/vfs/simple_opfs.dart` explicitly
/// restricts it to dedicated workers ("not in the JavaScript context for a
/// tab or a shared web worker"). This runs `SQLiteClient` with `storageMode:
/// 'indexedDb'` directly on the test page's main thread — no
/// WorkerHarness/opfs_worker.dart anywhere in this file — as direct
/// confirmation rather than trusting sqlite3's docs at face value.
@TestOn('browser')
library;

import 'package:knex_dart/knex_dart.dart';
import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';
import 'package:sqlite3/wasm.dart' show IndexedDbFileSystem;
import 'package:test/test.dart';

import 'worker_harness.dart' show WorkerHarness;

String _wasmUri() {
  // Same "walk this page's own URL back to package root" trick as
  // WorkerHarness.packageRootUrl — reused directly since this file lives at
  // the same test/browser/ depth and the main thread's `window.location` is
  // the exact same kind of per-run hash-prefixed URL a worker's would be.
  return '${WorkerHarness.packageRootUrl()}lib/web_assets/sqlite3.wasm';
}

SQLiteClient _indexedDbClient(String filename) {
  return SQLiteClient.fromConfig(
    KnexConfig(
      client: 'sqlite3',
      connection: {
        'filename': filename,
        'storageMode': 'indexedDb',
        'wasmUri': _wasmUri(),
      },
    ),
  );
}

void main() {
  test(
    'indexedDb storage mode: write, close, reopen succeeds without a '
    'dedicated worker',
    () async {
      final filename =
          'knex-sqlite-mainthread-indexeddb-'
          '${DateTime.now().microsecondsSinceEpoch}';

      final client = _indexedDbClient(filename);
      await client.initialize();
      await client.rawQuery('CREATE TABLE t (id INTEGER)', const []);
      await client.rawQuery('INSERT INTO t (id) VALUES (1)', const []);
      await client.close();

      // No dedicated worker anywhere in this test — if IndexedDbFileSystem
      // actually required one (like SimpleOpfsFileSystem does), opening it
      // above would already have failed with a VFS-registration or "not
      // available in this context" style error.
      final verify = _indexedDbClient(filename);
      await verify.initialize();
      final rows = await verify.rawQuery('SELECT * FROM t', const []);
      await verify.close();

      expect(rows, hasLength(1));

      await IndexedDbFileSystem.deleteDatabase(filename);
    },
  );
}
