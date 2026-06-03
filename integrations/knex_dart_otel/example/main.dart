// ignore_for_file: avoid_print
import 'package:dartastic_opentelemetry_api/dartastic_opentelemetry_api.dart';
import 'package:knex_dart_otel/knex_dart_otel.dart';

/// Example: attach KnexOtelInterceptor to a driver and observe query spans.
///
/// In a real app, replace OTelAPI.initialize with the full SDK setup from
/// package:dartastic_opentelemetry and point the endpoint at your collector.
Future<void> main() async {
  // 1. Initialize OTel (SDK or API no-op for this example).
  OTelAPI.initialize(
    endpoint: 'http://localhost:4317',
    serviceName: 'my-service',
    serviceVersion: '1.0.0',
  );

  final tracer = OTelAPI.tracer('my-service');

  // 2. Build the interceptor with optional hooks.
  final otel = KnexOtelInterceptor(
    tracer: tracer,
    options: KnexOtelOptions(
      captureQueryText: true,
      requestHook: (span, ctx) {
        // Add a custom attribute before execution.
        span.setStringAttribute('tenant.id', 'demo-tenant');
        if (ctx.txId != null) {
          span.setStringAttribute('db.transaction.id', ctx.txId!);
        }
      },
      responseHook: (span, ctx, result) {
        if (result.isError) {
          print('Query failed: ${ctx.querySummary} — ${result.error}');
        } else {
          print(
            'Query OK: ${ctx.querySummary} '
            'rows=${result.rowCount} elapsed=${result.elapsed}',
          );
        }
      },
    ),
  );

  // 3. Pass [otel] in the interceptors list when connecting any driver, e.g.:
  //
  //   final db = await KnexPostgres.connect(
  //     host: 'localhost', database: 'myapp',
  //     username: 'user', password: 'pass',
  //     interceptors: [otel],
  //   );
  //
  //   final rows = await db.select(db('users').where('active', '=', true));
  //   await db.destroy();
  //
  // Every query will now emit a span with db.system.name, db.operation.name,
  // db.query.text, server.address, and server.port attributes, plus record
  // the db.client.operation.duration histogram metric.

  print('KnexOtelInterceptor ready: $otel');
}
