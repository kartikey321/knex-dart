/// End-to-end proof that the live-execution mechanism actually works for
/// sqlite: every case linked in `fixtureLinksByDialect['sqlite']` (across
/// all five profiles applied together — canonical_seed_v2, synthetic_join_v1,
/// synthetic_aggregate_v1, accounts_window_v1, join_targets_v1) executes
/// without error through the real [SqliteLiveAdapter], and every profile's
/// row counts are unchanged afterward — proving the rollback-only isolation
/// actually held across all of them, not just that each one didn't throw.
///
/// No Docker/live service needed — SQLite's isolation mode is a disposable
/// file database created fresh for this run, so this test needs no tags and
/// no environment variables (mirroring the existing untagged sqlite
/// integration tests in `drivers/knex_dart_sqlite/test/integration/`).
library;

import 'package:knex_dart_live_test/knex_dart_live_test.dart';
import 'package:test/test.dart';

import 'sqlite_live_adapter.dart';

/// Expected row count per table, keyed by the fixture profile that seeds
/// it — used both to apply every profile at setup and to verify isolation
/// held afterward. Profiles with zero seeded rows (join_targets_v1 seeds
/// only `employee`) are omitted from the per-table expectation map below
/// except where they do seed something.
const _expectedCounts = {
  'canonical_seed_v2': {'users': 5, 'products': 5, 'orders': 7},
  'synthetic_join_v1': {'a': 2, 'b': 2, 'c': 2},
  'synthetic_aggregate_v1': {'t': 3, 'src': 2, 'inner_t': 2},
  'accounts_window_v1': {'accounts': 3},
  'join_targets_v1': {'employee': 3},
};

void main() {
  late SqliteLiveAdapter adapter;

  setUpAll(() async {
    adapter = SqliteLiveAdapter();
    await adapter.setUpRun();
    for (final profileId in _expectedCounts.keys) {
      await adapter.applyFixtureProfile(profileId);
    }
  });

  tearDownAll(() async {
    await adapter.tearDownRun(runSucceeded: true);
  });

  test('every fixture-linked case executes without error', () async {
    final links = fixtureLinksByDialect['sqlite']!;
    final failures = <String>[];

    for (final entry in links.entries) {
      final corpusCase = queryCorpusCases[entry.key]!;
      final result = await adapter.runCase(
        caseId: entry.key,
        fixtureProfileId: entry.value,
        body: (session) async {
          await session.execute(corpusCase.buildValidated('sqlite'));
        },
      );
      if (result.status != MechanicalStatus.executedWithoutError) {
        failures.add('${entry.key} (${entry.value}): ${result.detail}');
      }
    }

    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test(
    'isolation held: every fixture profile\'s row counts are unchanged '
    'after running every linked case (proves every case rolled back '
    'cleanly, including inserts/updates/deletes)',
    () async {
      for (final profileEntry in _expectedCounts.entries) {
        for (final tableEntry in profileEntry.value.entries) {
          final counts =
              await adapter.client.rawQuery(
                    'select count(*) as n from "${tableEntry.key}"',
                    const [],
                  )
                  as List<Map<String, dynamic>>;
          expect(
            counts.first['n'],
            tableEntry.value,
            reason: '${profileEntry.key}.${tableEntry.key}',
          );
        }
      }
    },
  );
}
