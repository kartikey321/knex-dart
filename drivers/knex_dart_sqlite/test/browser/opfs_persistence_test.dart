/// Browser regression test for issue #35 — a named OPFS database losing every
/// row on close and reopen.
///
/// `SimpleOpfsFileSystem` persists exactly two paths, `/database` and
/// `/database-journal`, and its `xOpen` falls through to an in-memory overlay
/// for anything else. The driver used the caller's filename as *both* the OPFS
/// directory and the sqlite path, so the sqlite path was never one of those
/// two: `CREATE TABLE` and `INSERT` reported success and the data was gone on
/// the next open. Nothing raised, nothing warned.
///
/// This has to run in a real dedicated Web Worker — `SimpleOpfsFileSystem` is
/// unavailable on a tab's main thread and in shared workers — which is why it
/// drives the worker RPC in opfs_worker.dart rather than calling the driver
/// directly. A unit test cannot observe this bug at all.
///
/// Before running (see tool/):
///   dart run tool/download_wasm.dart
///   dart run tool/build_browser_worker.dart
///   dart test test/browser/ --platform=chrome
@TestOn('browser')
@Retry(0)
library;

import 'package:test/test.dart';

import 'worker_harness.dart';

int _counter = 0;

String _uniqueName(String tag) =>
    'knex-sqlite-$tag-${DateTime.now().microsecondsSinceEpoch}-${_counter++}';

void main() {
  group('OPFS persistence across close/reopen', () {
    late WorkerHarness harness;
    final created = <String>[];

    setUp(() {
      harness = WorkerHarness.spawn();
    });

    tearDown(() async {
      for (final name in created) {
        // Best-effort: a failed assertion must not leave OPFS directories
        // behind for the next run to trip over.
        try {
          await harness.call('deleteOpfsStorage', {'filename': name});
        } on Object {
          // ignore
        }
      }
      created.clear();
      await harness.dispose();
    });

    test('a row written before close is still there after reopen', () async {
      final name = _uniqueName('reopen');
      created.add(name);

      final result =
          await harness.callOk('opfsReopenPersists', {'filename': name})
              as Map<Object?, Object?>;

      expect(
        result['values'],
        ['persisted'],
        reason: 'an empty list is the original bug: the write went to '
            'SimpleOpfsFileSystem\'s in-memory overlay and was dropped on '
            'close, because the opened sqlite path was not /database',
      );
      expect(harness.uncaughtWorkerErrors, isEmpty);
    });

    test('a database opened with no storageMode persists', () async {
      // Omitting webStorageMode used to mean `memory`: the write succeeded and
      // was gone on the next open, with nothing to indicate the database was
      // never persistent. The default is now `auto`.
      final name = _uniqueName('default-mode');
      created.add(name);

      final result =
          await harness.callOk('defaultModePersists', {'filename': name})
              as Map<Object?, Object?>;

      expect(
        result['values'],
        ['default'],
        reason: 'an empty list means the default storage mode is still giving '
            'a non-persistent database for a named file',
      );
      expect(harness.uncaughtWorkerErrors, isEmpty);
    });

    test('two differently-named databases stay isolated', () async {
      // Every name now opens the same fixed sqlite path, so isolation rests
      // on each name getting its own OPFS directory. Assert it.
      final first = _uniqueName('iso-a');
      final second = _uniqueName('iso-b');
      created.addAll([first, second]);

      final result = await harness.callOk('opfsNamesIsolated', {
        'filename': first,
        'filenameB': second,
      }) as Map<Object?, Object?>;

      expect(result['first'], ['first']);
      expect(result['second'], ['second']);
      expect(harness.uncaughtWorkerErrors, isEmpty);
    });
  });
}
