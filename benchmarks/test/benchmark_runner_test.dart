/// Tests for BenchmarkConfig, BenchmarkRun, BenchmarkCaseResult, and
/// BenchmarkRunner.
library;

import 'package:knex_dart/knex_dart.dart';
import 'package:knex_dart_benchmark/benchmark_case.dart';
import 'package:knex_dart_benchmark/benchmark_runner.dart';
import 'package:test/test.dart';

// ── Helpers ─────────────────────────────────────────────────────────────────

BenchmarkCase _simpleCase({
  String id = 'select_simple',
  String name = 'SELECT simple',
  String category = 'select',
  BenchmarkMode mode = BenchmarkMode.queryGeneration,
  String complexity = 'basic',
  List<String> features = const ['select'],
  Set<KnexDialect>? dialects,
}) {
  return BenchmarkCase(
    id: id,
    name: name,
    category: category,
    mode: mode,
    complexity: complexity,
    features: features,
    dialects: dialects,
    build: (dialect) => BenchmarkOutput.fromSqlString(
      KnexQuery.forDialect(dialect).from('users').select(['id']).toSQL(),
    ),
  );
}

BenchmarkCase _throwingCase({String id = 'error_case'}) {
  return BenchmarkCase(
    id: id,
    name: 'Throwing Case',
    category: 'error',
    mode: BenchmarkMode.queryGeneration,
    complexity: 'basic',
    features: [],
    build: (_) => throw StateError('build failed'),
  );
}

