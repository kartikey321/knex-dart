/// Dedicated-worker entrypoint for the OPFS/IndexedDB handle-leak browser
/// tests.
///
/// [SimpleOpfsFileSystem] (package:sqlite3's OPFS VFS) only works inside a
/// dedicated Web Worker, not in a tab's main JS context — see the class doc
/// comment in sqlite3's `lib/src/wasm/vfs/simple_opfs.dart`. This file is
/// compiled to JS (via `dart compile js`, see tool/build_browser_worker.dart)
/// and loaded as a real `Worker` from the main test context (see
/// worker_harness.dart), so the scenarios below actually exercise
/// SimpleOpfsFileSystem/IndexedDbFileSystem the way a real caller would.
///
/// Protocol: the main thread posts a JSON-encoded string
/// `{id, action, params}`; this worker replies with a JSON-encoded string
/// `{id, ok, result?, error?, stack?}`. Every action that opens a client
/// expects `params['wasmUri']` — an absolute URL to sqlite3.wasm — because
/// this worker has no reliable way to derive its own script location's
/// package root independently (see WorkerHarness.wasmUrl for how the main
/// thread computes it). One request is handled at a time in the order
/// received (this file does not pipeline).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:knex_dart/knex_dart.dart';
import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';
import 'package:sqlite3/wasm.dart';
import 'package:web/web.dart';

late final DedicatedWorkerGlobalScope _scope;

void main() {
  _scope = globalContext as DedicatedWorkerGlobalScope;
  _scope.onmessage = ((MessageEvent event) {
    final raw = (event.data as JSString).toDart;
    // Handle each request in its own async zone so a scenario that never
    // completes (e.g. a hung close()) doesn't block later requests, and so
    // uncaught async errors are captured and reported instead of becoming
    // silent worker-global exceptions the test can't observe.
    unawaited(_handle(raw));
  }).toJS;
}

Future<void> _handle(String raw) async {
  final request = jsonDecode(raw) as Map<String, dynamic>;
  final id = request['id'] as String;
  final action = request['action'] as String;
  final params = (request['params'] as Map<String, dynamic>?) ?? const {};

  await runZonedGuarded(
    () async {
      try {
        final result = await _dispatch(action, params);
        _reply({'id': id, 'ok': true, 'result': result});
      } on Object catch (e, st) {
        _reply({
          'id': id,
          'ok': false,
          'error': e.toString(),
          'stack': st.toString(),
        });
      }
    },
    (error, stack) {
      // Caught here means it escaped the try/catch above (e.g. thrown from a
      // callback/microtask after the awaited call already returned) — report
      // it under a distinct id (rather than dropping it) so the test can
      // assert "no uncaught error" instead of the failure silently vanishing
      // into the worker's global error handler.
      _reply({
        'id': '$id.uncaught',
        'ok': false,
        'error': error.toString(),
        'stack': stack.toString(),
      });
    },
  );
}

void _reply(Map<String, dynamic> message) {
  _scope.postMessage(jsonEncode(message).toJS);
}

Future<Object?> _dispatch(String action, Map<String, dynamic> params) async {
  switch (action) {
    case 'ping':
      return 'pong';

    case 'defaultModePersists':
      return _defaultModePersists(
        params['filename'] as String,
        params['wasmUri'] as String,
      );

    case 'opfsReopenPersists':
      return _opfsReopenPersists(
        params['filename'] as String,
        params['wasmUri'] as String,
      );

    case 'opfsNamesIsolated':
      return _opfsNamesIsolated(
        params['filename'] as String,
        params['filenameB'] as String,
        params['wasmUri'] as String,
      );

    case 'opfsWriteCloseDelete':
      return _opfsWriteCloseDelete(
        params['filename'] as String,
        params['wasmUri'] as String,
      );

    case 'indexedDbWriteCloseDelete':
      return _indexedDbWriteCloseDelete(
        params['filename'] as String,
        params['wasmUri'] as String,
      );

    case 'doubleClose':
      return _doubleClose(
        params['filename'] as String,
        params['storageMode'] as String,
        params['wasmUri'] as String,
      );

    case 'closeDuringInit':
      return _closeDuringInit(
        params['filename'] as String,
        params['storageMode'] as String,
        params['wasmUri'] as String,
      );

    case 'closeDuringQuery':
      return _closeDuringQuery(
        params['filename'] as String,
        params['storageMode'] as String,
        params['wasmUri'] as String,
      );

    case 'deleteOpfsStorage':
      await SimpleOpfsFileSystem.deleteFromStorage(
        params['filename'] as String,
      );
      return null;

    case 'deleteIndexedDb':
      await IndexedDbFileSystem.deleteDatabase(params['filename'] as String);
      return null;

    default:
      throw StateError('Unknown action "$action"');
  }
}

