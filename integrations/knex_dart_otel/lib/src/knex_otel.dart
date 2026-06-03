/// OpenTelemetry instrumentation for knex_dart driver wrappers.
///
/// Attach [KnexOtelInterceptor] to any driver's `interceptors` list to get
/// automatic query spans and `db.client.operation.duration` histogram metrics
/// following the OpenTelemetry database semantic conventions.
library;

import 'dart:async';

import 'package:dartastic_opentelemetry_api/dartastic_opentelemetry_api.dart';
import 'package:knex_dart/knex_dart.dart';

// ---------------------------------------------------------------------------
// Public hook types
// ---------------------------------------------------------------------------

/// Called synchronously after span creation, before query execution.
/// Use it to add custom span attributes.
///
/// Errors thrown here are swallowed so observability cannot break DB calls.
typedef KnexOtelRequestHook =
    void Function(APISpan span, KnexOtelSpanContext ctx);

/// Called synchronously after query completion (success or error).
typedef KnexOtelResponseHook =
    void Function(APISpan span, KnexOtelSpanContext ctx, KnexOtelResult result);

// ---------------------------------------------------------------------------
// Context and result types passed to hooks
// ---------------------------------------------------------------------------

/// Snapshot of query metadata available to hook callbacks.
class KnexOtelSpanContext {
  final String dbSystem;
  final String? database;
  final String? serverAddress;
  final int? serverPort;
  final String sql;
  final String operationName;
  final String? collectionName;
  final String querySummary;

  /// Transaction ID when the query runs inside a transaction, null otherwise.
  ///
  /// Use this in a [KnexOtelRequestHook] to attach `db.transaction.id`:
  /// ```dart
  /// requestHook: (span, ctx) {
  ///   if (ctx.txId != null) span.setStringAttribute('db.transaction.id', ctx.txId!);
  /// },
  /// ```
  final String? txId;

  const KnexOtelSpanContext({
    required this.dbSystem,
    required this.sql,
    required this.operationName,
    required this.querySummary,
    this.database,
    this.serverAddress,
    this.serverPort,
    this.collectionName,
    this.txId,
  });

  factory KnexOtelSpanContext.fromExecution(QueryExecutionContext ctx) =>
      KnexOtelSpanContext(
        dbSystem: ctx.dbSystem,
        database: ctx.database,
        serverAddress: ctx.serverAddress,
        serverPort: ctx.serverPort,
        sql: ctx.sql,
        operationName: ctx.operationName,
        collectionName: ctx.collectionName,
        querySummary: ctx.querySummary,
        txId: ctx.txId,
      );
}

/// Result metadata passed to [KnexOtelResponseHook].
class KnexOtelResult {
  final bool isError;
  final Object? error;
  final StackTrace? stackTrace;
  final int? rowCount;
  final Duration elapsed;

  /// Creates a [KnexOtelResult] with the given fields.
  ///
  /// [isError] and [elapsed] are required. [rowCount] is set when the result
  /// is a `List` (select queries); it is `null` for non-row-returning operations.
  const KnexOtelResult({
    required this.isError,
    required this.elapsed,
    this.error,
    this.stackTrace,
    this.rowCount,
  });
}

// ---------------------------------------------------------------------------
// Options
// ---------------------------------------------------------------------------

/// Configuration for [KnexOtelInterceptor].
class KnexOtelOptions {
  /// Include `db.query.text` attribute on spans.
  ///
  /// knex_dart always emits parameterized SQL so this is safe by default.
  final bool captureQueryText;

  /// Maximum length for `db.query.text`. Longer SQL is truncated.
  final int maxQueryTextLength;

  /// Called after span creation, before execution.
  /// Safe place to add custom span attributes (tenant ID, feature flags, etc.).
  final KnexOtelRequestHook? requestHook;

  /// Called after execution (success or error).
  final KnexOtelResponseHook? responseHook;

