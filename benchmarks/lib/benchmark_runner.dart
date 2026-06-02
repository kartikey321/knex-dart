import 'dart:io';

import 'package:knex_dart/knex_dart.dart';

import 'benchmark_case.dart';

class BenchmarkConfig {
  final int iterations;
  final int warmupIterations;
  final List<KnexDialect> dialects;
  final bool includeUnsupported;

  const BenchmarkConfig({
    required this.iterations,
    required this.warmupIterations,
    required this.dialects,
    this.includeUnsupported = true,
  });

  Map<String, dynamic> toJson() {
    return {
      'iterations': iterations,
      'warmupIterations': warmupIterations,
      'dialects': dialects.map((dialect) => dialect.name).toList(),
      'includeUnsupported': includeUnsupported,
    };
  }
}

class BenchmarkRun {
  final String runId;
  final DateTime startedAt;
  final BenchmarkConfig config;
  final List<BenchmarkCaseResult> results;
  final Map<String, dynamic> environment;

  const BenchmarkRun({
    required this.runId,
    required this.startedAt,
    required this.config,
    required this.results,
    required this.environment,
  });

  Map<String, dynamic> toJson() {
    return {
      'runId': runId,
      'startedAt': startedAt.toUtc().toIso8601String(),
      'environment': environment,
      'config': config.toJson(),
      'results': results.map((result) => result.toJson()).toList(),
    };
  }
}

class BenchmarkCaseResult {
  final String caseId;
  final String caseName;
  final String category;
  final String mode;
  final String complexity;
  final List<String> features;
  final String dialect;
  final String status;
  final double? microsecondsPerOp;
  final int iterations;
  final int warmupIterations;
  final int? sqlLength;
  final int? bindingCount;
  final int? statementCount;
  final String? method;
  final String? sqlSample;
  final String? errorType;
  final String? error;

  const BenchmarkCaseResult({
    required this.caseId,
    required this.caseName,
    required this.category,
    required this.mode,
    required this.complexity,
    required this.features,
    required this.dialect,
    required this.status,
    required this.iterations,
    required this.warmupIterations,
    this.microsecondsPerOp,
    this.sqlLength,
    this.bindingCount,
    this.statementCount,
    this.method,
    this.sqlSample,
    this.errorType,
    this.error,
  });

  Map<String, dynamic> toJson() {
    return {
      'caseId': caseId,
      'caseName': caseName,
      'category': category,
      'mode': mode,
      'complexity': complexity,
      'features': features,
      'dialect': dialect,
      'status': status,
      'iterations': iterations,
      'warmupIterations': warmupIterations,
      if (microsecondsPerOp != null) 'microsecondsPerOp': microsecondsPerOp,
      if (sqlLength != null) 'sqlLength': sqlLength,
      if (bindingCount != null) 'bindingCount': bindingCount,
      if (statementCount != null) 'statementCount': statementCount,
      if (method != null) 'method': method,
      if (sqlSample != null) 'sqlSample': sqlSample,
      if (errorType != null) 'errorType': errorType,
      if (error != null) 'error': error,
    };
  }
}

class BenchmarkRunner {
  final List<BenchmarkCase> cases;
  final BenchmarkConfig config;

  BenchmarkOutput? _lastOutput;

  BenchmarkRunner({required this.cases, required this.config});

  BenchmarkRun run() {
    final startedAt = DateTime.now().toUtc();
    final results = <BenchmarkCaseResult>[];

    for (final benchmarkCase in cases) {
      for (final dialect in config.dialects) {
        if (!benchmarkCase.supports(dialect)) {
          if (config.includeUnsupported) {
            results.add(_unsupportedResult(benchmarkCase, dialect));
          }
          continue;
        }

        results.add(_runCase(benchmarkCase, dialect));
      }
    }

    if (_lastOutput == null) {
      throw StateError('benchmark produced no SQL');
    }

    return BenchmarkRun(
      runId: startedAt.toIso8601String().replaceAll(':', '-'),
      startedAt: startedAt,
      config: config,
      results: results,
      environment: {
        'dartVersion': Platform.version,
        'operatingSystem': Platform.operatingSystem,
        'operatingSystemVersion': Platform.operatingSystemVersion,
        'numberOfProcessors': Platform.numberOfProcessors,
      },
    );
  }

  BenchmarkCaseResult _runCase(
    BenchmarkCase benchmarkCase,
    KnexDialect dialect,
  ) {
    try {
      final sample = benchmarkCase.build(dialect);
      _lastOutput = sample;

      _time(benchmarkCase.build, dialect, config.warmupIterations);
      final elapsed = _time(benchmarkCase.build, dialect, config.iterations);

      return BenchmarkCaseResult(
        caseId: benchmarkCase.id,
        caseName: benchmarkCase.name,
        category: benchmarkCase.category,
        mode: benchmarkCase.mode.name,
        complexity: benchmarkCase.complexity,
        features: benchmarkCase.features,
        dialect: dialect.name,
        status: 'ok',
        microsecondsPerOp: elapsed.inMicroseconds / config.iterations,
        iterations: config.iterations,
        warmupIterations: config.warmupIterations,
        sqlLength: sample.sql.length,
        bindingCount: sample.bindings.length,
        statementCount: sample.statementCount,
        method: sample.method,
        sqlSample: _sampleSql(sample.sql),
      );
    } catch (error, stackTrace) {
      return BenchmarkCaseResult(
        caseId: benchmarkCase.id,
        caseName: benchmarkCase.name,
        category: benchmarkCase.category,
        mode: benchmarkCase.mode.name,
        complexity: benchmarkCase.complexity,
        features: benchmarkCase.features,
        dialect: dialect.name,
        status: 'error',
        iterations: config.iterations,
        warmupIterations: config.warmupIterations,
        errorType: error.runtimeType.toString(),
        error: '$error\n${_firstStackLine(stackTrace)}',
      );
    }
  }

  BenchmarkCaseResult _unsupportedResult(
    BenchmarkCase benchmarkCase,
    KnexDialect dialect,
  ) {
    return BenchmarkCaseResult(
      caseId: benchmarkCase.id,
      caseName: benchmarkCase.name,
      category: benchmarkCase.category,
      mode: benchmarkCase.mode.name,
      complexity: benchmarkCase.complexity,
      features: benchmarkCase.features,
      dialect: dialect.name,
      status: 'unsupported_expected',
      iterations: config.iterations,
      warmupIterations: config.warmupIterations,
    );
  }

  Duration _time(BenchmarkBuild build, KnexDialect dialect, int iterations) {
    final sw = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      _lastOutput = build(dialect);
    }
    sw.stop();
    return sw.elapsed;
  }

  String _sampleSql(String sql) {
    const maxLength = 240;
    if (sql.length <= maxLength) return sql;
    return '${sql.substring(0, maxLength)}...';
  }

  String _firstStackLine(StackTrace stackTrace) {
    final lines = stackTrace.toString().split('\n');
    return lines.isEmpty ? '' : lines.first;
  }
}