SQLiteClient _client(String filename, String storageMode, String wasmUri) {
  return SQLiteClient.fromConfig(
    KnexConfig(
      client: 'sqlite3',
      connection: {
        'filename': filename,
        'storageMode': storageMode,
        'wasmUri': wasmUri,
      },
    ),
  );
}

/// Opens with **no** `storageMode` at all, writes, closes, reopens, reads back.
///
/// The default used to be `memory`, so `connect(filename: 'app.db')` on web
/// handed back a database that looked persistent and discarded everything on
/// close — the same silent non-persistence as the OPFS bug, reached by
/// omission rather than by a broken path. The default is now `auto` for any
/// filename other than `:memory:`.
Future<Map<String, dynamic>> _defaultModePersists(
  String filename,
  String wasmUri,
) async {
  SQLiteClient open() => SQLiteClient.fromConfig(
    KnexConfig(
      client: 'sqlite3',
      connection: {'filename': filename, 'wasmUri': wasmUri},
    ),
  );

  var client = open();
  await client.initialize();
  await client.rawQuery('CREATE TABLE probe (value TEXT)', const []);
  await client.rawQuery('INSERT INTO probe (value) VALUES (?)', ['default']);
  await client.close();

  client = open();
  await client.initialize();
  final rows = await client.rawQuery('SELECT value FROM probe', const []);
  await client.close();

  return {'values': _values(rows)};
}

/// Writes a row, closes, reopens the SAME named database and reads it back.
///
/// Before the fix this came back empty. The driver opened
/// `sqlite.open(_filename)`, but `SimpleOpfsFileSystem` persists only
/// `/database` and `/database-journal` and silently serves every other path
/// from an in-memory overlay — so the CREATE and INSERT both succeeded and
/// were discarded on close. Issue #35.
Future<Map<String, dynamic>> _opfsReopenPersists(
  String filename,
  String wasmUri,
) async {
  var client = _client(filename, 'opfs', wasmUri);
  await client.initialize();
  await client.rawQuery('CREATE TABLE probe (value TEXT)', const []);
  await client.rawQuery('INSERT INTO probe (value) VALUES (?)', ['persisted']);
  await client.close();

  client = _client(filename, 'opfs', wasmUri);
  await client.initialize();
  final rows = await client.rawQuery('SELECT value FROM probe', const []);
  await client.close();

  return {'values': _values(rows)};
}

/// Two differently-named OPFS databases must not see each other's rows.
///
/// The fix opens the fixed path `/database` for every name, so the isolation
/// now rests entirely on `loadFromStorage(name)` giving each name its own
/// OPFS directory. That is worth asserting rather than assuming.
Future<Map<String, dynamic>> _opfsNamesIsolated(
  String filename,
  String filenameB,
  String wasmUri,
) async {
  Future<void> seed(String name, String value) async {
    final client = _client(name, 'opfs', wasmUri);
    await client.initialize();
    await client.rawQuery('CREATE TABLE probe (value TEXT)', const []);
    await client.rawQuery('INSERT INTO probe (value) VALUES (?)', [value]);
    await client.close();
  }

  Future<List<String>> read(String name) async {
    final client = _client(name, 'opfs', wasmUri);
    await client.initialize();
    final rows = await client.rawQuery('SELECT value FROM probe', const []);
    await client.close();
    return _values(rows);
  }

  await seed(filename, 'first');
  await seed(filenameB, 'second');
  return {'first': await read(filename), 'second': await read(filenameB)};
}

