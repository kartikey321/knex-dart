/// Main-thread side of the dedicated-worker RPC used by the OPFS/IndexedDB
/// browser tests (see opfs_worker.dart for the protocol and worker side).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart';

/// Spawns test/browser/opfs_worker.dart (pre-compiled to JS — see
/// tool/build_browser_worker.dart) as a real dedicated Worker and exposes an
/// RPC-style [call] API over postMessage.
class WorkerHarness {
  final Worker _worker;

  /// Absolute URL to this package's root as served by `dart test`'s browser
  /// static server for the current test run.
  ///
  /// `dart test --platform=chrome` serves each browser test page at a
  /// per-run, hash-prefixed URL that mirrors the test file's path under the
  /// package root — e.g. a page compiled from `test/browser/foo_test.dart`
  /// is served at `http://host:port/<hash>/test/browser/foo_test.html`.
  /// There is no stable `/packages/<name>/...` route for non-Dart assets
  /// (unlike a real pub/Flutter web app) — that only exists for a page
  /// loaded via `custom_html_template_path`, which this harness doesn't use.
  /// So instead this walks the current page's own URL back to the segment
  /// right before the first `test` path component, which is package root for
  /// any test file under `test/**`.
  static String packageRootUrl() {
    final location = Uri.parse(window.location.href);
    final segments = location.pathSegments;
    final testIndex = segments.indexOf('test');
    if (testIndex < 0) {
      throw StateError(
        'Could not locate package root from test page URL '
        '"${location.toString()}" (no "test" path segment found).',
      );
    }
    final rootSegments = segments.sublist(0, testIndex);
    return '${location.origin}/${rootSegments.join('/')}/';
  }

  static String get _workerUrl =>
      '${packageRootUrl()}lib/web_assets/opfs_worker.dart.js';

  /// Absolute URL to the vendored sqlite3.wasm binary, passed to the worker
  /// explicitly (rather than having the worker guess its own path) since the
  /// worker's own script URL lives under the same per-run hash but the
  /// worker has no reason to re-derive it independently.
  static String get wasmUrl =>
      '${packageRootUrl()}lib/web_assets/sqlite3.wasm';

  final _pending = <String, Completer<Map<String, dynamic>>>{};

  /// Messages the worker reported via its `runZonedGuarded` error handler —
  /// i.e. errors that escaped the per-request try/catch entirely. A clean
  /// test run must leave this empty.
  final List<Map<String, dynamic>> uncaughtWorkerErrors = [];

  late final StreamSubscription<MessageEvent> _messageSub;
  late final StreamSubscription<Event> _errorSub;
  int _counter = 0;
  Object? _fatalWorkerError;

  WorkerHarness._(this._worker) {
    _messageSub = EventStreamProviders.messageEvent
        .forTarget(_worker)
        .listen(_onMessage);
    _errorSub = EventStreamProviders.errorEvent
        .forTarget(_worker)
        .listen(_onWorkerError);
  }

  /// Spawns a fresh dedicated worker. Each test should spawn its own so a
  /// crash or hang in one test can't bleed into the next.
  factory WorkerHarness.spawn() {
    final worker = Worker(
      _workerUrl.toJS,
      WorkerOptions(name: 'knex-sqlite-opfs-test-worker'),
    );
    return WorkerHarness._(worker);
  }

  void _onMessage(MessageEvent event) {
    final raw = (event.data as JSString).toDart;
    final message = jsonDecode(raw) as Map<String, dynamic>;
    final id = message['id'] as String;

    if (id.endsWith('.uncaught')) {
      uncaughtWorkerErrors.add(message);
      // The original request this uncaught error was attributed to may still
      // be pending forever (the scenario never replied on the happy path) —
      // fail it now rather than let the test hang until the call timeout.
      final originalId = id.substring(0, id.length - '.uncaught'.length);
      final completer = _pending.remove(originalId);
      completer?.completeError(
        StateError('Uncaught error in worker: ${message['error']}'),
      );
      return;
    }

    final completer = _pending.remove(id);
    // No pending completer for a normal (non-.uncaught) reply should never
    // happen given the request/response protocol; surfacing via print (rather
    // than silently dropping) makes a protocol bug visible in test output.
    if (completer == null) {
      // ignore: avoid_print
      print('WorkerHarness: reply for unknown request id "$id": $message');
      return;
    }
    completer.complete(message);
  }

  void _onWorkerError(Event event) {
    _fatalWorkerError = event;
    var detail = 'Dedicated worker raised an ErrorEvent';
    if (event.isA<ErrorEvent>()) {
      final errorEvent = event as ErrorEvent;
      detail =
          '$detail: message="${errorEvent.message}" '
          'filename="${errorEvent.filename}" lineno=${errorEvent.lineno}';
    }
    // A blank message/filename above (browsers sanitize load-failure detail)
    // most commonly means lib/web_assets/opfs_worker.dart.js doesn't exist or
    // is stale — fail loudly with the fix rather than let this present as an
    // opaque hang or a generic "Worker already failed" from every call site.
    detail =
        '$detail\nIf this worker never loaded at all, run '
        '`dart run tool/build_browser_worker.dart` (and '
        '`dart run tool/download_wasm.dart` for sqlite3.wasm) first.';
    final error = StateError(detail);
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();
  }

  /// Sends [action] with [params] to the worker and awaits its reply.
  ///
  /// Fails (rather than hanging for the whole suite timeout) if the worker
  /// doesn't reply within [timeout], which keeps a genuinely hung scenario
  /// from being indistinguishable from "still running" in CI output.
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> params = const {},
    Duration timeout = const Duration(seconds: 15),
  ]) {
    if (_fatalWorkerError != null) {
      return Future.error(
        StateError('Worker already failed with $_fatalWorkerError'),
      );
    }
    final id = 'req-${_counter++}';
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    // Every action that opens a SQLiteClient needs wasmUri; harmless to pass
    // it to actions that don't (ping, deleteOpfsStorage, deleteIndexedDb).
    // Callers can still override it explicitly via params.
    final fullParams = {'wasmUri': wasmUrl, ...params};
    _worker.postMessage(
      jsonEncode({'id': id, 'action': action, 'params': fullParams}).toJS,
    );
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException(
          'Worker call "$action" (id $id) timed out after $timeout',
        );
      },
    );
  }

  /// Calls [action] and returns its `result` payload, throwing a descriptive
  /// [StateError] if the worker reported `ok: false`.
  Future<Object?> callOk(
    String action, [
    Map<String, dynamic> params = const {},
  ]) async {
    final response = await call(action, params);
    if (response['ok'] != true) {
      throw StateError(
        'Worker action "$action" failed: ${response['error']}\n'
        '${response['stack']}',
      );
    }
    return response['result'];
  }

  Future<void> dispose() async {
    await _messageSub.cancel();
    await _errorSub.cancel();
    _worker.terminate();
  }
}
