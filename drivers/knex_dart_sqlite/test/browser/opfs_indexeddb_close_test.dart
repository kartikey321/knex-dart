/// Browser tests for the OPFS/IndexedDB handle-leak fix in
/// `SQLiteClient` (web) — drivers/knex_dart_sqlite/lib/src/sqlite_client_web.dart.
///
/// These run the actual `SQLiteClient` (fromConfig — the same code path
/// `SQLiteClient.connect()` / `KnexSQLite.connect()` use internally) inside a
/// real dedicated Web Worker, because `SimpleOpfsFileSystem` (package:sqlite3's
/// OPFS VFS) only works inside a dedicated worker, never on the main thread of
/// a tab (see sqlite3's `lib/src/wasm/vfs/simple_opfs.dart` class doc
/// comment). See worker_harness.dart / opfs_worker.dart for the RPC protocol
/// this test drives.
///
/// Before running (see tool/):
///   dart run tool/download_wasm.dart
///   dart run tool/build_browser_worker.dart
///   dart test test/browser/ --platform=chrome
///
/// `SQLiteClient` and `KnexSQLite` are not tested separately here:
/// `KnexSQLite.close()` (lib/src/knex_sqlite.dart) is a pure passthrough to
/// `SQLiteClient.close()` with no additional logic of its own, and every race
/// this suite probes (double close, close during init, close during a query)
/// lives entirely inside `SQLiteClient`'s internals
/// (`destroyPool`/`_closeFileSystem`/`_initializeImpl`). Testing the wrapper
/// on top would assert the exact same thing through an extra layer of
/// indirection.
///
/// `@Retry(0)`: dart_test.yaml sets `retry: 2` package-wide for Chrome (for
/// occasional browser-launch flakiness), but a retry on a lifecycle
/// regression here would be exactly the wrong outcome — a real race
/// condition failing once and then passing on retry must show up as a
/// failure, not get silently absorbed.
@TestOn('browser')
@Retry(0)
library;

import 'package:test/test.dart';

import 'worker_harness.dart';

/// Storage-mode-specific bug-repro + cleanup actions, parameterizing the
/// shared scenario bodies below over 'opfs' and 'indexedDb'.
class _StorageMode {
  final String name;
  final String writeCloseDeleteAction;
  final String deleteAction;

  const _StorageMode({
    required this.name,
    required this.writeCloseDeleteAction,
    required this.deleteAction,
  });

  static const opfs = _StorageMode(
    name: 'opfs',
    writeCloseDeleteAction: 'opfsWriteCloseDelete',
    deleteAction: 'deleteOpfsStorage',
  );

  static const indexedDb = _StorageMode(
    name: 'indexedDb',
    writeCloseDeleteAction: 'indexedDbWriteCloseDelete',
    deleteAction: 'deleteIndexedDb',
  );
}

int _fileCounter = 0;

/// A filename unique to this test run/scenario. OPFS and IndexedDB storage
/// is per-origin and outlives a single test (same localhost:port for the
/// whole `dart test` run), so reusing a name across tests would make close()
/// timing bugs order-dependent instead of deterministic.
String _uniqueFilename(String tag) =>
    'knex-sqlite-$tag-${DateTime.now().microsecondsSinceEpoch}-${_fileCounter++}';

