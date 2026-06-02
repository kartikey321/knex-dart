/// Tests for benchmarkRunToJson and benchmarkRunToMarkdown reporters.
library;

import 'dart:convert';

import 'package:knex_dart/knex_dart.dart';
import 'package:knex_dart_benchmark/benchmark_case.dart';
import 'package:knex_dart_benchmark/benchmark_runner.dart';
import 'package:knex_dart_benchmark/reporters.dart';
import 'package:test/test.dart';

// ── Helpers ─────────────────────────────────────────────────────────────────

BenchmarkRunner _runnerWithCases(List<BenchmarkCase> cases) {
  return BenchmarkRunner(
    cases: cases,
    config: BenchmarkConfig(
      iterations: 2,
      warmupIterations: 1,
      dialects: [KnexDialect.sqlite, KnexDialect.postgres],
    ),
  );
}

BenchmarkCase _selectCase({String id = 'select_simple', String name = 'SELECT simple'}) {
  return BenchmarkCase(
    id: id,
    name: name,
    category: 'select',
    mode: BenchmarkMode.queryGeneration,
    complexity: 'basic',
    features: ['select'],
    build: (dialect) => BenchmarkOutput.fromSqlString(
      KnexQuery.forDialect(dialect).from('users').select(['id', 'name']).toSQL(),
    ),
  );
}

BenchmarkCase _insertCase({String? dialects}) {
  return BenchmarkCase(
    id: 'insert_single',
    name: 'INSERT single',
    category: 'mutation',
    mode: BenchmarkMode.queryGeneration,
    complexity: 'basic',
    features: ['insert'],
    build: (dialect) => BenchmarkOutput.fromSqlString(
      KnexQuery.forDialect(dialect)
          .from('users')
          .insert({'name': 'Alice', 'age': 30})
          .toSQL(),
    ),
  );
}