  /// Creates a [KnexOtelOptions] configuration.
  ///
  /// All parameters are optional. [maxQueryTextLength] must be non-negative;
  /// pass `0` to suppress `db.query.text` entirely (same as `captureQueryText: false`).
  KnexOtelOptions({
    this.captureQueryText = true,
    int maxQueryTextLength = 1024,
    this.requestHook,
    this.responseHook,
  }) : maxQueryTextLength = maxQueryTextLength >= 0
           ? maxQueryTextLength
           : throw ArgumentError.value(
               maxQueryTextLength,
               'maxQueryTextLength',
               'must be non-negative',
             );
}

// ---------------------------------------------------------------------------
// Main interceptor
// ---------------------------------------------------------------------------

/// OpenTelemetry query interceptor for knex_dart.
///
/// Implements [QueryInterceptor] and is attached via the `interceptors`
/// parameter on any driver wrapper.
///
/// ## Setup
///
/// ```dart
/// import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
/// import 'package:knex_dart_postgres/knex_dart_postgres.dart';
/// import 'package:knex_dart_otel/knex_dart_otel.dart';
///
/// final tracer = OTelAPI.tracerProvider().getTracer(
///   'my-service',
///   version: '1.0.0',
/// );
///
/// final db = await KnexPostgres.connect(
///   host: 'localhost', database: 'myapp',
///   username: 'user', password: 'pass',
///   interceptors: [
///     KnexOtelInterceptor(
///       tracer: tracer,
///       options: KnexOtelOptions(
///         requestHook: (span, ctx) {
///           span.setStringAttribute('tenant.id', 'tenant-123');
///         },
///       ),
///     ),
///   ],
/// );
/// ```
///
/// ## Context propagation
///
/// [intercept] is called synchronously inside the caller's async zone —
/// the same zone as `await db.select(...)`. `Context.current` is therefore
/// the correct OTel context (e.g. the active HTTP/gRPC request span), and the
/// DB span is automatically parented to it.
class KnexOtelInterceptor extends QueryInterceptor {
  static const _instrumentationName = 'knex_dart_otel';
  static const _instrumentationVersion = '0.1.0';

  // Shared default histogram — all interceptors that don't supply their own
  // use this one so only a single instrument is registered per process.
  static APIHistogram<double>? _defaultHistogram;

  static const _operationDurationBuckets = <double>[
    0.001,
    0.005,
    0.01,
    0.05,
    0.1,
    0.5,
    1,
    5,
    10,
  ];

  final APITracer _tracer;
  final APIHistogram<double> _operationDuration;
  final KnexOtelOptions _options;

  /// Creates a [KnexOtelInterceptor].
  ///
  /// **Important**: initialize your OTel SDK *before* constructing this
  /// interceptor. The default [operationDurationHistogram] is created lazily
  /// and cached; if the SDK is not yet installed, it will bind to a no-op
  /// provider and stay no-op even after the SDK is installed later.
  /// Pass an explicit [operationDurationHistogram] to avoid this.
  KnexOtelInterceptor({
    required APITracer tracer,
    APIHistogram<double>? operationDurationHistogram,
    KnexOtelOptions? options,
  }) : _tracer = tracer,
       _operationDuration =
           operationDurationHistogram ??
           (_defaultHistogram ??= _createOperationDurationHistogram()),
       _options = options ?? KnexOtelOptions();

