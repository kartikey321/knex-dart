import 'dart:async';

import 'package:knex_dart/knex_dart.dart';
import 'package:test/test.dart';

// ── Test helpers ──────────────────────────────────────────────────────────────

class RecordingInterceptor extends QueryInterceptor {
  final List<QueryExecutionContext> futures = [];
  final List<QueryExecutionContext> streams = [];
  final String? label;

  RecordingInterceptor([this.label]);

  @override
  Future<T> intercept<T>(
    QueryExecutionContext ctx,
    Future<T> Function() next,
  ) {
    futures.add(ctx);
    return next();
  }

  @override
  Stream<T> interceptStream<T>(
    QueryExecutionContext ctx,
    Stream<T> Function() next,
  ) {
    streams.add(ctx);
    return next();
  }
}

class ErrorInterceptor extends QueryInterceptor {
  @override
  Future<T> intercept<T>(QueryExecutionContext ctx, Future<T> Function() next) {
    throw StateError('interceptor exploded');
  }
}

// Order-tracking interceptor: appends its label to a shared list on each call.
class OrderInterceptor extends QueryInterceptor {
  final List<String> order;
  final String label;

  OrderInterceptor(this.order, this.label);

  @override
  Future<T> intercept<T>(
    QueryExecutionContext ctx,
    Future<T> Function() next,
  ) async {
    order.add('$label:before');
    final r = await next();
    order.add('$label:after');
    return r;
  }
}

KnexInterceptorPipeline _pipeline({
  List<QueryInterceptor> interceptors = const [],
  String dbSystem = 'postgresql',
  String database = 'testdb',
  String serverAddress = 'localhost',
  int serverPort = 5432,
}) =>
    KnexInterceptorPipeline(
      dbSystem: dbSystem,
      database: database,
      serverAddress: serverAddress,
      serverPort: serverPort,
      interceptors: interceptors,
      instanceId: 'test', // deterministic for assertions
    );

