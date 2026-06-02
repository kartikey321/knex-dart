import 'dart:convert';
import 'dart:io';

import 'package:knex_dart/knex_dart.dart';
import 'package:knex_dart_benchmark/benchmark_case.dart';
import 'package:knex_dart_benchmark/benchmark_runner.dart';
import 'package:knex_dart_benchmark/dialect_cases.dart';
import 'package:knex_dart_benchmark/reporters.dart';

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  final runner = BenchmarkRunner(
    cases: sqlGenerationCases,
    config: BenchmarkConfig(
      iterations: options.iterations,
      warmupIterations: options.warmupIterations,
      dialects: options.dialects,
      includeUnsupported: true,
    ),
  );

  final run = runner.run();
  final markdown = benchmarkRunToMarkdown(run);
  final outputDir = Directory(options.outputDirectory);
  if (!outputDir.existsSync()) {
    outputDir.createSync(recursive: true);
  }

  File(
    '${outputDir.path}/latest.json',
  ).writeAsStringSync(benchmarkRunToJson(run));
  File('${outputDir.path}/latest.md').writeAsStringSync(markdown);
  File('${outputDir.path}/operations.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(matrixCoverageMetadata),
  );

  print(markdown);
}

class _Options {
  final int iterations;
  final int warmupIterations;
  final String outputDirectory;
  final List<KnexDialect> dialects;

  const _Options({
    required this.iterations,
    required this.warmupIterations,
    required this.outputDirectory,
    required this.dialects,
  });

  factory _Options.parse(List<String> args) {
    var iterations = 10000;
    var warmupIterations = 1000;
    var outputDirectory = 'benchmarks/results';
    var dialects = allBenchmarkDialects;

    for (final arg in args) {
      if (arg.startsWith('--iterations=')) {
        iterations = _parsePositiveInt(arg, '--iterations=');
      } else if (arg.startsWith('--warmup=')) {
        warmupIterations = _parsePositiveInt(arg, '--warmup=');
      } else if (arg.startsWith('--out=')) {
        outputDirectory = arg.substring('--out='.length);
      } else if (arg.startsWith('--dialects=')) {
        dialects = _parseDialects(arg.substring('--dialects='.length));
      } else {
        throw ArgumentError('Unknown argument: $arg');
      }
    }

    return _Options(
      iterations: iterations,
      warmupIterations: warmupIterations,
      outputDirectory: outputDirectory,
      dialects: dialects,
    );
  }

  static int _parsePositiveInt(String arg, String prefix) {
    final value = int.tryParse(arg.substring(prefix.length));
    if (value == null || value <= 0) {
      throw ArgumentError('$prefix must be a positive integer');
    }
    return value;
  }

  static List<KnexDialect> _parseDialects(String value) {
    final names = value
        .split(',')
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty);
    final dialects = <KnexDialect>[];
    for (final name in names) {
      dialects.add(
        KnexDialect.values.firstWhere(
          (dialect) => dialect.name == name,
          orElse: () => throw ArgumentError('Unknown dialect: $name'),
        ),
      );
    }
    if (dialects.isEmpty) {
      throw ArgumentError('--dialects must contain at least one dialect');
    }
    return dialects;
  }
}