  /// Wraps a single future-based query execution with an OTel span.
  ///
  /// Sets all standard DB semantic convention attributes, calls any configured
  /// [KnexOtelOptions.requestHook] before execution, records the
  /// `db.client.operation.duration` histogram on completion, and re-throws
  /// any exception so it propagates normally to the caller.
  @override
  Future<T> intercept<T>(
    QueryExecutionContext ctx,
    Future<T> Function() next,
  ) async {
    // Span name follows OTel DB semconv recommendation:
    // db.query.summary when available, else db.operation.name.
    final spanName = ctx.querySummary;
    final hookCtx = KnexOtelSpanContext.fromExecution(ctx);

    final span = _tracer.startSpan(spanName, kind: SpanKind.client);

    // Required / recommended OTel DB semantic convention attributes.
    // Guarded: a failing SDK call must never prevent span.end() from being
    // reached (which would leak the span), nor break the user's query.
    try {
      span.setStringAttribute('db.system.name', ctx.dbSystem);
      span.setStringAttribute('db.operation.name', ctx.operationName);
      if (ctx.database != null) {
        span.setStringAttribute('db.namespace', ctx.database!);
      }
      if (ctx.collectionName != null) {
        span.setStringAttribute('db.collection.name', ctx.collectionName!);
      }
      if (_options.captureQueryText) {
        final sql = ctx.sql.length > _options.maxQueryTextLength
            ? '${ctx.sql.substring(0, _options.maxQueryTextLength)}…'
            : ctx.sql;
        span.setStringAttribute('db.query.text', sql);
      }
      if (ctx.serverAddress != null) {
        span.setStringAttribute('server.address', ctx.serverAddress!);
      }
      if (ctx.serverPort != null) {
        span.setIntAttribute('server.port', ctx.serverPort!);
      }
    } catch (_) {}

    // User hook — runs after base attributes are set so it can override them.
    if (_options.requestHook != null) {
      try {
        _options.requestHook!(span, hookCtx);
      } catch (_) {
        // Never let hook errors break query execution.
      }
    }

    final sw = Stopwatch()..start();
    try {
      // Make the DB span current so any child spans (HTTP, TCP) created inside
      // the driver are automatically parented to it. Use Context directly
      // instead of tracer.withSpanAsync() because some SDKs also record thrown
      // exceptions there; the interceptor owns DB exception recording below.
      final result = await Context.current.withSpan(span).run(next);
      sw.stop();

      span.setStatus(SpanStatusCode.Ok);

      final rowCount = result is List ? result.length : null;
      final otelResult = KnexOtelResult(
        isError: false,
        elapsed: sw.elapsed,
        rowCount: rowCount,
      );
      if (_options.responseHook != null) {
        try {
          _options.responseHook!(span, hookCtx, otelResult);
        } catch (_) {}
      }

      _recordOperationDuration(ctx, sw.elapsed);
      span.end();
      return result;
    } catch (e, st) {
      sw.stop();

      span.recordException(e, stackTrace: st);
      span.setStringAttribute('error.type', e.runtimeType.toString());
      span.setStatus(SpanStatusCode.Error, e.toString());

      final otelResult = KnexOtelResult(
        isError: true,
        elapsed: sw.elapsed,
        error: e,
        stackTrace: st,
      );
      if (_options.responseHook != null) {
        try {
          _options.responseHook!(span, hookCtx, otelResult);
        } catch (_) {}
      }

      _recordOperationDuration(ctx, sw.elapsed);
      span.end();
      rethrow;
    }
  }

  static APIHistogram<double> _createOperationDurationHistogram() {
    final meter = OTelAPI.meterProvider().getMeter(
      name: _instrumentationName,
      version: _instrumentationVersion,
      schemaUrl: OTelAPI.defaultSchemaUrl,
    );
    return meter.createHistogram<double>(
      name: 'db.client.operation.duration',
      unit: 's',
      description: 'Duration of database client operations.',
      boundaries: _operationDurationBuckets,
    );
  }

