import 'dart:async';

import 'package:dartastic_opentelemetry_api/dartastic_opentelemetry_api.dart';
import 'package:knex_dart/knex_dart.dart';
import 'package:knex_dart_otel/knex_dart_otel.dart';
import 'package:test/test.dart';

// ── Capturing histogram ───────────────────────────────────────────────────────

class CapturingHistogram extends APIHistogram<double> {
  final List<(double value, Map<String, Object> attrs)> recordings = [];

  CapturingHistogram(APIMeter meter)
      : super('db.client.operation.duration', null, 's', true, meter);

  @override
  void record(double value, [Attributes? attributes]) {
    recordings.add((value, {}));
  }

  @override
  void recordWithMap(double value, Map<String, Object> attributeMap) {
    recordings.add((value, Map<String, Object>.from(attributeMap)));
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

QueryExecutionContext _ctx({
  String dbSystem = 'postgresql',
  String database = 'mydb',
  String serverAddress = 'localhost',
  int serverPort = 5432,
  String sql = 'select * from "users"',
  String operationName = 'SELECT',
  String? collectionName = 'users',
  String querySummary = 'SELECT users',
  String? txId,
}) =>
    QueryExecutionContext(
      dbSystem: dbSystem,
      database: database,
      serverAddress: serverAddress,
      serverPort: serverPort,
      sql: sql,
      parameters: const [],
      operationName: operationName,
      collectionName: collectionName,
      querySummary: querySummary,
      txId: txId,
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late APITracer tracer;
  late CapturingHistogram histogram;
  late KnexOtelInterceptor interceptor;

  setUp(() {
    OTelAPI.reset();
    OTelAPI.initialize(
      endpoint: 'http://localhost:4317',
      serviceName: 'knex-otel-test',
      serviceVersion: '0.0.1',
    );
    tracer = OTelAPI.tracer('knex_dart_otel_test');
    histogram = CapturingHistogram(
      OTelAPI.meterProvider().getMeter(name: 'knex_dart_otel_test'),
    );
    interceptor = KnexOtelInterceptor(
      tracer: tracer,
      operationDurationHistogram: histogram,
    );
  });

  tearDown(() => OTelAPI.reset());

  // ── intercept() — success path ────────────────────────────────────────────

  group('intercept() success path', () {
    test('span is ended after successful query', () async {
      APISpan? span;
      final i = KnexOtelInterceptor(
        tracer: tracer,
        operationDurationHistogram: histogram,
        options: KnexOtelOptions(requestHook: (s, _) => span = s),
      );
      await i.intercept<List<Map<String, dynamic>>>(
        _ctx(),
        () async => [{'id': 1}],
      );
      expect(span, isNotNull);
      expect(span!.isEnded, isTrue);
    });

    test('span name is querySummary', () async {
      APISpan? span;
      final i = KnexOtelInterceptor(
        tracer: tracer,
        operationDurationHistogram: histogram,
        options: KnexOtelOptions(requestHook: (s, _) => span = s),
      );
      await i.intercept<List<Map<String, dynamic>>>(
        _ctx(querySummary: 'SELECT users'),
        () async => [],
      );
      expect(span!.name, 'SELECT users');
    });

    test('span status is Ok on success', () async {
      APISpan? span;
      final i = KnexOtelInterceptor(
        tracer: tracer,
        operationDurationHistogram: histogram,
        options: KnexOtelOptions(requestHook: (s, _) => span = s),
      );
      await i.intercept<List<Map<String, dynamic>>>(_ctx(), () async => []);
      expect(span!.status, SpanStatusCode.Ok);
    });

    test('OTel DB semconv attributes are set', () async {
      APISpan? span;
      final i = KnexOtelInterceptor(
        tracer: tracer,
        operationDurationHistogram: histogram,
        options: KnexOtelOptions(requestHook: (s, _) => span = s),
      );
      await i.intercept<List<Map<String, dynamic>>>(
        _ctx(
          dbSystem: 'postgresql',
          database: 'mydb',
          serverAddress: 'db.local',
          serverPort: 5432,
          sql: 'select * from "users"',
          operationName: 'SELECT',
          collectionName: 'users',
        ),
        () async => [],
      );
      final attrs = span!.attributes.toJson();
      expect(attrs['db.system.name'], 'postgresql');
      expect(attrs['db.operation.name'], 'SELECT');
      expect(attrs['db.namespace'], 'mydb');
      expect(attrs['db.collection.name'], 'users');
      expect(attrs['db.query.text'], 'select * from "users"');
      expect(attrs['server.address'], 'db.local');
      expect(attrs['server.port'], 5432);
    });

    test('db.query.text not set when captureQueryText is false', () async {
      APISpan? span;
      final i = KnexOtelInterceptor(
        tracer: tracer,
        operationDurationHistogram: histogram,
        options: KnexOtelOptions(
          captureQueryText: false,
          requestHook: (s, _) => span = s,
        ),
      );
      await i.intercept<List<Map<String, dynamic>>>(_ctx(), () async => []);
      expect(span!.attributes.toJson().containsKey('db.query.text'), isFalse);
    });

    test('db.query.text truncated at maxQueryTextLength', () async {
      APISpan? span;
      final i = KnexOtelInterceptor(
        tracer: tracer,
        operationDurationHistogram: histogram,
        options: KnexOtelOptions(
          maxQueryTextLength: 10,
          requestHook: (s, _) => span = s,
        ),
      );
      await i.intercept<List<Map<String, dynamic>>>(
        _ctx(sql: 'select * from "users" where id = ?'),
        () async => [],
      );
      final text = span!.attributes.toJson()['db.query.text'] as String;
      expect(text.length, lessThanOrEqualTo(11)); // 10 chars + ellipsis
      expect(text, endsWith('…'));
    });

    test('histogram records elapsed in seconds', () async {
      await interceptor.intercept<List<Map<String, dynamic>>>(
        _ctx(),
        () async => [],
      );
      expect(histogram.recordings, hasLength(1));
      final value = histogram.recordings.first.$1;
      expect(value, greaterThanOrEqualTo(0.0));
      expect(value, lessThan(5.0)); // sanity: no test takes 5 seconds
    });

    test('histogram attributes include db.system.name and db.operation.name', () async {
      await interceptor.intercept<List<Map<String, dynamic>>>(
        _ctx(dbSystem: 'postgresql', operationName: 'INSERT'),
        () async => [],
      );
      final attrs = histogram.recordings.first.$2;
      expect(attrs['db.system.name'], 'postgresql');
      expect(attrs['db.operation.name'], 'INSERT');
    });

    test('histogram attributes include db.namespace and server.address', () async {
      await interceptor.intercept<List<Map<String, dynamic>>>(
        _ctx(database: 'orders_db', serverAddress: 'db.internal', serverPort: 5433),
        () async => [],
      );
      final attrs = histogram.recordings.first.$2;
      expect(attrs['db.namespace'], 'orders_db');
      expect(attrs['server.address'], 'db.internal');
      expect(attrs['server.port'], 5433);
    });

    test('server.port in histogram is int, not string', () async {
      await interceptor.intercept<List<Map<String, dynamic>>>(
        _ctx(serverPort: 5432),
        () async => [],
      );
      final port = histogram.recordings.first.$2['server.port'];
      expect(port, isA<int>());
      expect(port, 5432);
    });

    test('result returned unchanged to caller', () async {
      final result = await interceptor.intercept<List<Map<String, dynamic>>>(
        _ctx(),
        () async => [
          {'id': 1, 'name': 'Alice'},
          {'id': 2, 'name': 'Bob'},
        ],
      );
      expect(result, hasLength(2));
      expect(result.first['name'], 'Alice');
    });

    test('responseHook receives rowCount for List result', () async {
      KnexOtelResult? result;
      final i = KnexOtelInterceptor(
        tracer: tracer,
        operationDurationHistogram: histogram,
        options: KnexOtelOptions(
          responseHook: (span, ctx, r) => result = r,
        ),
      );
      await i.intercept<List<Map<String, dynamic>>>(
        _ctx(),
        () async => [{'id': 1}, {'id': 2}, {'id': 3}],
      );
      expect(result, isNotNull);
      expect(result!.isError, isFalse);
      expect(result!.rowCount, 3);
      expect(result!.elapsed.inMicroseconds, greaterThanOrEqualTo(0));
    });
  });

  // ── intercept() — error path ──────────────────────────────────────────────

  group('intercept() error path', () {
    test('exception is re-thrown to caller', () async {
      expect(
        () => interceptor.intercept<List<Map<String, dynamic>>>(
          _ctx(),
          () async => throw StateError('db down'),
        ),
        throwsA(isA<StateError>().having((e) => e.message, 'message', 'db down')),
      );
    });

    test('span status is Error on exception', () async {
      APISpan? span;
      final i = KnexOtelInterceptor(
        tracer: tracer,
        operationDurationHistogram: histogram,
        options: KnexOtelOptions(requestHook: (s, _) => span = s),
      );
      try {
        await i.intercept<List<Map<String, dynamic>>>(
          _ctx(),
          () async => throw StateError('fail'),
        );
      } catch (_) {}
      expect(span!.status, SpanStatusCode.Error);
    });

    test('error.type attribute set on exception', () async {
      APISpan? span;
      final i = KnexOtelInterceptor(
        tracer: tracer,
        operationDurationHistogram: histogram,
        options: KnexOtelOptions(requestHook: (s, _) => span = s),
      );
      try {
        await i.intercept<List<Map<String, dynamic>>>(
          _ctx(),
          () async => throw FormatException('bad sql'),
        );
      } catch (_) {}
      expect(span!.attributes.toJson()['error.type'], 'FormatException');
    });

    test('span is ended on exception', () async {
      APISpan? span;
      final i = KnexOtelInterceptor(
        tracer: tracer,
        operationDurationHistogram: histogram,
        options: KnexOtelOptions(requestHook: (s, _) => span = s),
      );
      try {
        await i.intercept<List<Map<String, dynamic>>>(
          _ctx(),
          () async => throw StateError('fail'),
        );
      } catch (_) {}
      expect(span!.isEnded, isTrue);
    });

    test('histogram records even on exception', () async {
      try {
        await interceptor.intercept<List<Map<String, dynamic>>>(
          _ctx(),
          () async => throw StateError('fail'),
        );
      } catch (_) {}
      expect(histogram.recordings, hasLength(1));
    });

    test('responseHook receives isError=true and error object', () async {
      KnexOtelResult? result;
      final i = KnexOtelInterceptor(
        tracer: tracer,
        operationDurationHistogram: histogram,
        options: KnexOtelOptions(
          responseHook: (span, ctx, r) => result = r,
        ),
      );
      try {
        await i.intercept<List<Map<String, dynamic>>>(
          _ctx(),
          () async => throw StateError('fail'),
        );
      } catch (_) {}
      expect(result!.isError, isTrue);
      expect(result!.error, isA<StateError>());
    });
  });

  // ── hooks — swallowing ────────────────────────────────────────────────────

  group('hook error swallowing', () {
    test('requestHook throwing does not prevent query execution', () async {
      var queryCalled = false;
      final i = KnexOtelInterceptor(
        tracer: tracer,
        operationDurationHistogram: histogram,
        options: KnexOtelOptions(
          requestHook: (span, ctx) => throw StateError('hook exploded'),
        ),
      );
      await i.intercept<List<Map<String, dynamic>>>(
        _ctx(),
        () async {
          queryCalled = true;
          return [];
        },
      );
      expect(queryCalled, isTrue);
    });

    test('responseHook throwing does not prevent span from ending', () async {
      APISpan? span;
      final i = KnexOtelInterceptor(
        tracer: tracer,
        operationDurationHistogram: histogram,
        options: KnexOtelOptions(
          requestHook: (s, _) => span = s,
          responseHook: (span, ctx, result) => throw StateError('hook exploded'),
        ),
      );
      await i.intercept<List<Map<String, dynamic>>>(_ctx(), () async => []);
      expect(span!.isEnded, isTrue);
    });
  });

  // ── hook context ──────────────────────────────────────────────────────────

  group('hook context fields', () {
    test('requestHook KnexOtelSpanContext has correct fields', () async {
      KnexOtelSpanContext? hookCtx;
      final i = KnexOtelInterceptor(
        tracer: tracer,
        operationDurationHistogram: histogram,
        options: KnexOtelOptions(requestHook: (_, c) => hookCtx = c),
      );
      await i.intercept<List<Map<String, dynamic>>>(
        _ctx(
          dbSystem: 'sqlite',
          database: 'test.db',
          operationName: 'INSERT',
          collectionName: 'orders',
          querySummary: 'INSERT orders',
          txId: 'abc_1',
        ),
        () async => [],
      );
      expect(hookCtx!.dbSystem, 'sqlite');
      expect(hookCtx!.database, 'test.db');
      expect(hookCtx!.operationName, 'INSERT');
      expect(hookCtx!.collectionName, 'orders');
      expect(hookCtx!.querySummary, 'INSERT orders');
      expect(hookCtx!.txId, 'abc_1');
    });

    test('txId null when not in a transaction', () async {
      KnexOtelSpanContext? hookCtx;
      final i = KnexOtelInterceptor(
        tracer: tracer,
        operationDurationHistogram: histogram,
        options: KnexOtelOptions(requestHook: (_, c) => hookCtx = c),
      );
      await i.intercept<List<Map<String, dynamic>>>(_ctx(), () async => []);
      expect(hookCtx!.txId, isNull);
    });
  });

  // ── interceptStream() ────────────────────────────────────────────────────

  group('interceptStream()', () {
    test('span is ended when stream completes normally', () async {
      APISpan? span;
      final i = KnexOtelInterceptor(
        tracer: tracer,
        operationDurationHistogram: histogram,
        options: KnexOtelOptions(requestHook: (s, _) => span = s),
      );
      await i.interceptStream<int>(_ctx(), () => Stream.fromIterable([1, 2, 3])).toList();
      expect(span!.isEnded, isTrue);
      expect(span!.status, SpanStatusCode.Ok);
    });

    test('span is ended when stream errors', () async {
      APISpan? span;
      final i = KnexOtelInterceptor(
        tracer: tracer,
        operationDurationHistogram: histogram,
        options: KnexOtelOptions(requestHook: (s, _) => span = s),
      );
      try {
        await i
            .interceptStream<int>(_ctx(), () => Stream.error(StateError('fail')))
            .toList();
      } catch (_) {}
      expect(span!.isEnded, isTrue);
      expect(span!.status, SpanStatusCode.Error);
      expect(span!.attributes.toJson()['error.type'], 'StateError');
    });

    test('span is ended when subscription is cancelled', () async {
      APISpan? span;
      final i = KnexOtelInterceptor(
        tracer: tracer,
        operationDurationHistogram: histogram,
        options: KnexOtelOptions(requestHook: (s, _) => span = s),
      );
      late StreamSubscription<int> sub;
      sub = i
          .interceptStream<int>(
            _ctx(),
            () => Stream.periodic(const Duration(milliseconds: 10), (n) => n),
          )
          .listen((_) => sub.cancel());
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(span!.isEnded, isTrue);
    });

    test('no span created when stream is never subscribed', () async {
      APISpan? span;
      final i = KnexOtelInterceptor(
        tracer: tracer,
        operationDurationHistogram: histogram,
        options: KnexOtelOptions(requestHook: (s, _) => span = s),
      );
      // Create stream but never listen.
      // ignore: unused_local_variable
      final stream = i.interceptStream<int>(_ctx(), () => Stream.fromIterable([1]));
      await Future<void>.delayed(Duration.zero);
      expect(span, isNull);
    });

    test('histogram recorded on stream completion', () async {
      await interceptor
          .interceptStream<int>(_ctx(), () => Stream.fromIterable([1, 2]))
          .toList();
      expect(histogram.recordings, hasLength(1));
      expect(histogram.recordings.first.$1, greaterThanOrEqualTo(0.0));
    });

    test('histogram recorded on stream cancellation', () async {
      late StreamSubscription<int> sub;
      sub = interceptor
          .interceptStream<int>(
            _ctx(),
            () => Stream.periodic(const Duration(milliseconds: 10), (n) => n),
          )
          .listen((_) => sub.cancel());
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(histogram.recordings, hasLength(1));
    });

    test('responseHook called on stream completion', () async {
      KnexOtelResult? result;
      final i = KnexOtelInterceptor(
        tracer: tracer,
        operationDurationHistogram: histogram,
        options: KnexOtelOptions(responseHook: (span, ctx, r) => result = r),
      );
      await i.interceptStream<int>(_ctx(), () => Stream.fromIterable([1, 2, 3])).toList();
      expect(result!.isError, isFalse);
    });

    test('responseHook called with isError=true on stream error', () async {
      KnexOtelResult? result;
      final i = KnexOtelInterceptor(
        tracer: tracer,
        operationDurationHistogram: histogram,
        options: KnexOtelOptions(responseHook: (span, ctx, r) => result = r),
      );
      try {
        await i
            .interceptStream<int>(_ctx(), () => Stream.error(StateError('boom')))
            .toList();
      } catch (_) {}
      expect(result!.isError, isTrue);
      expect(result!.error, isA<StateError>());
    });

    test('stream items pass through unchanged', () async {
      final result = await interceptor
          .interceptStream<int>(_ctx(), () => Stream.fromIterable([10, 20, 30]))
          .toList();
      expect(result, [10, 20, 30]);
    });

    test('finishOnce guard: responseHook called exactly once on normal close', () async {
      var hookCount = 0;
      final captureHistogram = CapturingHistogram(
        OTelAPI.meterProvider().getMeter(name: 'guard_test'),
      );
      final i = KnexOtelInterceptor(
        tracer: tracer,
        operationDurationHistogram: captureHistogram,
        options: KnexOtelOptions(responseHook: (span, ctx, result) => hookCount++),
      );
      await i.interceptStream<int>(_ctx(), () => Stream.fromIterable([1])).toList();
      // Both responseHook and histogram must fire exactly once.
      expect(hookCount, 1);
      expect(captureHistogram.recordings, hasLength(1));
    });
  });

  // ── KnexOtelOptions validation ────────────────────────────────────────────

  group('KnexOtelOptions validation', () {
    test('maxQueryTextLength = 0 is valid (captures nothing)', () async {
      APISpan? span;
      final i = KnexOtelInterceptor(
        tracer: tracer,
        operationDurationHistogram: histogram,
        options: KnexOtelOptions(
          maxQueryTextLength: 0,
          requestHook: (s, _) => span = s,
        ),
      );
      await i.intercept<List<Map<String, dynamic>>>(_ctx(sql: 'SELECT 1'), () async => []);
      // With length 0, SQL is empty string + ellipsis.
      final text = span!.attributes.toJson()['db.query.text'] as String;
      expect(text, '…');
    });

    test('negative maxQueryTextLength throws ArgumentError (works in production builds)', () {
      expect(
        () => KnexOtelOptions(maxQueryTextLength: -1),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

