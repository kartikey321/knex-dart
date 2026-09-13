/// End-to-end proof that the live-execution mechanism works for postgres's
/// schema-DDL corpus: every case linked in
/// `fixtureLinksByDialect['postgres']` under a `schema/*` id executes
/// without error, and every case listed in
/// `unsupportedEngineAllowlist['postgres']` under a `schema/*` id still
/// reproduces its documented failure.
///
/// Unlike `postgres_live_execution_test.dart` (the query corpus, one shared
/// schema/run for the whole file), EVERY schema-DDL case here gets its own
/// fresh, disposable schema — see `postgres_schema_ddl_profiles.dart`'s
/// docstring for why a shared schema can't work for this corpus (DDL cases
/// routinely need opposite starting states for the identical table/column/
/// constraint name).
@Tags(['postgres'])
library;

import 'package:universal_io/io.dart';

import 'package:knex_dart_live_test/knex_dart_live_test.dart';
import 'package:knex_dart_postgres/knex_dart_postgres.dart';
import 'package:test/test.dart';

import 'postgres_live_adapter.dart';

void main() {
  late PostgresClient client;

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
  });

  tearDownAll(() => client.close());

  /// Runs [caseId] under [profileId] in its own fresh schema and returns
  /// the mechanical outcome. Always tears down (including the
  /// withSchema()-created named schemas, which live alongside — not
  /// inside — the per-case ephemeral schema).
  Future<MechanicalResult> runSchemaCase(String caseId, String profileId) async {
    final adapter = PostgresLiveAdapter(client);
    await adapter.setUpRun();
    var succeeded = false;
    try {
      await adapter.applySchemaDdlProfile(profileId);
      final result = await adapter.runCase(
        caseId: caseId,
        fixtureProfileId: profileId,
        body: (session) async {
          final builder = schemaCorpusCases[caseId]!('postgres');
          await session.executeSchema(builder);
        },
      );
      succeeded = result.status == MechanicalStatus.executedWithoutError;
      return result;
    } catch (e) {
      // applySchemaDdlProfile itself failing (a bug in this profile's own
      // prerequisite DDL, not the case under test) — report it the same
      // way as a case failure rather than letting it escape uncaught and
      // abort the whole loop.
      return MechanicalResult(
        MechanicalStatus.executionFailed,
        detail: 'fixture setup failed: $e',
        fixtureProfile: profileId,
      );
    } finally {
      // Keep the schema around (runSucceeded: false) whenever anything
      // above didn't cleanly succeed, mirroring tearDownRun's own
      // "keep failures reproducible" contract.
      await adapter.tearDownRun(runSucceeded: succeeded);
      await adapter.cleanUpNamedSchemas();
    }
  }

  test('every fixture-linked schema-DDL case executes without error', () async {
    final links = fixtureLinksByDialect['postgres']!;
    final schemaLinks = Map.fromEntries(
      links.entries.where((e) => e.key.startsWith('schema/')),
    );
    final failures = <String>[];

    for (final entry in schemaLinks.entries) {
      final result = await runSchemaCase(entry.key, entry.value);
      if (result.status != MechanicalStatus.executedWithoutError) {
        failures.add('${entry.key} (${entry.value}): ${result.detail}');
      }
    }

    expect(schemaLinks, isNotEmpty);
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test(
    'every unsupported-engine-allowlisted schema-DDL case still fails to '
    'execute (ratchet: a case that starts succeeding demands re-triage, '
    'not a silently-stale allowlist entry)',
    () async {
      final allowlist = unsupportedEngineAllowlist['postgres']!;
      final schemaAllowlist = Map.fromEntries(
        allowlist.entries.where((e) => e.key.startsWith('schema/')),
      );
      final unexpectedSuccesses = <String>[];

      for (final caseId in schemaAllowlist.keys) {
        final result = await runSchemaCase(caseId, 'schema_ddl_empty_v1');
        if (result.status == MechanicalStatus.executedWithoutError) {
          unexpectedSuccesses.add(caseId);
        }
      }

      expect(schemaAllowlist, isNotEmpty);
      expect(
        unexpectedSuccesses,
        isEmpty,
        reason:
            'Allowlisted schema-DDL case(s) now execute cleanly — re-triage '
            'and remove the allowlist entry: $unexpectedSuccesses',
      );
    },
  );
}
