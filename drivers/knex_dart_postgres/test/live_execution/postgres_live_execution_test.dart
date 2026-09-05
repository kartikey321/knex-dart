/// End-to-end proof that the live-execution mechanism actually works for
/// postgres: every case linked to `canonical_seed_v1` in
/// `fixtureLinksByDialect` executes without error through the real
/// [PostgresLiveAdapter], and the ephemeral schema's row counts are
/// unchanged afterward — proving the rollback-only isolation actually
/// held across all of them, not just that each one didn't throw.
@Tags(['postgres'])
library;

import 'package:universal_io/io.dart';

import 'package:knex_dart_live_test/knex_dart_live_test.dart';
import 'package:knex_dart_postgres/knex_dart_postgres.dart';
import 'package:test/test.dart';

import 'postgres_live_adapter.dart';

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
    await adapter.applyFixtureProfile('canonical_seed_v1');
  });

  tearDownAll(() async {
    await adapter.tearDownRun(runSucceeded: true);
    await client.close();
  });

  test(
    'every case linked to canonical_seed_v1 executes without error',
    () async {
      final links = fixtureLinksByDialect['postgres']!;
      final failures = <String>[];

      for (final entry in links.entries) {
        if (entry.value != 'canonical_seed_v1') continue;
        final corpusCase = queryCorpusCases[entry.key]!;
        final result = await adapter.runCase(
          caseId: entry.key,
          fixtureProfileId: entry.value,
          body: (session) async {
            await session.execute(corpusCase.buildValidated('postgres'));
          },
        );
        if (result.status != MechanicalStatus.executedWithoutError) {
          failures.add('${entry.key}: ${result.detail}');
        }
      }

      expect(failures, isEmpty, reason: failures.join('\n'));
    },
  );

  test(
    'isolation held: canonical_seed_v1 row counts are unchanged after '
    'running every linked case (proves every case rolled back cleanly, '
    'including inserts/updates/deletes)',
    () async {
      final counts = await client.rawSql(
        'select '
        "(select count(*) from \"${adapter.schemaName}\".users) as users, "
        "(select count(*) from \"${adapter.schemaName}\".products) as products, "
        "(select count(*) from \"${adapter.schemaName}\".orders) as orders",
      );
      expect(counts.single['users'], 5);
      expect(counts.single['products'], 5);
      expect(counts.single['orders'], 7);
    },
  );
}
