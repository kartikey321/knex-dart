/// End-to-end proof that the live-execution mechanism actually works for
/// postgres: every case linked in `fixtureLinksByDialect` (across all three
/// profiles applied together — canonical_seed_v1, synthetic_join_v1,
/// synthetic_aggregate_v1) executes without error through the real
/// [PostgresLiveAdapter], and every profile's row counts are unchanged
/// afterward — proving the rollback-only isolation actually held across
/// all of them, not just that each one didn't throw.
@Tags(['postgres'])
library;

import 'package:universal_io/io.dart';

import 'package:knex_dart_live_test/knex_dart_live_test.dart';
import 'package:knex_dart_postgres/knex_dart_postgres.dart';
import 'package:test/test.dart';

import 'postgres_live_adapter.dart';

/// Expected row count per table, keyed by the fixture profile that seeds
/// it — used both to apply every profile at setup and to verify isolation
/// held afterward.
const _expectedCounts = {
  'canonical_seed_v1': {'users': 5, 'products': 5, 'orders': 7},
  'synthetic_join_v1': {'a': 2, 'b': 2, 'c': 2},
  'synthetic_aggregate_v1': {'t': 3, 'src': 2, 'inner_t': 2},
};

void main() {
  late PostgresClient client;
  late PostgresLiveAdapter adapter;

  setUpAll(() async {
    final host = Platform.environment['PG_HOST'] ?? 'localhost';
    final port = int.parse(Platform.environment['PG_PORT'] ?? '5432');
    final database = Platform.environment['PG_DATABASE'] ?? 'knex_test';
    final username = Platform.environment['PG_USER'] ?? 'test';
    final password = Platform.environment['PG_PASSWORD'] ?? 'test';

    client = await PostgresClient.connect(
      host: host,
      port: port,
      database: database,
      username: username,
      password: password,
    );
    adapter = PostgresLiveAdapter(client);
    await adapter.setUpRun();
    for (final profileId in _expectedCounts.keys) {
      await adapter.applyFixtureProfile(profileId);
    }
  });

  tearDownAll(() async {
    await adapter.tearDownRun(runSucceeded: true);
    await client.close();
  });

  test('every fixture-linked case executes without error', () async {
    final links = fixtureLinksByDialect['postgres']!;
    final failures = <String>[];

    for (final entry in links.entries) {
      final corpusCase = queryCorpusCases[entry.key]!;
      final result = await adapter.runCase(
        caseId: entry.key,
        fixtureProfileId: entry.value,
        body: (session) async {
          await session.execute(corpusCase.buildValidated('postgres'));
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
          final counts = await client.rawSql(
            'select count(*) as n from '
            '"${adapter.schemaName}"."${tableEntry.key}"',
          );
          expect(
            counts.single['n'],
            tableEntry.value,
            reason: '${profileEntry.key}.${tableEntry.key}',
          );
        }
      }
    },
  );
}