  /// Wraps a streaming query execution with an OTel span.
  ///
  /// The span is created lazily on first subscription so unsubscribed streams
  /// do not leak open spans. The span ends when the stream closes normally,
  /// emits an error, or the subscriber cancels.
  @override
  Stream<T> interceptStream<T>(
    QueryExecutionContext ctx,
    Stream<T> Function() next,
  ) {
    // Span is created lazily inside onListen so that a stream that is
    // never subscribed does not leak an open span.
    late APISpan span;
    late KnexOtelSpanContext hookCtx;
    final sw = Stopwatch();
    bool finished = false;
    StreamSubscription<T>? upstream;

    // Called exactly once regardless of how the stream ends: normal close,
    // error, or subscriber cancellation.  Guards against double-recording.
    void finishOnce({
      bool isError = false,
      Object? error,
      StackTrace? stackTrace,
    }) {
      if (finished) return;
      finished = true;
      sw.stop();

      if (isError) {
        span.recordException(error!, stackTrace: stackTrace);
        span.setStringAttribute('error.type', error.runtimeType.toString());
        span.setStatus(SpanStatusCode.Error, error.toString());
      } else {
        span.setStatus(SpanStatusCode.Ok);
      }

      _recordOperationDuration(ctx, sw.elapsed);

      if (_options.responseHook != null) {
        try {
          _options.responseHook!(
            span,
            hookCtx,
            KnexOtelResult(
              isError: isError,
              elapsed: sw.elapsed,
              error: error,
              stackTrace: stackTrace,
            ),
          );
        } catch (_) {}
      }

      span.end();
    }

    late StreamController<T> controller;
    controller = StreamController<T>(
      onListen: () {
        // Span starts here — only if someone actually subscribes.
        hookCtx = KnexOtelSpanContext.fromExecution(ctx);
        span = _tracer.startSpan(ctx.querySummary, kind: SpanKind.client);

        // Guard attribute-setting the same way as intercept() — a bad OTel SDK
        // call must not abort the stream before next().listen() runs.
        try {
          span.setStringAttribute('db.system.name', ctx.dbSystem);
          span.setStringAttribute('db.operation.name', ctx.operationName);
          if (ctx.database != null) {
            span.setStringAttribute('db.namespace', ctx.database!);
          }
          if (ctx.collectionName != null) {
            span.setStringAttribute('db.collection.name', ctx.collectionName!);
          }
          if (_options.captureQueryText) {
            final sql = ctx.sql.length > _options.maxQueryTextLength
                ? '${ctx.sql.substring(0, _options.maxQueryTextLength)}…'
                : ctx.sql;
            span.setStringAttribute('db.query.text', sql);
          }
          if (ctx.serverAddress != null) {
            span.setStringAttribute('server.address', ctx.serverAddress!);
          }
          if (ctx.serverPort != null) {
            span.setIntAttribute('server.port', ctx.serverPort!);
          }
        } catch (_) {}

        if (_options.requestHook != null) {
          try {
            _options.requestHook!(span, hookCtx);
          } catch (_) {}
        }

        sw.start();

        try {
          // Make the DB span current during listen() so any child spans created
          // by stream setup or stream callbacks are parented to it.
          upstream = _tracer.withSpan(
            span,
            () => next().listen(
              controller.add,
              onError: (Object e, StackTrace st) {
                finishOnce(isError: true, error: e, stackTrace: st);
                controller.addError(e, st);
              },
              onDone: () {
                finishOnce();
                controller.close();
              },
            ),
          );
        } catch (e, st) {
          // next() threw synchronously — end span immediately and forward.
          finishOnce(isError: true, error: e, stackTrace: st);
          controller.addError(e, st);
          controller.close();
        }
      },
      onCancel: () {
        // Subscriber cancelled mid-stream — await upstream cleanup so the DB
        // driver can release its cursor/connection before we end the span.
        final cancelFuture = upstream?.cancel();
        if (cancelFuture != null) {
          return cancelFuture.whenComplete(finishOnce);
        }
        finishOnce();
      },
      onPause: () => upstream?.pause(),
      onResume: () => upstream?.resume(),
    );

    return controller.stream;
  }

  void _recordOperationDuration(QueryExecutionContext ctx, Duration elapsed) {
    try {
      final attributes = <String, Object>{
        'db.system.name': ctx.dbSystem,
        'db.operation.name': ctx.operationName,
      };
      if (ctx.database != null) {
        attributes['db.namespace'] = ctx.database!;
      }
      if (ctx.collectionName != null) {
        attributes['db.collection.name'] = ctx.collectionName!;
      }
      if (ctx.serverAddress != null) {
        attributes['server.address'] = ctx.serverAddress!;
      }
      if (ctx.serverPort != null) {
        attributes['server.port'] = ctx.serverPort!;
      }

      _operationDuration.recordWithMap(
        elapsed.inMicroseconds / Duration.microsecondsPerSecond,
        attributes,
      );
    } catch (_) {
      // Observability must never break query execution.
    }
  }
}
