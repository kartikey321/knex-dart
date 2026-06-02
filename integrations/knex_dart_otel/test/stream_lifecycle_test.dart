import 'dart:async';

import 'package:knex_dart/src/client/query_interceptor.dart';
import 'package:test/test.dart';

// ── Test interceptor that tracks stream lifecycle ─────────────────────────────

class LifecycleInterceptor extends QueryInterceptor {
  int startCount = 0;
  int doneCount = 0;
  int errorCount = 0;
  int cancelCount = 0;
  int finishCount = 0; // incremented exactly once per stream

  @override
  Future<T> intercept<T>(QueryExecutionContext ctx, Future<T> Function() next) =>
      next();

  @override
  Stream<T> interceptStream<T>(
    QueryExecutionContext ctx,
    Stream<T> Function() next,
  ) {
    bool finished = false;
    StreamSubscription<T>? upstream;

    void finishOnce({bool isError = false, bool isCancelled = false}) {
      if (finished) return;
      finished = true;
      finishCount++;
      if (isError) {
        errorCount++;
      } else if (!isCancelled) {
        doneCount++;
      }
    }

    late StreamController<T> controller;
    controller = StreamController<T>(
      onListen: () {
        startCount++;
        upstream = next().listen(
          controller.add,
          onError: (Object e, StackTrace st) {
            finishOnce(isError: true);
            controller.addError(e, st);
          },
          onDone: () {
            finishOnce();
            controller.close();
          },
        );
      },
      onCancel: () {
        cancelCount++;
        final f = upstream?.cancel();
        if (f != null) return f.whenComplete(() => finishOnce(isCancelled: true));
        finishOnce(isCancelled: true);
      },
      onPause: () => upstream?.pause(),
      onResume: () => upstream?.resume(),
    );

    return controller.stream;
  }
}

QueryExecutionContext _ctx() => const QueryExecutionContext(
      dbSystem: 'sqlite',
      sql: 'SELECT 1',
      parameters: [],
      operationName: 'SELECT',
      querySummary: 'SELECT users',
    );

// ── Helpers for controlled streams ────────────────────────────────────────────

Stream<int> _finiteStream(List<int> items) => Stream.fromIterable(items);

Stream<int> _errorStream() => Stream<int>.error(StateError('db error'));

Stream<int> _periodicStream() =>
    Stream.periodic(const Duration(milliseconds: 10), (i) => i);

// ── Tests ─────────────────────────────────────────────────────────────────────

// Helper: run ctx through a single LifecycleInterceptor.
Stream<T> _run<T>(
  LifecycleInterceptor interceptor,
  QueryExecutionContext ctx,
  Stream<T> Function() source,
) =>
    interceptor.interceptStream(ctx, source);

void main() {
  group('Stream lifecycle — finishOnce guard and lifecycle events', () {
    late LifecycleInterceptor interceptor;

    setUp(() {
      interceptor = LifecycleInterceptor();
    });

    // ── Normal completion ───────────────────────────────────────────────────

    // Key invariant: finishOnce fires exactly once and marks done=1, error=0.
    // cancelCount may be non-zero due to Dart StreamController teardown
    // semantics (onCancel can fire after natural close); finishOnce guards it.
    test('normal completion: start=1, done=1, finish=1, error=0', () async {
      final ctx = _ctx();
      await _run(interceptor, ctx, () => _finiteStream([1, 2, 3])).toList();
      expect(interceptor.startCount, 1);
      expect(interceptor.doneCount, 1);
      expect(interceptor.errorCount, 0);
      expect(interceptor.finishCount, 1);
    });

    test('normal completion delivers all items', () async {
      final ctx = _ctx();
      final result =
          await _run(interceptor, ctx, () => _finiteStream([10, 20, 30])).toList();
      expect(result, [10, 20, 30]);
    });

    // ── Error path ──────────────────────────────────────────────────────────

    test('error stream: finish=1, error=1, done=0', () async {
      final ctx = _ctx();
      Object? caught;
      try {
        await _run(interceptor, ctx, () => _errorStream()).toList();
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<StateError>());
      expect(interceptor.errorCount, 1);
      expect(interceptor.doneCount, 0);
      expect(interceptor.finishCount, 1);
    });

    test('error is not swallowed — subscriber receives it', () async {
      final ctx = _ctx();
      Object? caught;
      try {
        await _run(interceptor, ctx, () => _errorStream()).toList();
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<StateError>());
    });

    // ── Cancellation path ───────────────────────────────────────────────────

    test('cancel after first item: finish=1, cancel=1, done=0', () async {
      final ctx = _ctx();
      late StreamSubscription<int> sub;
      sub = _run(interceptor, ctx,() => _periodicStream())
          .listen((_) => sub.cancel());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(interceptor.cancelCount, 1);
      expect(interceptor.finishCount, 1);
      expect(interceptor.doneCount, 0);
      expect(interceptor.errorCount, 0);
    });

    test('cancel on finite stream: finish=1', () async {
      final ctx = _ctx();
      // Cancel immediately before any data flows.
      final sub = _run(interceptor, ctx,() => _finiteStream([1, 2, 3]))
          .listen((_) {});
      await sub.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(interceptor.finishCount, 1);
    });

    // ── Never-listened stream ───────────────────────────────────────────────

    test('never-listened stream: start=0, finish=0 — no span leak', () async {
      final ctx = _ctx();
      // Create the stream but never subscribe.
      // ignore: unused_local_variable
      final stream = _run(interceptor, ctx, () => _finiteStream([1]));
      await Future<void>.delayed(Duration.zero);
      expect(interceptor.startCount, 0);
      expect(interceptor.finishCount, 0);
    });

    // ── finishOnce guard ────────────────────────────────────────────────────

    test('finishCount is exactly 1 even if error fires near stream close', () async {
      // Emit one error; the stream closes after it.
      final ctx = _ctx();
      await _run(interceptor, ctx,() => _errorStream())
          .listen((_) {}, onError: (_) {})
          .asFuture<void>()
          .catchError((_) {});
      await Future<void>.delayed(Duration.zero);
      // finishOnce must be called exactly once regardless.
      expect(interceptor.finishCount, 1);
    });

    // ── Multiple interceptors ───────────────────────────────────────────────

    test('two interceptors both track lifecycle independently', () async {
      final i1 = LifecycleInterceptor();
      final i2 = LifecycleInterceptor();
      final ctx = _ctx();
      // Chain: i1 wraps i2 wraps source.
      await i1
          .interceptStream(ctx, () => i2.interceptStream(ctx, () => _finiteStream([1, 2])))
          .toList();
      expect(i1.finishCount, 1);
      expect(i2.finishCount, 1);
    });
  });
}
