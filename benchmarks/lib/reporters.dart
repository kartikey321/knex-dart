import 'dart:convert';

import 'benchmark_runner.dart';

String benchmarkRunToJson(BenchmarkRun run) {
  return const JsonEncoder.withIndent('  ').convert(run.toJson());
}

String benchmarkRunToMarkdown(BenchmarkRun run) {
  final buffer = StringBuffer()
    ..writeln('## Knex Dart Query-Building Benchmark Matrix')
    ..writeln()
    ..writeln(
      'Iterations: ${run.config.iterations}, '
      'warmup: ${run.config.warmupIterations}',
    )
    ..writeln()
    ..writeln('### API Cost Summary')
    ..writeln()
    ..writeln(
      '| Operation | Category | Avg us/op | vs SELECT simple | Min us/op | Max us/op | Dialects | Status |',
    )
    ..writeln(
      '|-----------|----------|-----------|------------------|-----------|-----------|----------|--------|',
    );

  final summaries = _summaries(run.results);
  final baseline = _baseline(summaries);
  for (final summary in summaries) {
    buffer.writeln(
      '| ${summary.caseName} '
      '| ${summary.category} '
      '| ${summary.average.toStringAsFixed(2)} '
      '| ${_formatRatio(summary.average, baseline)} '
      '| ${summary.minimum.toStringAsFixed(2)} '
      '| ${summary.maximum.toStringAsFixed(2)} '
      '| ${summary.measuredDialects} '
      '| ${summary.status} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('### Category Summary')
    ..writeln()
    ..writeln('| Category | Cases | Avg us/op | Max case | Max avg us/op |')
    ..writeln('|----------|-------|-----------|----------|---------------|');

  for (final category in _categorySummaries(summaries)) {
    buffer.writeln(
      '| ${category.category} '
      '| ${category.caseCount} '
      '| ${category.average.toStringAsFixed(2)} '
      '| ${category.maxCaseName} '
      '| ${category.maxAverage.toStringAsFixed(2)} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('### Full Matrix')
    ..writeln()
    ..writeln(
      '| Category | Operation | Dialect | Status | us/op | Bindings | SQL len | Statements |',
    )
    ..writeln(
      '|----------|-----------|---------|--------|-------|----------|---------|------------|',
    );

  for (final result in run.results) {
    buffer.writeln(
      '| ${result.category} '
      '| ${result.caseName} '
      '| ${result.dialect} '
      '| ${result.status} '
      '| ${_formatMicros(result.microsecondsPerOp)} '
      '| ${result.bindingCount ?? ''} '
      '| ${result.sqlLength ?? ''} '
      '| ${result.statementCount ?? ''} |',
    );
  }

  final errors = run.results.where((result) => result.status == 'error');
  if (errors.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('### Errors')
      ..writeln()
      ..writeln('| Operation | Dialect | Error |')
      ..writeln('|-----------|---------|-------|');
    for (final result in errors) {
      buffer.writeln(
        '| ${result.caseName} '
        '| ${result.dialect} '
        '| ${_escapeCell(result.errorType ?? result.error ?? 'error')} |',
      );
    }
  }

  return buffer.toString();
}

List<_OperationSummary> _summaries(List<BenchmarkCaseResult> results) {
  final byCase = <String, List<BenchmarkCaseResult>>{};
  for (final result in results) {
    byCase.putIfAbsent(result.caseId, () => []).add(result);
  }

  return [for (final entries in byCase.values) _summarize(entries)];
}

double? _baseline(List<_OperationSummary> summaries) {
  for (final summary in summaries) {
    if (summary.caseName == 'SELECT simple' && summary.average > 0) {
      return summary.average;
    }
  }
  return null;
}

List<_CategorySummary> _categorySummaries(List<_OperationSummary> summaries) {
  final byCategory = <String, List<_OperationSummary>>{};
  for (final summary in summaries.where((summary) => summary.average > 0)) {
    byCategory.putIfAbsent(summary.category, () => []).add(summary);
  }

  final categorySummaries = <_CategorySummary>[];
  for (final entry in byCategory.entries) {
    var total = 0.0;
    var max = entry.value.first;
    for (final summary in entry.value) {
      total += summary.average;
      if (summary.average > max.average) {
        max = summary;
      }
    }

    categorySummaries.add(
      _CategorySummary(
        category: entry.key,
        caseCount: entry.value.length,
        average: total / entry.value.length,
        maxCaseName: max.caseName,
        maxAverage: max.average,
      ),
    );
  }

  categorySummaries.sort((a, b) => b.average.compareTo(a.average));
  return categorySummaries;
}

_OperationSummary _summarize(List<BenchmarkCaseResult> entries) {
  final measured = entries
      .where((entry) => entry.status == 'ok' && entry.microsecondsPerOp != null)
      .toList();
  if (measured.isEmpty) {
    final statuses = entries.map((entry) => entry.status).toSet().join(',');
    return _OperationSummary(
      caseName: entries.first.caseName,
      category: entries.first.category,
      average: 0,
      minimum: 0,
      maximum: 0,
      measuredDialects: 0,
      status: statuses,
    );
  }

  var total = 0.0;
  var minimum = measured.first.microsecondsPerOp!;
  var maximum = measured.first.microsecondsPerOp!;
  for (final entry in measured.skip(1)) {
    final value = entry.microsecondsPerOp!;
    if (value < minimum) minimum = value;
    if (value > maximum) maximum = value;
  }
  for (final entry in measured) {
    total += entry.microsecondsPerOp!;
  }
  final average = total / measured.length;

  final unsupportedCount = entries
      .where((entry) => entry.status == 'unsupported_expected')
      .length;
  final errorCount = entries.where((entry) => entry.status == 'error').length;
  final status = [
    '${measured.length} ok',
    if (unsupportedCount > 0) '$unsupportedCount unsupported',
    if (errorCount > 0) '$errorCount error',
  ].join(', ');

  return _OperationSummary(
    caseName: entries.first.caseName,
    category: entries.first.category,
    average: average,
    minimum: minimum,
    maximum: maximum,
    measuredDialects: measured.length,
    status: status,
  );
}

String _formatMicros(double? value) {
  if (value == null) return '';
  return value.toStringAsFixed(2);
}

String _formatRatio(double value, double? baseline) {
  if (baseline == null || baseline == 0 || value == 0) return '';
  return '${(value / baseline).toStringAsFixed(2)}x';
}

String _escapeCell(String value) {
  return value.replaceAll('|', r'\|').replaceAll('\n', ' ');
}

class _OperationSummary {
  final String caseName;
  final String category;
  final double average;
  final double minimum;
  final double maximum;
  final int measuredDialects;
  final String status;

  const _OperationSummary({
    required this.caseName,
    required this.category,
    required this.average,
    required this.minimum,
    required this.maximum,
    required this.measuredDialects,
    required this.status,
  });
}

class _CategorySummary {
  final String category;
  final int caseCount;
  final double average;
  final String maxCaseName;
  final double maxAverage;

  const _CategorySummary({
    required this.category,
    required this.caseCount,
    required this.average,
    required this.maxCaseName,
    required this.maxAverage,
  });
}