void main() {
  test('sanity: dedicated worker spawns and responds', () async {
    final harness = WorkerHarness.spawn();
    addTearDown(harness.dispose);

    expect(await harness.callOk('ping'), 'pong');
    // A stray uncaught error from the worker can arrive a microtask after
    // the reply that answered this call — pump before asserting the list is
    // empty, everywhere in this file, so that assertion is actually load-
    // bearing instead of racing the very thing it's checking for.
    await pumpEventQueue();
    expect(harness.uncaughtWorkerErrors, isEmpty);
  });

  for (final mode in [_StorageMode.opfs, _StorageMode.indexedDb]) {
    group(mode.name, () {
      late WorkerHarness harness;
      late String filename;

      setUp(() {
        harness = WorkerHarness.spawn();
        filename = _uniqueFilename(mode.name);
      });

      tearDown(() async {
        // Best-effort: if a test leaves storage in a state the worker can't
        // clean up itself (e.g. it crashed), don't let that mask the actual
        // assertion failure or leak into later tests.
        try {
          await harness.call(mode.deleteAction, {'filename': filename});
        } on Object {
          // ignored — some scenarios already delete as part of the test.
        }
        await harness.dispose();
      });

      test(
        'write -> close -> delete succeeds (issue #18 repro, fixed)',
        () async {
          final result = await harness.callOk(mode.writeCloseDeleteAction, {
            'filename': filename,
          });
          expect(result, {'deleted': true});
          await pumpEventQueue();
          expect(harness.uncaughtWorkerErrors, isEmpty);
        },
      );

      test(
        'two concurrent close() calls: no throw, no double-release, '
        'storage still deletable after',
        () async {
          final result =
              await harness.callOk('doubleClose', {
                    'filename': filename,
                    'storageMode': mode.name,
                  })
                  as Map<String, dynamic>;
          expect(
            result['isClosed'],
            isTrue,
            reason: 'client must report closed after Future.wait([close(), '
                'close()])',
          );
          await pumpEventQueue();
          expect(
            harness.uncaughtWorkerErrors,
            isEmpty,
            reason: 'neither close() call may raise or leak an uncaught '
                'error',
          );

          // The real point of the test: storage must not be left locked by
          // a handle that only one of the two close() calls released.
          await harness.callOk(mode.deleteAction, {'filename': filename});
        },
      );

      test(
        'close() called before initialize() is ever awaited (pending-init '
        'window): no uncaught error, storage still deletable after',
        () async {
          final result =
              await harness.callOk('closeDuringInit', {
                    'filename': filename,
                    'storageMode': mode.name,
                  })
                  as Map<String, dynamic>;
          expect(result['isClosed'], isTrue);
          // Both futures are awaited with their own try/catch inside the
          // worker (see opfs_worker.dart._closeDuringInit) specifically so a
          // thrown error here surfaces as a *value* (initError/closeError)
          // instead of an uncaught worker-side exception. Neither should
          // actually be set: initialize() should complete successfully
          // (destroyPool()'s `await initialize()` shares the same pending
          // future, so close() waits for init to finish rather than
          // interrupting it — see PR description for the full trace) and
          // close() should complete cleanly afterwards.
          expect(result['initError'], isNull, reason: result.toString());
          expect(result['closeError'], isNull, reason: result.toString());
          await pumpEventQueue();
          expect(harness.uncaughtWorkerErrors, isEmpty);

          await harness.callOk(mode.deleteAction, {'filename': filename});
        },
      );

      test(
        'close() called while a write query is in flight: no corruption, '
        'no uncaught error',
        () async {
          final result =
              await harness.callOk('closeDuringQuery', {
                    'filename': filename,
                    'storageMode': mode.name,
                  })
                  as Map<String, dynamic>;
          expect(result['isClosed'], isTrue);
          // Acceptable outcomes per the task's own bar: either the in-flight
          // query completes before teardown reaches it (queryError is null —
          // this is what's actually observed: _ensureDb's `await
          // initialize()` and destroyPool's `await initialize()` both
          // resolve off the same already-completed future, and since the
          // query's await was scheduled first, Dart's FIFO microtask queue
          // runs its continuation — which finishes the fully-synchronous
          // prepare/execute — before destroyPool's finally block ever runs),
          // or it's cut off with a clean StateError. What's never acceptable
          // is a hang (the harness's per-call timeout would have already
          // failed the test above) or an uncaught error (asserted below).
          if (result['queryError'] != null) {
            expect(result['queryError'], contains('StateError'));
          }
          await pumpEventQueue();
          expect(harness.uncaughtWorkerErrors, isEmpty);

          await harness.callOk(mode.deleteAction, {'filename': filename});
        },
      );
    });
  }
}
