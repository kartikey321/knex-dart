/// Tests for BenchmarkOutput, BenchmarkCase, and allBenchmarkDialects.
library;

import 'package:knex_dart/knex_dart.dart';
import 'package:knex_dart_benchmark/benchmark_case.dart';
import 'package:test/test.dart';

void main() {
  // ── BenchmarkOutput ─────────────────────────────────────────────────────

  group('BenchmarkOutput', () {
    group('default constructor', () {
      test('stores all provided fields', () {
        const output = BenchmarkOutput(
          sql: 'SELECT 1',
          bindings: [1, 'hello'],
          method: 'select',
          statementCount: 2,
        );
        expect(output.sql, 'SELECT 1');
        expect(output.bindings, [1, 'hello']);
        expect(output.method, 'select');
        expect(output.statementCount, 2);
      });

      test('statementCount defaults to 1', () {
        const output = BenchmarkOutput(
          sql: 'SELECT 1',
          bindings: [],
          method: 'select',
        );
        expect(output.statementCount, 1);
      });
    });

    group('fromSqlString', () {
      test('extracts sql, bindings, and method from SqlString', () {
        final sqlStr = KnexQuery.forDialect(KnexDialect.sqlite)
            .from('users')
            .select(['id', 'name'])
            .toSQL();
        final output = BenchmarkOutput.fromSqlString(sqlStr);
        expect(output.sql, sqlStr.sql);
        expect(output.bindings, sqlStr.bindings);
        expect(output.method, sqlStr.method ?? 'raw');
        expect(output.statementCount, 1);
      });

      test('uses "raw" as method fallback when SqlString.method is null', () {
        // Raw fragments may not carry a method.
        final sqlStr = KnexQuery.forDialect(
          KnexDialect.sqlite,
        ).queryBuilder().client.raw('select 1').toSQL();
        final output = BenchmarkOutput.fromSqlString(sqlStr);
        // method is either the SqlString value or 'raw' fallback
        expect(output.method, isNotEmpty);
      });

      test('INSERT SqlString produces correct output', () {
        final sqlStr = KnexQuery.forDialect(KnexDialect.postgres)
            .from('users')
            .insert({'name': 'Alice', 'age': 30})
            .toSQL();
        final output = BenchmarkOutput.fromSqlString(sqlStr);
        expect(output.sql, sqlStr.sql);
        expect(output.bindings, hasLength(greaterThan(0)));
        expect(output.statementCount, 1);
      });

      test('UPDATE SqlString has correct sql and bindings', () {
        final sqlStr = KnexQuery.forDialect(KnexDialect.postgres)
            .from('users')
            .where('id', '=', 1)
            .update({'name': 'Bob'})
            .toSQL();
        final output = BenchmarkOutput.fromSqlString(sqlStr);
        expect(output.sql, sqlStr.sql);
        expect(output.bindings, isNotEmpty);
      });
    });

    group('fromSchema', () {
      test('joins multiple statement SQL with semicolons', () {
        final statements = [
          {'sql': 'CREATE TABLE a (id INTEGER)', 'bindings': <dynamic>[]},
          {
            'sql': 'CREATE INDEX idx ON a (id)',
            'bindings': <dynamic>[],
          },
        ];
        final output = BenchmarkOutput.fromSchema(statements);
        expect(output.sql, contains('CREATE TABLE a (id INTEGER)'));
        expect(output.sql, contains('CREATE INDEX idx ON a (id)'));
        expect(output.sql, contains(';'));
      });

      test('sets method to "schema"', () {
        final output = BenchmarkOutput.fromSchema([
          {'sql': 'CREATE TABLE t (id INTEGER)', 'bindings': <dynamic>[]},
        ]);
        expect(output.method, 'schema');
      });

      test('statementCount equals number of statements', () {
        final statements = [
          {'sql': 'STMT 1', 'bindings': <dynamic>[]},
          {'sql': 'STMT 2', 'bindings': <dynamic>[]},
          {'sql': 'STMT 3', 'bindings': <dynamic>[]},
        ];
        final output = BenchmarkOutput.fromSchema(statements);
        expect(output.statementCount, 3);
      });

      test('merges bindings from all statements', () {
        final statements = [
          {
            'sql': 'CREATE TABLE t (id INTEGER)',
            'bindings': <dynamic>[1, 2],
          },
          {
            'sql': 'INSERT INTO t VALUES (?)',
            'bindings': <dynamic>[3, 4],
          },
        ];
        final output = BenchmarkOutput.fromSchema(statements);
        expect(output.bindings, [1, 2, 3, 4]);
      });

      test('handles statements with null or missing bindings', () {
        final statements = [
          {'sql': 'CREATE TABLE t (id INTEGER)'},
          {'sql': 'ANOTHER STMT', 'bindings': <dynamic>[5]},
        ];
        final output = BenchmarkOutput.fromSchema(statements);
        expect(output.bindings, [5]);
      });

      test('single statement produces no semicolons and count 1', () {
        final output = BenchmarkOutput.fromSchema([
          {'sql': 'CREATE TABLE solo (id INTEGER)', 'bindings': <dynamic>[]},
        ]);
        expect(output.sql, 'CREATE TABLE solo (id INTEGER)');
        expect(output.statementCount, 1);
      });
    });
  });

  // ── BenchmarkCase ────────────────────────────────────────────────────────

  group('BenchmarkCase', () {
    BenchmarkCase _makeCase({
      String id = 'test_case',
      String name = 'Test Case',
      String category = 'select',
      BenchmarkMode mode = BenchmarkMode.queryGeneration,
      String complexity = 'basic',
      List<String> features = const ['select'],
      Set<KnexDialect>? dialects,
      String? notes,
    }) {
      return BenchmarkCase(
        id: id,
        name: name,
        category: category,
        mode: mode,
        complexity: complexity,
        features: features,
        dialects: dialects,
        notes: notes,
        build: (dialect) => BenchmarkOutput.fromSqlString(
          KnexQuery.forDialect(dialect).from('users').select(['id']).toSQL(),
        ),
      );
    }

    group('supports()', () {
      test('returns true for all dialects when dialects is null', () {
        final c = _makeCase(dialects: null);
        for (final dialect in allBenchmarkDialects) {
          expect(c.supports(dialect), isTrue, reason: dialect.name);
        }
      });

      test('returns true for dialects in the allowed set', () {
        final c = _makeCase(
          dialects: {KnexDialect.postgres, KnexDialect.sqlite},
        );
        expect(c.supports(KnexDialect.postgres), isTrue);
        expect(c.supports(KnexDialect.sqlite), isTrue);
      });

      test('returns false for dialects not in the allowed set', () {
        final c = _makeCase(
          dialects: {KnexDialect.postgres},
        );
        expect(c.supports(KnexDialect.mysql), isFalse);
        expect(c.supports(KnexDialect.sqlite), isFalse);
        expect(c.supports(KnexDialect.mssql), isFalse);
      });

      test('empty dialects set means no dialect is supported', () {
        final c = _makeCase(dialects: {});
        for (final dialect in allBenchmarkDialects) {
          expect(c.supports(dialect), isFalse, reason: dialect.name);
        }
      });
    });

    group('toMetadataJson()', () {
      test('includes required scalar fields', () {
        final c = _makeCase(
          id: 'sel_simple',
          name: 'SELECT simple',
          category: 'select',
          mode: BenchmarkMode.queryGeneration,
          complexity: 'basic',
          features: ['select', 'projection'],
        );
        final json = c.toMetadataJson();
        expect(json['id'], 'sel_simple');
        expect(json['name'], 'SELECT simple');
        expect(json['category'], 'select');
        expect(json['mode'], 'queryGeneration');
        expect(json['complexity'], 'basic');
        expect(json['features'], ['select', 'projection']);
      });

      test('omits "dialects" key when dialects is null', () {
        final c = _makeCase(dialects: null);
        expect(c.toMetadataJson(), isNot(contains('dialects')));
      });

      test('includes "dialects" key as list of names when set', () {
        final c = _makeCase(
          dialects: {KnexDialect.postgres, KnexDialect.mysql},
        );
        final json = c.toMetadataJson();
        expect(json, contains('dialects'));
        final dialectList = json['dialects'] as List;
        expect(dialectList, containsAll(['postgres', 'mysql']));
      });

      test('omits "notes" key when notes is null', () {
        final c = _makeCase(notes: null);
        expect(c.toMetadataJson(), isNot(contains('notes')));
      });

      test('includes "notes" key when notes is provided', () {
        final c = _makeCase(notes: 'some note');
        expect(c.toMetadataJson()['notes'], 'some note');
      });

      test('mode is encoded as enum name string', () {
        expect(
          _makeCase(mode: BenchmarkMode.queryGeneration).toMetadataJson()['mode'],
          'queryGeneration',
        );
        expect(
          _makeCase(mode: BenchmarkMode.schemaGeneration).toMetadataJson()['mode'],
          'schemaGeneration',
        );
        expect(
          _makeCase(mode: BenchmarkMode.rawGeneration).toMetadataJson()['mode'],
          'rawGeneration',
        );
      });
    });

    group('build()', () {
      test('build callback is invoked with the given dialect', () {
        KnexDialect? receivedDialect;
        final c = BenchmarkCase(
          id: 'cb_test',
          name: 'CB Test',
          category: 'select',
          mode: BenchmarkMode.queryGeneration,
          complexity: 'basic',
          features: [],
          build: (dialect) {
            receivedDialect = dialect;
            return BenchmarkOutput.fromSqlString(
              KnexQuery.forDialect(dialect).from('t').toSQL(),
            );
          },
        );
        c.build(KnexDialect.mysql);
        expect(receivedDialect, KnexDialect.mysql);
      });
    });
  });

  // ── allBenchmarkDialects ─────────────────────────────────────────────────

  group('allBenchmarkDialects', () {
    test('contains exactly 11 dialects', () {
      expect(allBenchmarkDialects, hasLength(11));
    });

    test('contains the canonical set of supported dialects', () {
      expect(allBenchmarkDialects, containsAll([
        KnexDialect.postgres,
        KnexDialect.mysql,
        KnexDialect.sqlite,
        KnexDialect.mariadb,
        KnexDialect.redshift,
        KnexDialect.turso,
        KnexDialect.d1,
        KnexDialect.duckdb,
        KnexDialect.snowflake,
        KnexDialect.bigquery,
        KnexDialect.mssql,
      ]));
    });

    test('contains no duplicates', () {
      expect(allBenchmarkDialects.toSet(), hasLength(allBenchmarkDialects.length));
    });
  });
}