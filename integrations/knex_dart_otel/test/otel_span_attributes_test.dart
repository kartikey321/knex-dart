/// Direct OTel span attribute verification tests.
library;

import 'package:dartastic_opentelemetry_api/dartastic_opentelemetry_api.dart';
import 'package:knex_dart/knex_dart.dart';
import 'package:knex_dart_otel/knex_dart_otel.dart';
import 'package:test/test.dart';

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

QueryExecutionContext _ctx({
  String dbSystem = 'postgresql',
  String? database = 'mydb',
  String? serverAddress = 'localhost',
  int? serverPort = 5432,
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

void main() {
  late APITracer tracer;
  late CapturingHistogram histogram;

  setUp(() {
    OTelAPI.reset();
    OTelAPI.initialize(
      endpoint: 'http://localhost:4317',
      serviceName: 'knex-otel-span-attributes-test',
      serviceVersion: '0.0.1',
    );
    tracer = OTelAPI.tracer('knex_dart_otel_span_attributes_test');
    histogram = CapturingHistogram(
      OTelAPI.meterProvider().getMeter(
        name: 'knex_dart_otel_span_attributes_test',
      ),
    );
  });

  tearDown(() => OTelAPI.reset());

  KnexOtelInterceptor interceptorCapturing(void Function(APISpan span) hook) {
    return KnexOtelInterceptor(
      tracer: tracer,
      operationDurationHistogram: histogram,
      options: KnexOtelOptions(requestHook: (span, _) => hook(span)),
    );
  }

  group('span attributes', () {
    test('db.system.name equals ctx.dbSystem', () async {
      for (final dbSystem in ['postgresql', 'sqlite', 'mysql']) {
        late APISpan capturedSpan;
        final otel = interceptorCapturing((span) => capturedSpan = span);

        await otel.intercept<List<Map<String, dynamic>>>(
          _ctx(dbSystem: dbSystem),
          () async => [],
        );

        expect(capturedSpan.attributes.getString('db.system.name'), dbSystem);
      }
    });

    test('db.operation.name equals ctx.operationName', () async {
      for (final operationName in ['SELECT', 'INSERT']) {
        late APISpan capturedSpan;
        final otel = interceptorCapturing((span) => capturedSpan = span);

        await otel.intercept<List<Map<String, dynamic>>>(
          _ctx(operationName: operationName),
          () async => [],
        );

        expect(
          capturedSpan.attributes.getString('db.operation.name'),
          operationName,
        );
      }
    });

    test('db.namespace set only when database is provided', () async {
      late APISpan withDatabase;
      await interceptorCapturing(
        (span) => withDatabase = span,
      ).intercept<List<Map<String, dynamic>>>(
        _ctx(database: 'orders_db'),
        () async => [],
      );

      late APISpan withoutDatabase;
      await interceptorCapturing(
        (span) => withoutDatabase = span,
      ).intercept<List<Map<String, dynamic>>>(
        _ctx(database: null),
        () async => [],
      );

      expect(withDatabase.attributes.getString('db.namespace'), 'orders_db');
      expect(
        withoutDatabase.attributes.toMap(),
        isNot(contains('db.namespace')),
      );
    });

    test(
      'db.collection.name set only when collectionName is provided',
      () async {
        late APISpan withCollection;
        await interceptorCapturing(
          (span) => withCollection = span,
        ).intercept<List<Map<String, dynamic>>>(
          _ctx(collectionName: 'users'),
          () async => [],
        );

        late APISpan withoutCollection;
        await interceptorCapturing(
          (span) => withoutCollection = span,
        ).intercept<List<Map<String, dynamic>>>(
          _ctx(collectionName: null),
          () async => [],
        );

        expect(
          withCollection.attributes.getString('db.collection.name'),
          'users',
        );
        expect(
          withoutCollection.attributes.toMap(),
          isNot(contains('db.collection.name')),
        );
      },
    );

    test(
      'db.query.text equals ctx.sql when captureQueryText is true',
      () async {
        late APISpan capturedSpan;
        final sql = 'select * from "users" where "id" = ?';

        await interceptorCapturing(
          (span) => capturedSpan = span,
        ).intercept<List<Map<String, dynamic>>>(_ctx(sql: sql), () async => []);

        expect(capturedSpan.attributes.getString('db.query.text'), sql);
      },
    );

    test('db.query.text absent when captureQueryText is false', () async {
      late APISpan capturedSpan;
      final otel = KnexOtelInterceptor(
        tracer: tracer,
        operationDurationHistogram: histogram,
        options: KnexOtelOptions(
          captureQueryText: false,
          requestHook: (span, _) => capturedSpan = span,
        ),
      );

      await otel.intercept<List<Map<String, dynamic>>>(_ctx(), () async => []);

      expect(capturedSpan.attributes.toMap(), isNot(contains('db.query.text')));
    });

    test(
      'db.query.text truncated to maxQueryTextLength plus ellipsis',
      () async {
        late APISpan capturedSpan;
        const maxQueryTextLength = 12;
        final sql = 'select * from users where email = ? and active = ?';
        final otel = KnexOtelInterceptor(
          tracer: tracer,
          operationDurationHistogram: histogram,
          options: KnexOtelOptions(
            maxQueryTextLength: maxQueryTextLength,
            requestHook: (span, _) => capturedSpan = span,
          ),
        );

        await otel.intercept<List<Map<String, dynamic>>>(
          _ctx(sql: sql),
          () async => [],
        );

        final text = capturedSpan.attributes.getString('db.query.text')!;
        expect(text.length, maxQueryTextLength + 1);
        expect(text, endsWith('…'));
      },
    );

    test('server.address set only when serverAddress is non-null', () async {
      late APISpan withAddress;
      await interceptorCapturing(
        (span) => withAddress = span,
      ).intercept<List<Map<String, dynamic>>>(
        _ctx(serverAddress: 'db.local'),
        () async => [],
      );

      late APISpan withoutAddress;
      await interceptorCapturing(
        (span) => withoutAddress = span,
      ).intercept<List<Map<String, dynamic>>>(
        _ctx(serverAddress: null),
        () async => [],
      );

      expect(withAddress.attributes.getString('server.address'), 'db.local');
      expect(
        withoutAddress.attributes.toMap(),
        isNot(contains('server.address')),
      );
    });

    test('server.port set only when serverPort is non-null', () async {
      late APISpan withPort;
      await interceptorCapturing(
        (span) => withPort = span,
      ).intercept<List<Map<String, dynamic>>>(
        _ctx(serverPort: 5433),
        () async => [],
      );

      late APISpan withoutPort;
      await interceptorCapturing(
        (span) => withoutPort = span,
      ).intercept<List<Map<String, dynamic>>>(
        _ctx(serverPort: null),
        () async => [],
      );

      expect(withPort.attributes.getInt('server.port'), 5433);
      expect(withoutPort.attributes.toMap(), isNot(contains('server.port')));
    });
  });

  group('span lifecycle and status', () {
    test('span name equals ctx.querySummary', () async {
      late APISpan capturedSpan;

      await interceptorCapturing(
        (span) => capturedSpan = span,
      ).intercept<List<Map<String, dynamic>>>(
        _ctx(querySummary: 'SELECT active users'),
        () async => [],
      );

      expect(capturedSpan.name, 'SELECT active users');
    });

    test('span status is Ok on successful query', () async {
      late APISpan capturedSpan;

      await interceptorCapturing(
        (span) => capturedSpan = span,
      ).intercept<List<Map<String, dynamic>>>(_ctx(), () async => []);

      expect(capturedSpan.status, SpanStatusCode.Ok);
    });

    test('span status is Error when query throws', () async {
      late APISpan capturedSpan;

      await expectLater(
        () => interceptorCapturing(
          (span) => capturedSpan = span,
        ).intercept<void>(_ctx(), () async => throw StateError('fail')),
        throwsA(isA<StateError>()),
      );

      expect(capturedSpan.status, SpanStatusCode.Error);
    });

    test('error.type attribute is exception runtimeType string', () async {
      for (final error in [StateError('fail'), ArgumentError('bad input')]) {
        late APISpan capturedSpan;

        await expectLater(
          () => interceptorCapturing(
            (span) => capturedSpan = span,
          ).intercept<void>(_ctx(), () async => throw error),
          throwsA(isA<Object>()),
        );

        expect(
          capturedSpan.attributes.getString('error.type'),
          error.runtimeType.toString(),
        );
      }
    });

    test('spanEvents contains exception event on error', () async {
      late APISpan capturedSpan;

      await expectLater(
        () => interceptorCapturing(
          (span) => capturedSpan = span,
        ).intercept<void>(_ctx(), () async => throw StateError('fail')),
        throwsA(isA<StateError>()),
      );

      expect(
        capturedSpan.spanEvents?.any((event) => event.name == 'exception'),
        isTrue,
      );
    });

    test('isEnded is true after intercept returns', () async {
      late APISpan capturedSpan;

      await interceptorCapturing(
        (span) => capturedSpan = span,
      ).intercept<List<Map<String, dynamic>>>(_ctx(), () async => []);

      expect(capturedSpan.isEnded, isTrue);
    });
  });

  group('responseHook', () {
    test('receives successful KnexOtelResult with rowCount', () async {
      KnexOtelResult? capturedResult;
      final otel = KnexOtelInterceptor(
        tracer: tracer,
        operationDurationHistogram: histogram,
        options: KnexOtelOptions(
          responseHook: (_, _, result) => capturedResult = result,
        ),
      );

      await otel.intercept<List<int>>(_ctx(), () async => [1, 2, 3]);

      expect(capturedResult, isNotNull);
      expect(capturedResult!.isError, isFalse);
      expect(capturedResult!.rowCount, 3);
    });

    test('receives error KnexOtelResult with error object', () async {
      KnexOtelResult? capturedResult;
      final error = StateError('fail');
      final otel = KnexOtelInterceptor(
        tracer: tracer,
        operationDurationHistogram: histogram,
        options: KnexOtelOptions(
          responseHook: (_, _, result) => capturedResult = result,
        ),
      );

      await expectLater(
        () => otel.intercept<void>(_ctx(), () async => throw error),
        throwsA(same(error)),
      );

      expect(capturedResult, isNotNull);
      expect(capturedResult!.isError, isTrue);
      expect(capturedResult!.error, same(error));
    });
  });

  group('interceptStream', () {
    test('sets db.system.name and db.operation.name', () async {
      late APISpan capturedSpan;
      final otel = KnexOtelInterceptor(
        tracer: tracer,
        operationDurationHistogram: histogram,
        options: KnexOtelOptions(requestHook: (span, _) => capturedSpan = span),
      );

      await otel
          .interceptStream<int>(
            _ctx(dbSystem: 'sqlite', operationName: 'SELECT'),
            () => Stream.fromIterable([1, 2, 3]),
          )
          .toList();

      expect(capturedSpan.attributes.getString('db.system.name'), 'sqlite');
      expect(capturedSpan.attributes.getString('db.operation.name'), 'SELECT');
    });

    test('ends span when subscription is cancelled mid-stream', () async {
      late APISpan capturedSpan;
      var responseHookCalls = 0;
      final otel = KnexOtelInterceptor(
        tracer: tracer,
        operationDurationHistogram: histogram,
        options: KnexOtelOptions(
          requestHook: (span, _) => capturedSpan = span,
          responseHook: (_, _, result) {
            responseHookCalls++;
            expect(result.isError, isFalse);
          },
        ),
      );

      final subscription = otel
          .interceptStream<int>(
            _ctx(dbSystem: 'sqlite', operationName: 'SELECT'),
            () => Stream.periodic(
              const Duration(milliseconds: 1),
              (index) => index,
            ),
          )
          .listen((_) {});

      await Future<void>.delayed(const Duration(milliseconds: 5));
      await subscription.cancel();

      expect(capturedSpan.isEnded, isTrue);
      expect(responseHookCalls, 1);
    });
  });
}
