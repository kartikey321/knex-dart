import 'dart:convert';
import 'dart:io';

import 'package:knex_dart_live_test/knex_dart_live_test.dart';
import 'package:test/test.dart';

void main() {
  group('ExecutableCasesRoadmap.load', () {
    test('loads the real roadmap and finds postgres', () {
      final roadmap = ExecutableCasesRoadmap.load();
      final pg = roadmap.forDialect('postgres');
      expect(pg.executableQueryIds, isNotEmpty);
      expect(pg.executableSchemaIds, isNotEmpty);
    });

    test('throws for an unknown dialect rather than returning empty', () {
      final roadmap = ExecutableCasesRoadmap.load();
      expect(
        () => roadmap.forDialect('not-a-real-dialect'),
        throwsArgumentError,
      );
    });
  });

  group('validateRoadmapAgainstCorpus', () {
    test('the real roadmap and real corpus agree for every dialect', () {
      final roadmap = ExecutableCasesRoadmap.load();
      for (final dialect in roadmap.dialects.keys) {
        // Should not throw.
        validateRoadmapAgainstCorpus(
          roadmap: roadmap,
          dialect: dialect,
          queryCorpusIds: queryCorpusCases.keys.toSet(),
          schemaCorpusIds: schemaCorpusCases.keys.toSet(),
        );
      }
    });

    test('throws when the roadmap references an id missing from the corpus', () {
      final roadmap = ExecutableCasesRoadmap(
        knexVersion: 'test',
        generatedAt: 'test',
        dialects: {
          'postgres': const DialectRoadmap(
            dialect: 'postgres',
            executableQueryIds: ['definitely/not-a-real-case-id'],
            refusedQueryIds: {},
            executableSchemaIds: [],
            refusedSchemaIds: {},
          ),
        },
      );
      expect(
        () => validateRoadmapAgainstCorpus(
          roadmap: roadmap,
          dialect: 'postgres',
          queryCorpusIds: queryCorpusCases.keys.toSet(),
          schemaCorpusIds: schemaCorpusCases.keys.toSet(),
        ),
        throwsA(isA<RoadmapCorpusMismatch>()),
      );
    });
  });

  group('collectDialectReport', () {
    late ExecutableCasesRoadmap roadmap;

    setUpAll(() {
      roadmap = ExecutableCasesRoadmap.load();
    });

    test('with no results supplied, every roadmap id is unclassified — '
        'the honest report before any adapter exists', () {
      final report = collectDialectReport(roadmap: roadmap, dialect: 'postgres');
      final pg = roadmap.forDialect('postgres');

      expect(report.queryRows.length, pg.executableQueryIds.length);
      expect(report.schemaRows.length, pg.executableSchemaIds.length);
      expect(
        report.queryRows.every(
          (r) => r.mechanical.status == MechanicalStatus.unclassified,
        ),
        true,
      );
      expect(
        report.schemaRows.every(
          (r) => r.mechanical.status == MechanicalStatus.unclassified,
        ),
        true,
      );

      // The summary's buckets must sum to the roadmap size — no id can be
      // silently absent from the accounting.
      final qs = report.querySummary;
      expect(
        qs.executedWithoutError +
            qs.executionFailed +
            qs.unclassified +
            qs.deferredFixture +
            qs.unsupportedEngine +
            qs.environmentUnavailable,
        qs.roadmapExecutable,
      );
    });

    test('supplied results override the unclassified default, and behavior '
        'specs are tracked separately from the mechanical status', () {
      final pg = roadmap.forDialect('postgres');
      final someId = pg.executableQueryIds.first;

      final report = collectDialectReport(
        roadmap: roadmap,
        dialect: 'postgres',
        queryResults: {
          someId: const MechanicalResult(
            MechanicalStatus.executedWithoutError,
            fixtureProfile: 'canonical_seed_v1',
          ),
        },
        queryBehavioral: {
          someId: const [
            BehavioralResult(description: 'proves X', passed: true),
          ],
        },
      );

      final row = report.queryRows.firstWhere((r) => r.id == someId);
      expect(row.mechanical.status, MechanicalStatus.executedWithoutError);
      expect(row.mechanical.fixtureProfile, 'canonical_seed_v1');
      expect(row.behavioral.single.passed, true);

      final untouchedRow = report.queryRows.firstWhere((r) => r.id != someId);
      expect(untouchedRow.mechanical.status, MechanicalStatus.unclassified);
      expect(untouchedRow.behavioral, isEmpty);

      final summary = report.querySummary;
      expect(summary.executedWithoutError, 1);
      expect(summary.behaviorSpecsRegistered, 1);
      expect(summary.behaviorSpecsPassed, 1);
    });
  });

  group('LiveExecutionReport', () {
    test('round-trips through JSON and renders the required Markdown labels, '
        'writing real files to a scratch directory', () async {
      final roadmap = ExecutableCasesRoadmap.load();
      final report = LiveExecutionReport(
        generatedAt: '2026-09-04T00:00:00Z',
        knexVersion: roadmap.knexVersion,
        dialectReports: [
          collectDialectReport(roadmap: roadmap, dialect: 'postgres'),
        ],
      );

      final scratchDir = await Directory.systemTemp.createTemp(
        'knex_dart_live_test_report_',
      );
      addTearDown(() => scratchDir.delete(recursive: true));

      final jsonPath = '${scratchDir.path}/postgres.json';
      final mdPath = '${scratchDir.path}/postgres.md';
      await report.writeTo(jsonPath: jsonPath, markdownPath: mdPath);

      final writtenJson =
          jsonDecode(await File(jsonPath).readAsString()) as Map<String, dynamic>;
      expect(writtenJson['knexVersion'], roadmap.knexVersion);
      expect((writtenJson['dialects'] as List).single['dialect'], 'postgres');

      final markdown = await File(mdPath).readAsString();
      // The exact labels required by design — never bare "coverage".
      expect(markdown, contains('**Executed without error**'));
      expect(markdown, contains('**Behaviorally verified**'));
      expect(markdown, isNot(contains('Coverage:')));
    });
  });
}