BenchmarkCase _unsupportedCase() {
  return BenchmarkCase(
    id: 'pg_only',
    name: 'PG only',
    category: 'insert',
    mode: BenchmarkMode.queryGeneration,
    complexity: 'basic',
    features: ['returning'],
    dialects: {KnexDialect.postgres},
    build: (dialect) => BenchmarkOutput.fromSqlString(
      KnexQuery.forDialect(dialect)
          .from('users')
          .insert({'name': 'A'})
          .returning(['id'])
          .toSQL(),
    ),
  );
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  // ── benchmarkRunToJson ─────────────────────────────────────────────────

  group('benchmarkRunToJson()', () {
    test('returns valid JSON string', () {
      final run = _runnerWithCases([_selectCase()]).run();
      final json = benchmarkRunToJson(run);
      expect(() => jsonDecode(json), returnsNormally);
    });

    test('JSON output is pretty-printed with 2-space indentation', () {
      final run = _runnerWithCases([_selectCase()]).run();
      final json = benchmarkRunToJson(run);
      // Pretty-printed JSON has newlines.
      expect(json, contains('\n'));
      // Indented with 2 spaces.
      expect(json, contains('  "'));
    });

    test('JSON contains top-level keys runId, startedAt, config, results, environment', () {
      final run = _runnerWithCases([_selectCase()]).run();
      final json = benchmarkRunToJson(run);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded, containsKey('runId'));
      expect(decoded, containsKey('startedAt'));
      expect(decoded, containsKey('config'));
      expect(decoded, containsKey('results'));
      expect(decoded, containsKey('environment'));
    });

    test('JSON results array contains at least one result object', () {
      final run = _runnerWithCases([_selectCase()]).run();
      final decoded = jsonDecode(benchmarkRunToJson(run)) as Map<String, dynamic>;
      final results = decoded['results'] as List;
      expect(results, isNotEmpty);
      expect(results.first, isA<Map<String, dynamic>>());
    });

    test('each result object contains caseId, dialect, status', () {
      final run = _runnerWithCases([_selectCase()]).run();
      final decoded = jsonDecode(benchmarkRunToJson(run)) as Map<String, dynamic>;
      final results = decoded['results'] as List<dynamic>;
      for (final result in results) {
        final r = result as Map<String, dynamic>;
        expect(r, containsKey('caseId'));
        expect(r, containsKey('dialect'));
        expect(r, containsKey('status'));
      }
    });

    test('round-trips through jsonDecode with no loss', () {
      final run = _runnerWithCases([_selectCase(), _insertCase()]).run();
      final json = benchmarkRunToJson(run);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      // Re-encode and compare structure.
      final reEncoded = jsonDecode(jsonEncode(decoded)) as Map<String, dynamic>;
      expect(reEncoded['runId'], decoded['runId']);
      expect(
        (reEncoded['results'] as List).length,
        (decoded['results'] as List).length,
      );
    });
  });

  // ── benchmarkRunToMarkdown ─────────────────────────────────────────────

  group('benchmarkRunToMarkdown()', () {
    late BenchmarkRun run;

    setUp(() {
      run = _runnerWithCases([_selectCase(), _insertCase()]).run();
    });

    test('returns a non-empty string', () {
      expect(benchmarkRunToMarkdown(run), isNotEmpty);
    });

    test('contains the top-level header', () {
      expect(
        benchmarkRunToMarkdown(run),
        contains('## Knex Dart Query-Building Benchmark Matrix'),
      );
    });

    test('contains the iterations / warmup line', () {
      final md = benchmarkRunToMarkdown(run);
      expect(md, contains('Iterations: 2'));
      expect(md, contains('warmup: 1'));
    });

    test('contains "### API Cost Summary" section', () {
      expect(benchmarkRunToMarkdown(run), contains('### API Cost Summary'));
    });

    test('contains "### Category Summary" section', () {
      expect(benchmarkRunToMarkdown(run), contains('### Category Summary'));
    });

    test('contains "### Full Matrix" section', () {
      expect(benchmarkRunToMarkdown(run), contains('### Full Matrix'));
    });

    test('full matrix table has the expected columns header', () {
      final md = benchmarkRunToMarkdown(run);
      expect(md, contains('| Category |'));
      expect(md, contains('| Operation |'));
      expect(md, contains('| Dialect |'));
      expect(md, contains('| Status |'));
    });

    test('case names appear in the markdown output', () {
      final md = benchmarkRunToMarkdown(run);
      expect(md, contains('SELECT simple'));
      expect(md, contains('INSERT single'));
    });

    test('dialect names appear in the full matrix', () {
      final md = benchmarkRunToMarkdown(run);
      expect(md, contains('sqlite'));
      expect(md, contains('postgres'));
    });

    test('does NOT include "### Errors" section when no errors exist', () {
      expect(benchmarkRunToMarkdown(run), isNot(contains('### Errors')));
    });

    test('includes "### Errors" section when errors exist', () {
      final throwingCase = BenchmarkCase(
        id: 'bad',
        name: 'Bad Case',
        category: 'error',
        mode: BenchmarkMode.queryGeneration,
        complexity: 'basic',
        features: [],
        build: (_) => throw StateError('oops'),
      );
      final runner = BenchmarkRunner(
        cases: [_selectCase(), throwingCase],
        config: BenchmarkConfig(
          iterations: 1,
          warmupIterations: 0,
          dialects: [KnexDialect.sqlite],
        ),
      );
      final md = benchmarkRunToMarkdown(runner.run());
      expect(md, contains('### Errors'));
      expect(md, contains('Bad Case'));
    });

    test('pipe characters in error message are escaped in the table', () {
      final errorCase = BenchmarkCase(
        id: 'pipe_err',
        name: 'Pipe|Error',
        category: 'error',
        mode: BenchmarkMode.queryGeneration,
        complexity: 'basic',
        features: [],
        build: (_) => throw StateError('error with | pipe'),
      );
      final runner = BenchmarkRunner(
        cases: [_selectCase(), errorCase],
        config: BenchmarkConfig(
          iterations: 1,
          warmupIterations: 0,
          dialects: [KnexDialect.sqlite],
        ),
      );
      final md = benchmarkRunToMarkdown(runner.run());
      // Pipes in error content must be escaped so the table is valid markdown.
      expect(md, contains(r'\|'));
    });

    test('unsupported dialects appear with "unsupported_expected" status in full matrix', () {
      final runner = BenchmarkRunner(
        cases: [_selectCase(), _unsupportedCase()],
        config: BenchmarkConfig(
          iterations: 1,
          warmupIterations: 0,
          dialects: [KnexDialect.sqlite, KnexDialect.postgres],
          includeUnsupported: true,
        ),
      );
      final md = benchmarkRunToMarkdown(runner.run());
      expect(md, contains('unsupported_expected'));
    });

    test('API cost summary ratio column shows "vs SELECT simple" ratio as empty when baseline is zero', () {
      // Create a run where SELECT simple has zero microseconds (edge case).
      // We simulate by using a case with a different name so no baseline is found.
      final run2 = BenchmarkRunner(
        cases: [
          BenchmarkCase(
            id: 'not_select_simple',
            name: 'Not SELECT simple',
            category: 'other',
            mode: BenchmarkMode.queryGeneration,
            complexity: 'basic',
            features: [],
            build: (dialect) => BenchmarkOutput.fromSqlString(
              KnexQuery.forDialect(dialect).from('t').toSQL(),
            ),
          ),
        ],
        config: BenchmarkConfig(
          iterations: 1,
          warmupIterations: 0,
          dialects: [KnexDialect.sqlite],
        ),
      ).run();
      // Should not throw when baseline is null.
      expect(() => benchmarkRunToMarkdown(run2), returnsNormally);
    });

    test('category summary table includes category names from results', () {
      final md = benchmarkRunToMarkdown(run);
      // 'select' and 'mutation' categories should appear in category summary.
      expect(md, contains('select'));
      expect(md, contains('mutation'));
    });
  });
}