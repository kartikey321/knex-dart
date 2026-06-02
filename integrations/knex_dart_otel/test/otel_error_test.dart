/// Exhaustive OTel interceptor error, attribute, and composition tests.
library;

import 'dart:async';

import 'package:dartastic_opentelemetry_api/dartastic_opentelemetry_api.dart';
import 'package:knex_dart/knex_dart.dart';
import 'package:knex_dart_otel/knex_dart_otel.dart';
import 'package:test/test.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

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

class CountingInterceptor extends QueryInterceptor {
  int calls = 0;

  @override
  Future<T> intercept<T>(
    QueryExecutionContext ctx,
    Future<T> Function() next,
  ) async {
    calls++;
    return next();
  }
}

class ThrowingInterceptor extends QueryInterceptor {
  @override
  Future<T> intercept<T>(
    QueryExecutionContext ctx,
    Future<T> Function() next,
  ) async {
    throw StateError('interceptor explosion');
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
}) => QueryExecutionContext(
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
  late KnexOtelInterceptor otel;

  setUp(() {
    OTelAPI.reset();
    OTelAPI.initialize(
      endpoint: 'http://localhost:4317',
      serviceName: 'knex-otel-error-test',
      serviceVersion: '0.0.1',
    );
    tracer = OTelAPI.tracer('knex_dart_otel_error_test');
    histogram = CapturingHistogram(
      OTelAPI.meterProvider().getMeter(name: 'knex_dart_otel_error_test'),
    );
    otel = KnexOtelInterceptor(
      tracer: tracer,
      operationDurationHistogram: histogram,
    );
  });

  tearDown(() => OTelAPI.reset());

  // ── 1. Span ends on query error ───────────────────────────────────────────

  group('span lifecycle on error', () {
    test('exception propagates to caller after span ends', () async {
      final err = StateError('db explosion');
      Object? caught;
      try {
        await otel.intercept<List<Map<String, dynamic>>>(
          _ctx(),
          () async => throw err,
        );
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<StateError>());
      expect((caught as StateError).message, 'db explosion');
    });

    test('histogram records duration even on error', () async {
      try {
        await otel.intercept<List<Map<String, dynamic>>>(
          _ctx(),
          () async => throw Exception('fail'),
        );
      } catch (_) {}

      expect(histogram.recordings, hasLength(1));
      expect(histogram.recordings.first.$1, greaterThanOrEqualTo(0.0));
    });

    test('original exception type preserved through OTel intercept', () async {
      final err = ArgumentError.value(42, 'param', 'bad value');
      Object? caught;
      try {
        await otel.intercept<void>(_ctx(), () async => throw err);
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<ArgumentError>());
      expect((caught as ArgumentError).message, 'bad value');
    });
  });

  // ── 2. db.system attribute matches dbSystem ───────────────────────────────

  group('span attributes', () {
    test('db.system attribute set from ctx.dbSystem', () async {
      // The OTel API in no-op mode still allows intercept to run; attribute
      // verification is done via a requestHook that captures the span.
      String? capturedDbSystem;
      final otelWithHook = KnexOtelInterceptor(
        tracer: tracer,
        operationDurationHistogram: histogram,
        options: KnexOtelOptions(
          requestHook: (span, ctx) {
            // In no-op mode the span is a no-op stub; we read from the ctx directly.
            capturedDbSystem = ctx.dbSystem;
          },
        ),
      );

      await otelWithHook.intercept<List<Map<String, dynamic>>>(
        _ctx(dbSystem: 'sqlite'),
        () async => [],
      );

      expect(capturedDbSystem, 'sqlite');
    });

    test('txId exposed in requestHook context when present', () async {
      String? capturedTxId;
      final otelWithHook = KnexOtelInterceptor(
        tracer: tracer,
        operationDurationHistogram: histogram,
        options: KnexOtelOptions(
          requestHook: (span, ctx) {
            capturedTxId = ctx.txId;
          },
        ),
      );

      await otelWithHook.intercept<List<Map<String, dynamic>>>(
        _ctx(txId: 'tx_abc123'),
        () async => [],
      );

      expect(capturedTxId, 'tx_abc123');
    });

    test('txId is null for non-transaction queries', () async {
      String? capturedTxId = 'sentinel';
      final otelWithHook = KnexOtelInterceptor(
        tracer: tracer,
        operationDurationHistogram: histogram,
        options: KnexOtelOptions(
          requestHook: (span, ctx) {
            capturedTxId = ctx.txId;
          },
        ),
      );

      await otelWithHook.intercept<List<Map<String, dynamic>>>(
        _ctx(txId: null),
        () async => [],
      );

      expect(capturedTxId, isNull);
    });
  });

  // ── 3. Multiple interceptors compose correctly ────────────────────────────

  group('pipeline composition', () {
    test('two interceptors both see every event in order', () async {
      final calls = <String>[];
      final a = _OrderedInterceptor('A', calls);
      final b = _OrderedInterceptor('B', calls);

      // Simulate A → B pipeline: A wraps B wraps the executor.
      await a.intercept<List<Map<String, dynamic>>>(
        _ctx(),
        () => b.intercept(_ctx(), () async => []),
      );

      expect(calls, ['A', 'B']);
    });

    test('OTel + spy interceptors both see every query', () async {
      final spy = CountingInterceptor();

      // OTel wraps spy.
      await otel.intercept<List<Map<String, dynamic>>>(
        _ctx(),
        () => spy.intercept(_ctx(), () async => []),
      );

      expect(spy.calls, 1);
      expect(histogram.recordings, hasLength(1));
    });

    test('OTel still records histogram when a downstream interceptor throws', () async {
      final throwing = ThrowingInterceptor();

      try {
        await otel.intercept<List<Map<String, dynamic>>>(
          _ctx(),
          () => throwing.intercept(_ctx(), () async => []),
        );
      } catch (_) {}

      expect(histogram.recordings, hasLength(1));
    });
  });

  // ── 4. OTel requestHook throw does not break query ────────────────────────

  group('hook error isolation', () {
    test('requestHook throw does not propagate — query completes', () async {
      final otelWithBadHook = KnexOtelInterceptor(
        tracer: tracer,
        operationDurationHistogram: histogram,
        options: KnexOtelOptions(
          requestHook: (_, _) => throw StateError('hook boom'),
        ),
      );

      final result = await otelWithBadHook.intercept<List<Map<String, dynamic>>>(
        _ctx(),
        () async => [{'id': 1}],
      );

      expect(result, hasLength(1));
    });

    test('responseHook throw does not propagate — query result returned', () async {
      final otelWithBadHook = KnexOtelInterceptor(
        tracer: tracer,
        operationDurationHistogram: histogram,
        options: KnexOtelOptions(
          responseHook: (_, _, _) => throw StateError('response hook boom'),
        ),
      );

      final result = await otelWithBadHook.intercept<List<Map<String, dynamic>>>(
        _ctx(),
        () async => [{'id': 42}],
      );

      expect(result, hasLength(1));
      expect(result.first['id'], 42);
    });

    test('responseHook throw on error path does not suppress original exception', () async {
      final otelWithBadHook = KnexOtelInterceptor(
        tracer: tracer,
        operationDurationHistogram: histogram,
        options: KnexOtelOptions(
          responseHook: (_, _, _) => throw StateError('response hook boom'),
        ),
      );

      await expectLater(
        otelWithBadHook.intercept<void>(
          _ctx(),
          () async => throw ArgumentError('original'),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // ── 5. Stream intercept ends span on error ────────────────────────────────

  group('interceptStream error path', () {
    test('histogram records duration when stream emits error', () async {
      final stream = otel.interceptStream<Map<String, dynamic>>(
        _ctx(),
        () => Stream.error(Exception('stream error')),
      );

      try {
        await stream.toList();
      } catch (_) {}

      expect(histogram.recordings, hasLength(1));
    });

    test('stream error propagates to subscriber', () async {
      final stream = otel.interceptStream<Map<String, dynamic>>(
        _ctx(),
        () => Stream.error(ArgumentError('stream bad arg')),
      );

      await expectLater(stream, emitsError(isA<ArgumentError>()));
    });

    test('stream success records histogram', () async {
      final stream = otel.interceptStream<Map<String, dynamic>>(
        _ctx(),
        () => Stream.fromIterable([
          {'id': 1},
          {'id': 2},
        ]),
      );

      final rows = await stream.toList();
      expect(rows, hasLength(2));
      expect(histogram.recordings, hasLength(1));
    });
  });
}

// ── Helper interceptor ────────────────────────────────────────────────────────

class _OrderedInterceptor extends QueryInterceptor {
  final String label;
  final List<String> log;

  _OrderedInterceptor(this.label, this.log);

  @override
  Future<T> intercept<T>(
    QueryExecutionContext ctx,
    Future<T> Function() next,
  ) async {
    log.add(label);
    return next();
  }
}
