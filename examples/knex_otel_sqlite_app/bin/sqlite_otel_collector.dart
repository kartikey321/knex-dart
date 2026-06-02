import 'dart:async';
import 'dart:io';

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:knex_dart_otel/knex_dart_otel.dart';
import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';

Future<void> main(List<String> args) async {
  final config = _ExampleConfig.parse(args);
  await _initializeOtel(config);

  final db = await KnexSQLite.connect(
    filename: ':memory:',
    interceptors: [
      KnexOtelInterceptor(
        tracer: OTel.tracer(),
        options: KnexOtelOptions(
          responseHook: (span, ctx, result) {
            if (result.rowCount != null) {
              span.setIntAttribute('db.response.row_count', result.rowCount!);
            }
          },
        ),
      ),
    ],
  );

  try {
    await _runWorkload(db);
    print('knex_dart OTel SQLite example completed.');
  } finally {
    await db.close();
    await Future<void>.delayed(const Duration(seconds: 2));
    await OTel.shutdown();
  }
}

Future<void> _initializeOtel(_ExampleConfig config) async {
  final spanExporter = switch (config.exporter) {
    _ExporterKind.console => ConsoleExporter(),
    _ExporterKind.otlpHttp => OtlpHttpSpanExporter(
      OtlpHttpExporterConfig(endpoint: config.endpoint),
    ),
    _ExporterKind.otlpGrpc => OtlpGrpcSpanExporter(
      OtlpGrpcExporterConfig(
        endpoint: _grpcEndpoint(config.endpoint),
        insecure: config.insecure,
      ),
    ),
  };

  final metricExporter = switch (config.exporter) {
    _ExporterKind.console => ConsoleMetricExporter(),
    _ExporterKind.otlpHttp => OtlpHttpMetricExporter(
      OtlpHttpMetricExporterConfig(endpoint: config.endpoint),
    ),
    _ExporterKind.otlpGrpc => OtlpGrpcMetricExporter(
      OtlpGrpcMetricExporterConfig(
        endpoint: _grpcEndpoint(config.endpoint),
        insecure: config.insecure,
      ),
    ),
  };

  await OTel.initialize(
    endpoint: config.endpoint,
    secure: !config.insecure,
    serviceName: 'knex-otel-sqlite-example',
    serviceVersion: '0.0.1',
    tracerName: 'knex-otel-sqlite-example',
    tracerVersion: '0.0.1',
    enableLogs: false,
    spanProcessor: SimpleSpanProcessor(spanExporter),
    metricReader: PeriodicExportingMetricReader(
      metricExporter,
      interval: const Duration(seconds: 1),
    ),
  );
}

Future<void> _runWorkload(KnexSQLite db) async {
  await db.executeSchema((schema) {
    schema.createTable('users', (table) {
      table.increments('id');
      table.string('name').notNullable();
      table.integer('age');
      table.boolean('active').defaultTo(true);
    });
  });

  await db.insert(
    db('users').insert([
      {'name': 'Alice', 'age': 30, 'active': true},
      {'name': 'Bob', 'age': 41, 'active': false},
      {'name': 'Cara', 'age': 28, 'active': true},
    ]),
  );

  await db.select(
    db('users')
        .select(['id', 'name', 'age'])
        .where('active', '=', true)
        .orderBy('age', 'desc'),
  );

  await db.trx((tx) async {
    await tx.update(
      tx('users').where('name', '=', 'Alice').update({'age': 31}),
    );
    await tx.select(tx('users').select(['id', 'name', 'age']));
  });

  try {
    await db.rawSql('SELECT * FROM missing_table');
  } catch (_) {
    // Intentional: verifies error span status and exception event export.
  }
}

String _grpcEndpoint(String endpoint) {
  final uri = Uri.tryParse(endpoint);
  if (uri == null || uri.host.isEmpty) return endpoint;
  return '${uri.host}:${uri.hasPort ? uri.port : 4317}';
}

class _ExampleConfig {
  final _ExporterKind exporter;
  final String endpoint;
  final bool insecure;

  const _ExampleConfig({
    required this.exporter,
    required this.endpoint,
    required this.insecure,
  });

  factory _ExampleConfig.parse(List<String> args) {
    var exporter = _ExporterKind.console;
    var endpoint =
        Platform.environment['OTEL_EXPORTER_OTLP_ENDPOINT'] ??
        'http://localhost:4318';
    var insecure =
        Platform.environment['OTEL_EXPORTER_OTLP_INSECURE'] == 'true';

    for (final arg in args) {
      if (arg == '--console') {
        exporter = _ExporterKind.console;
      } else if (arg == '--otlp-http') {
        exporter = _ExporterKind.otlpHttp;
      } else if (arg == '--otlp-grpc') {
        exporter = _ExporterKind.otlpGrpc;
        endpoint =
            Platform.environment['OTEL_EXPORTER_OTLP_ENDPOINT'] ??
            'localhost:4317';
      } else if (arg.startsWith('--endpoint=')) {
        endpoint = arg.substring('--endpoint='.length);
      } else if (arg == '--insecure') {
        insecure = true;
      } else {
        throw ArgumentError('Unknown argument: $arg');
      }
    }

    return _ExampleConfig(
      exporter: exporter,
      endpoint: endpoint,
      insecure: insecure,
    );
  }
}

enum _ExporterKind { console, otlpHttp, otlpGrpc }