BenchmarkConfig _minimalConfig({
  List<KnexDialect>? dialects,
  bool includeUnsupported = true,
  int iterations = 1,
  int warmupIterations = 0,
}) {
  return BenchmarkConfig(
    iterations: iterations,
    warmupIterations: warmupIterations,
    dialects: dialects ?? [KnexDialect.sqlite],
    includeUnsupported: includeUnsupported,
  );
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  // ── BenchmarkConfig ────────────────────────────────────────────────────

  group('BenchmarkConfig', () {
    test('stores all fields', () {
      const cfg = BenchmarkConfig(
        iterations: 5000,
        warmupIterations: 500,
        dialects: [KnexDialect.postgres, KnexDialect.mysql],
        includeUnsupported: false,
      );
      expect(cfg.iterations, 5000);
      expect(cfg.warmupIterations, 500);
      expect(cfg.dialects, [KnexDialect.postgres, KnexDialect.mysql]);
      expect(cfg.includeUnsupported, isFalse);
    });

    test('includeUnsupported defaults to true', () {
      const cfg = BenchmarkConfig(
        iterations: 1,
        warmupIterations: 0,
        dialects: [KnexDialect.sqlite],
      );
      expect(cfg.includeUnsupported, isTrue);
    });

    group('toJson()', () {
      test('contains all expected keys', () {
        final cfg = BenchmarkConfig(
          iterations: 100,
          warmupIterations: 10,
          dialects: [KnexDialect.postgres, KnexDialect.sqlite],
          includeUnsupported: true,
        );
        final json = cfg.toJson();
        expect(json['iterations'], 100);
        expect(json['warmupIterations'], 10);
        expect(json['includeUnsupported'], isTrue);
        expect(json['dialects'], ['postgres', 'sqlite']);
      });

      test('dialects serialized as names list', () {
        final cfg = BenchmarkConfig(
          iterations: 1,
          warmupIterations: 0,
          dialects: [KnexDialect.mssql, KnexDialect.bigquery],
        );
        expect(cfg.toJson()['dialects'], ['mssql', 'bigquery']);
      });

      test('empty dialects list serializes as empty list', () {
        final cfg = BenchmarkConfig(
          iterations: 1,
          warmupIterations: 0,
          dialects: [],
        );
        expect(cfg.toJson()['dialects'], isEmpty);
      });
    });
  });

  // ── BenchmarkCaseResult ────────────────────────────────────────────────

  group('BenchmarkCaseResult', () {
    BenchmarkCaseResult _okResult({
      double? microsecondsPerOp,
      int? sqlLength,
      int? bindingCount,
      int? statementCount,
      String? method,
      String? sqlSample,
    }) {
      return BenchmarkCaseResult(
        caseId: 'sel_simple',
        caseName: 'SELECT simple',
        category: 'select',
        mode: 'queryGeneration',
        complexity: 'basic',
        features: ['select'],
        dialect: 'sqlite',
        status: 'ok',
        iterations: 100,
        warmupIterations: 10,
        microsecondsPerOp: microsecondsPerOp,
        sqlLength: sqlLength,
        bindingCount: bindingCount,
        statementCount: statementCount,
        method: method,
        sqlSample: sqlSample,
      );
    }

    group('toJson()', () {
      test('always includes required scalar fields', () {
        final result = _okResult();
        final json = result.toJson();
        expect(json['caseId'], 'sel_simple');
        expect(json['caseName'], 'SELECT simple');
        expect(json['category'], 'select');
        expect(json['mode'], 'queryGeneration');
        expect(json['complexity'], 'basic');
        expect(json['features'], ['select']);
        expect(json['dialect'], 'sqlite');
        expect(json['status'], 'ok');
        expect(json['iterations'], 100);
        expect(json['warmupIterations'], 10);
      });

      test('omits optional fields when null', () {
        final json = _okResult().toJson();
        expect(json, isNot(contains('microsecondsPerOp')));
        expect(json, isNot(contains('sqlLength')));
        expect(json, isNot(contains('bindingCount')));
        expect(json, isNot(contains('statementCount')));
        expect(json, isNot(contains('method')));
        expect(json, isNot(contains('sqlSample')));
        expect(json, isNot(contains('errorType')));
        expect(json, isNot(contains('error')));
      });

      test('includes optional fields when not null', () {
        final result = _okResult(
          microsecondsPerOp: 1.23,
          sqlLength: 42,
          bindingCount: 3,
          statementCount: 1,
          method: 'select',
          sqlSample: 'select "id" from "users"',
        );
        final json = result.toJson();
        expect(json['microsecondsPerOp'], 1.23);
        expect(json['sqlLength'], 42);
        expect(json['bindingCount'], 3);
        expect(json['statementCount'], 1);
        expect(json['method'], 'select');
        expect(json['sqlSample'], 'select "id" from "users"');
      });

      test('error result includes errorType and error fields', () {
        final result = BenchmarkCaseResult(
          caseId: 'err',
          caseName: 'Error Case',
          category: 'error',
          mode: 'queryGeneration',
          complexity: 'basic',
          features: [],
          dialect: 'sqlite',
          status: 'error',
          iterations: 10,
          warmupIterations: 0,
          errorType: 'StateError',
          error: 'build failed\n#0 ...',
        );
        final json = result.toJson();
        expect(json['status'], 'error');
        expect(json['errorType'], 'StateError');
        expect(json['error'], contains('build failed'));
      });
    });
  });

  // ── BenchmarkRunner ────────────────────────────────────────────────────

  group('BenchmarkRunner', () {
    test('run() returns BenchmarkRun with correct config reference', () {
      final cfg = _minimalConfig();
      final runner = BenchmarkRunner(
        cases: [_simpleCase()],
        config: cfg,
      );
      final run = runner.run();
      expect(run.config, same(cfg));
    });

    test('run() produces results for each case × dialect', () {
      final cfg = BenchmarkConfig(
        iterations: 1,
        warmupIterations: 0,
        dialects: [KnexDialect.sqlite, KnexDialect.postgres],
      );
      final runner = BenchmarkRunner(
        cases: [_simpleCase(id: 'a'), _simpleCase(id: 'b')],
        config: cfg,
      );
      final run = runner.run();
      // 2 cases × 2 dialects = 4 results (all supported because dialects=null)
      expect(run.results, hasLength(4));
    });

    test('run() result status is "ok" for successful builds', () {
      final runner = BenchmarkRunner(
        cases: [_simpleCase()],
        config: _minimalConfig(),
      );
      final result = runner.run().results.first;
      expect(result.status, 'ok');
    });

    test('run() result carries microsecondsPerOp as non-negative double', () {
      final runner = BenchmarkRunner(
        cases: [_simpleCase()],
        config: _minimalConfig(iterations: 10),
      );
      final result = runner.run().results.first;
      expect(result.microsecondsPerOp, isNotNull);
      expect(result.microsecondsPerOp!, greaterThanOrEqualTo(0));
    });

    test('run() result includes sqlLength, bindingCount, method, sqlSample', () {
      final runner = BenchmarkRunner(
        cases: [_simpleCase()],
        config: _minimalConfig(),
      );
      final result = runner.run().results.first;
      expect(result.sqlLength, isNotNull);
      expect(result.sqlLength!, greaterThan(0));
      expect(result.bindingCount, isNotNull);
      expect(result.method, isNotEmpty);
      expect(result.sqlSample, isNotEmpty);
    });

    test('run() produces "error" result when build throws', () {
      final runner = BenchmarkRunner(
        cases: [_throwingCase()],
        config: _minimalConfig(),
      );
      // run() would throw StateError('benchmark produced no SQL') if _lastOutput
      // never gets set, but in this case the first build call sets it... except
      // the error case doesn't set _lastOutput. We need a mix.
      // Instead test only the error path by pairing with a valid case.
      final runner2 = BenchmarkRunner(
        cases: [_simpleCase(), _throwingCase()],
        config: _minimalConfig(),
      );
      final run = runner2.run();
      final errorResult = run.results.firstWhere((r) => r.caseId == 'error_case');
      expect(errorResult.status, 'error');
      expect(errorResult.errorType, isNotNull);
      expect(errorResult.error, contains('build failed'));
    });

    test('run() error result has no microsecondsPerOp', () {
      final runner = BenchmarkRunner(
        cases: [_simpleCase(), _throwingCase()],
        config: _minimalConfig(),
      );
      final errorResult = runner
          .run()
          .results
          .firstWhere((r) => r.status == 'error');
      expect(errorResult.microsecondsPerOp, isNull);
    });

    group('unsupported dialect handling', () {
      test('includes "unsupported_expected" result when includeUnsupported=true', () {
        // Only postgres is supported by this case, but we run sqlite dialect.
        final c = _simpleCase(dialects: {KnexDialect.postgres});
        final runner = BenchmarkRunner(
          cases: [_simpleCase(), c],
          config: BenchmarkConfig(
            iterations: 1,
            warmupIterations: 0,
            dialects: [KnexDialect.sqlite],
            includeUnsupported: true,
          ),
        );
        final run = runner.run();
        final unsupported = run.results.where(
          (r) => r.status == 'unsupported_expected',
        );
        expect(unsupported, isNotEmpty);
      });

      test('excludes unsupported results when includeUnsupported=false', () {
        final c = _simpleCase(dialects: {KnexDialect.postgres});
        final runner = BenchmarkRunner(
          cases: [_simpleCase(), c],
          config: BenchmarkConfig(
            iterations: 1,
            warmupIterations: 0,
            dialects: [KnexDialect.sqlite],
            includeUnsupported: false,
          ),
        );
        final run = runner.run();
        final unsupported = run.results.where(
          (r) => r.status == 'unsupported_expected',
        );
        expect(unsupported, isEmpty);
      });
    });

    test('run() throws StateError when no cases produce any output', () {
      // All cases throw on build + no prior successful builds.
      final runner = BenchmarkRunner(
        cases: [],
        config: _minimalConfig(),
      );
      expect(() => runner.run(), throwsStateError);
    });

    test('run() BenchmarkRun.runId derived from startedAt ISO string', () {
      final runner = BenchmarkRunner(
        cases: [_simpleCase()],
        config: _minimalConfig(),
      );
      final run = runner.run();
      // runId should not contain colons (replaced by dashes)
      expect(run.runId, isNot(contains(':')));
    });

    test('run() BenchmarkRun.environment contains dartVersion key', () {
      final runner = BenchmarkRunner(
        cases: [_simpleCase()],
        config: _minimalConfig(),
      );
      final run = runner.run();
      expect(run.environment, contains('dartVersion'));
      expect(run.environment, contains('operatingSystem'));
      expect(run.environment, contains('numberOfProcessors'));
    });

    test('run() sets caseId, caseName, category correctly in result', () {
      final runner = BenchmarkRunner(
        cases: [
          _simpleCase(
            id: 'my_id',
            name: 'My Name',
            category: 'my_cat',
          ),
        ],
        config: _minimalConfig(),
      );
      final result = runner.run().results.first;
      expect(result.caseId, 'my_id');
      expect(result.caseName, 'My Name');
      expect(result.category, 'my_cat');
    });

    test('sqlSample truncated to 240 chars + ellipsis for long SQL', () {
      // Build a case that generates a very long SQL string via many columns.
      final manyColumns = List.generate(80, (i) => 'column_$i');
      final longSqlCase = BenchmarkCase(
        id: 'long_sql',
        name: 'Long SQL',
        category: 'select',
        mode: BenchmarkMode.queryGeneration,
        complexity: 'complex',
        features: ['select'],
        build: (dialect) => BenchmarkOutput.fromSqlString(
          KnexQuery.forDialect(dialect).from('t').select(manyColumns).toSQL(),
        ),
      );
      final runner = BenchmarkRunner(
        cases: [longSqlCase],
        config: _minimalConfig(),
      );
      final result = runner.run().results.first;
      if (result.sqlSample != null && result.sqlSample!.length > 240) {
        expect(result.sqlSample!, endsWith('...'));
        expect(result.sqlSample!.length, 243);
      }
    });
  });

  // ── BenchmarkRun.toJson() ──────────────────────────────────────────────

  group('BenchmarkRun.toJson()', () {
    BenchmarkRun _makeRun() {
      return BenchmarkRunner(
        cases: [_simpleCase()],
        config: _minimalConfig(iterations: 2, warmupIterations: 1),
      ).run();
    }

    test('contains runId, startedAt, config, results, environment', () {
      final json = _makeRun().toJson();
      expect(json, containsKey('runId'));
      expect(json, containsKey('startedAt'));
      expect(json, containsKey('config'));
      expect(json, containsKey('results'));
      expect(json, containsKey('environment'));
    });

    test('startedAt is an ISO 8601 UTC string', () {
      final json = _makeRun().toJson();
      final startedAt = json['startedAt'] as String;
      // Must parse without throwing and be UTC.
      final dt = DateTime.parse(startedAt);
      expect(dt.isUtc, isTrue);
    });

    test('results is a non-empty list', () {
      final json = _makeRun().toJson();
      expect(json['results'], isA<List>());
      expect((json['results'] as List), isNotEmpty);
    });

    test('config sub-map contains iterations and dialects', () {
      final json = _makeRun().toJson();
      final configJson = json['config'] as Map<String, dynamic>;
      expect(configJson['iterations'], 2);
      expect(configJson['warmupIterations'], 1);
      expect(configJson['dialects'], isA<List>());
    });
  });
}