/// Regression tests for the web client's `_runTransactionScope` top-level
/// catch block (sqlite_client_web.dart) mirroring the native fix +
/// regression tests in test/sqlite_trx_test.dart.
///
/// If the callback already ended the transaction via raw SQL (or the
/// connection is torn down concurrently), `db.execute('ROLLBACK')` itself
/// throws. Before this was guarded — the same way the SAVEPOINT branch just
/// above it already guards `ROLLBACK TO SAVEPOINT` — that secondary failure
/// propagated *instead of* the callback's original error, and skipped
/// `_txUpdateStack.removeLast()`, permanently leaving a stale entry that made
/// `watch()` silently stop seeing non-transactional writes for the rest of
/// the client's lifetime (the update hook buffers into `_txUpdateStack.last`
/// instead of forwarding to `_updateController` whenever the stack is
/// non-empty).
///
/// Uses `storageMode: 'memory'`, so unlike the OPFS/IndexedDB tests this
/// needs neither a dedicated Worker nor `lib/web_assets/opfs_worker.dart.js`
/// — only sqlite3.wasm.
///
/// `@Retry(0)`: same reasoning as opfs_indexeddb_close_test.dart — a
/// regression here is deterministic, and dart_test.yaml's package-wide
/// Chrome `retry: 2` (for browser-launch flakiness) must not mask it.
@TestOn('browser')
@Retry(0)
library;

import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';
import 'package:test/test.dart';

int _fileCounter = 0;
String _uniqueFilename(String tag) =>
    'knex-sqlite-rollback-fail-$tag-'
    '${DateTime.now().microsecondsSinceEpoch}-${_fileCounter++}';

void main() {
  test(
    'a failing ROLLBACK preserves the original trx error (not the rollback '
    'failure)',
    () async {
      final db = await KnexSQLite.connect(
        filename: _uniqueFilename('error'),
        webStorageMode: 'memory',
      );
      addTearDown(db.close);
      await db.executeSchema((s) {
        s.createTable('t', (t) => t.integer('id').primary());
      });

      Object? caught;
      try {
        await db.trx((tx) async {
          await tx.rawSql('COMMIT'); // ends the transaction early
          throw Exception('boom');
        });
      } on Object catch (e) {
        caught = e;
      }
      expect(caught, isA<Exception>());
      expect(caught.toString(), contains('boom'));
    },
  );

  test(
    'watch() still emits for non-transactional writes after a rollback '
    'failure',
    () async {
      final db = await KnexSQLite.connect(
        filename: _uniqueFilename('watch'),
        webStorageMode: 'memory',
      );
      addTearDown(db.close);
      await db.executeSchema((s) {
        s.createTable('t', (t) => t.integer('id').primary());
      });

      try {
        await db.trx((tx) async {
          await tx.rawSql('COMMIT');
          throw Exception('boom');
        });
      } on Object {
        // Expected — asserted by the previous test.
      }

      final emissions = <int>[];
      final sub = db
          .watch(db('t').select(['*']))
          .listen((rows) => emissions.add(rows.length));
      await Future<void>.delayed(Duration.zero);

      await db.insert(db('t').insert({'id': 1}));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await sub.cancel();

      // Before the fix: only the initial (empty) emission ever arrived.
      expect(emissions, hasLength(2));
      expect(emissions.last, 1);
    },
  );
}