List<String> _values(Object? rows) => [
  for (final row in (rows as List).cast<Map<String, dynamic>>())
    row['value'] as String,
];

Future<Map<String, dynamic>> _opfsWriteCloseDelete(
  String filename,
  String wasmUri,
) async {
  final client = _client(filename, 'opfs', wasmUri);
  await client.initialize();
  await client.rawQuery('CREATE TABLE t (id INTEGER)', const []);
  await client.rawQuery('INSERT INTO t (id) VALUES (1)', const []);
  await client.close();

  // Before the fix, this throws NoModificationAllowedError because the
  // SimpleOpfsFileSystem's FileSystemSyncAccessHandles were never closed.
  await SimpleOpfsFileSystem.deleteFromStorage(filename);
  return {'deleted': true};
}

Future<Map<String, dynamic>> _indexedDbWriteCloseDelete(
  String filename,
  String wasmUri,
) async {
  final client = _client(filename, 'indexedDb', wasmUri);
  await client.initialize();
  await client.rawQuery('CREATE TABLE t (id INTEGER)', const []);
  await client.rawQuery('INSERT INTO t (id) VALUES (1)', const []);
  await client.close();

  // Before the fix, this throws StateError('IndexedDB open blocked') because
  // the IndexedDbFileSystem's IDBDatabase connection was never closed.
  await IndexedDbFileSystem.deleteDatabase(filename);
  return {'deleted': true};
}

Future<Map<String, dynamic>> _doubleClose(
  String filename,
  String storageMode,
  String wasmUri,
) async {
  final client = _client(filename, storageMode, wasmUri);
  await client.initialize();
  await client.rawQuery('CREATE TABLE t (id INTEGER)', const []);

  await Future.wait([client.close(), client.close()]);

  return {'isClosed': client.isClosed};
}

Future<Map<String, dynamic>> _closeDuringInit(
  String filename,
  String storageMode,
  String wasmUri,
) async {
  // Construct + close in the same synchronous prologue, before initialize()
  // is ever awaited, to hit the "closed mid-init" window. connect() cannot
  // express this because it awaits initialize() internally before returning
  // the client — this is the only realistic surface: fromConfig() followed
  // by an un-awaited initialize() is a real caller shape (e.g. a UI layer
  // that kicks off connection setup and lets the user navigate away/cancel
  // before it settles).
  final client = _client(filename, storageMode, wasmUri);
  final initFuture = client.initialize();
  final closeFuture = client.close();

  Object? initError;
  Object? closeError;
  try {
    await initFuture;
  } on Object catch (e) {
    initError = e;
  }
  try {
    await closeFuture;
  } on Object catch (e) {
    closeError = e;
  }

  // A query issued after this race must fail with an accurate "is closed"
  // error, not the misleading "failed to initialize" message _ensureDb()
  // used to give when _db was left null by the early-return branch inside
  // _initializeImpl() rather than by a genuine init failure.
  Object? queryAfterCloseError;
  try {
    await client.rawQuery('SELECT 1', const []);
  } on Object catch (e) {
    queryAfterCloseError = e;
  }

  return {
    'isClosed': client.isClosed,
    'initError': initError?.toString(),
    'closeError': closeError?.toString(),
    'queryAfterCloseError': queryAfterCloseError?.toString(),
  };
}

Future<Map<String, dynamic>> _closeDuringQuery(
  String filename,
  String storageMode,
  String wasmUri,
) async {
  final client = _client(filename, storageMode, wasmUri);
  await client.initialize();
  await client.rawQuery('CREATE TABLE t (id INTEGER)', const []);

  final queryFuture = client.rawQuery(
    'INSERT INTO t (id) VALUES (1)',
    const [],
  );
  final closeFuture = client.close();

  Object? queryError;
  Object? closeError;
  try {
    await queryFuture;
  } on Object catch (e) {
    queryError = e;
  }
  try {
    await closeFuture;
  } on Object catch (e) {
    closeError = e;
  }

  return {
    'isClosed': client.isClosed,
    'queryError': queryError?.toString(),
    'closeError': closeError?.toString(),
  };
}