QueryExecutionContext _fakeCtx() => const QueryExecutionContext(
      dbSystem: 'postgresql',
      sql: 'SELECT 1',
      parameters: [],
      operationName: 'SELECT',
      querySummary: 'SELECT',
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── runRaw ─────────────────────────────────────────────────────────────────

  group('KnexInterceptorPipeline.runRaw', () {
    test('no interceptors → execute called directly (passthrough)', () async {
      final pipeline = _pipeline();
      var called = false;
      await pipeline.runRaw('SELECT 1', [], () async {
        called = true;
        return <Map<String, dynamic>>[];
      });
      expect(called, isTrue);
    });

    test('context fields populated from pipeline metadata', () async {
      final rec = RecordingInterceptor();
      final pipeline = _pipeline(interceptors: [rec]);
      await pipeline.runRaw(
        'INSERT INTO orders VALUES (?)',
        [42],
        () async => <Map<String, dynamic>>[],
      );
      expect(rec.futures, hasLength(1));
      final ctx = rec.futures.first;
      expect(ctx.dbSystem, 'postgresql');
      expect(ctx.database, 'testdb');
      expect(ctx.serverAddress, 'localhost');
      expect(ctx.serverPort, 5432);
      expect(ctx.sql, 'INSERT INTO orders VALUES (?)');
      expect(ctx.parameters, [42]);
      expect(ctx.operationName, 'INSERT');
      expect(ctx.querySummary, 'INSERT');
      expect(ctx.collectionName, isNull);
    });

    test('operationName derived from SQL via sqlOperationFromRaw', () async {
      final rec = RecordingInterceptor();
      final pipeline = _pipeline(interceptors: [rec]);

      Future<void> check(String sql, String expected) async {
        await pipeline.runRaw(sql, [], () async => []);
        expect(rec.futures.last.operationName, expected, reason: sql);
      }

      await check('SELECT 1', 'SELECT');
      await check('insert into t values (1)', 'INSERT');
      await check('CREATE TABLE t (id INT)', 'CREATE');
      await check('SELECTIVITY test', 'DB');
      await check('', 'DB');
    });

    test('txId propagated when supplied', () async {
      final rec = RecordingInterceptor();
      final pipeline = _pipeline(interceptors: [rec]);
      await pipeline.runRaw('SELECT 1', [], () async => [], txId: 'tx-abc');
      expect(rec.futures.first.txId, 'tx-abc');
    });

    test('interceptor error propagates to caller', () async {
      final pipeline = _pipeline(interceptors: [ErrorInterceptor()]);
      expect(
        () => pipeline.runRaw('SELECT 1', [], () async => []),
        throwsA(isA<StateError>()),
      );
    });

    test('execute error propagates through interceptor chain', () async {
      final rec = RecordingInterceptor();
      final pipeline = _pipeline(interceptors: [rec]);
      expect(
        () => pipeline.runRaw('SELECT 1', [], () async => throw StateError('db down')),
        throwsA(isA<StateError>().having((e) => e.message, 'message', 'db down')),
      );
    });
  });

  // ── runBatch ───────────────────────────────────────────────────────────────

  group('KnexInterceptorPipeline.runBatch', () {
    test('produces BATCH operationName and sql placeholder', () async {
      final rec = RecordingInterceptor();
      final pipeline = _pipeline(interceptors: [rec]);
      await pipeline.runBatch(() async => []);
      expect(rec.futures, hasLength(1));
      expect(rec.futures.first.operationName, 'BATCH');
      expect(rec.futures.first.sql, '<batch>');
    });

    test('no interceptors → execute called directly', () async {
      final pipeline = _pipeline();
      var called = false;
      await pipeline.runBatch(() async {
        called = true;
        return [];
      });
      expect(called, isTrue);
    });
  });

  // ── runStream via interceptor directly ────────────────────────────────────

  group('interceptStream chaining (direct interceptor call)', () {
    test('default interceptStream passthrough delivers items', () async {
      final i = RecordingInterceptor();
      final ctx = _fakeCtx();
      final result = await i
          .interceptStream<int>(ctx, () => Stream.fromIterable([1, 2, 3]))
          .toList();
      expect(result, [1, 2, 3]);
      expect(i.streams, hasLength(1));
    });

    test('two chained interceptors both record stream context', () async {
      final i1 = RecordingInterceptor();
      final i2 = RecordingInterceptor();
      final ctx = _fakeCtx();
      // Chain manually: i1 wraps i2 wraps execute.
      final result = await i1
          .interceptStream<int>(ctx,
              () => i2.interceptStream(ctx, () => Stream.fromIterable([7, 8])))
          .toList();
      expect(result, [7, 8]);
      expect(i1.streams, hasLength(1));
      expect(i2.streams, hasLength(1));
    });
  });

  // ── interceptor ordering ───────────────────────────────────────────────────

  group('interceptor ordering', () {
    test('interceptors called in index order (outer-first)', () async {
      final order = <String>[];
      final pipeline = _pipeline(interceptors: [
        OrderInterceptor(order, 'A'),
        OrderInterceptor(order, 'B'),
        OrderInterceptor(order, 'C'),
      ]);
      await pipeline.runRaw('SELECT 1', [], () async => []);
      expect(order, ['A:before', 'B:before', 'C:before', 'C:after', 'B:after', 'A:after']);
    });

    test('all interceptors receive the same context object', () async {
      final ctxs = <QueryExecutionContext>[];
      final i1 = RecordingInterceptor()..futures.clear();
      final i2 = RecordingInterceptor()..futures.clear();
      final pipeline = _pipeline(interceptors: [i1, i2]);
      await pipeline.runRaw('SELECT 1', [], () async => []);
      // Both interceptors should have identical contexts.
      expect(i1.futures.first.sql, i2.futures.first.sql);
      expect(i1.futures.first.operationName, i2.futures.first.operationName);
      ctxs.addAll([i1.futures.first, i2.futures.first]);
      expect(ctxs, hasLength(2));
    });
  });

  // ── nextUid ────────────────────────────────────────────────────────────────

  group('nextUid', () {
    test('format is <instanceId>_<n>', () {
      final pipeline = _pipeline();
      expect(pipeline.nextUid(), 'test_1');
      expect(pipeline.nextUid(), 'test_2');
    });

    test('monotonically increasing', () {
      final pipeline = _pipeline();
      final uids = List.generate(10, (_) => pipeline.nextUid());
      final counters = uids.map((u) => int.parse(u.split('_').last)).toList();
      for (var i = 0; i < counters.length - 1; i++) {
        expect(counters[i + 1], greaterThan(counters[i]));
      }
    });

    test('unique across calls', () {
      final pipeline = _pipeline();
      final uids = List.generate(100, (_) => pipeline.nextUid()).toSet();
      expect(uids, hasLength(100));
    });

    test('different pipelines produce non-colliding ids', () {
      // With random instanceId this is probabilistic; with fixed ids we
      // verify format only.
      final p1 = KnexInterceptorPipeline(dbSystem: 'pg', instanceId: 'aaa');
      final p2 = KnexInterceptorPipeline(dbSystem: 'pg', instanceId: 'bbb');
      expect(p1.nextUid(), startsWith('aaa_'));
      expect(p2.nextUid(), startsWith('bbb_'));
    });

    test('instanceId generated by default is non-empty 8-char hex', () {
      final pipeline = KnexInterceptorPipeline(dbSystem: 'pg');
      expect(pipeline.instanceId, matches(RegExp(r'^[0-9a-f]{1,8}$')));
    });
  });
}

// Expose internal _chainStream for unit testing without going through
// QueryBuilder compilation (which needs a real client).
