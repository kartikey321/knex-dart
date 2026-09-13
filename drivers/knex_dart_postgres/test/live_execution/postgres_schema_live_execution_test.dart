/// End-to-end proof that the live-execution mechanism works for postgres's
/// schema-DDL corpus: every case linked in
/// `fixtureLinksByDialect['postgres']` under a `schema/*` id executes
/// without error, and every case listed in
/// `unsupportedEngineAllowlist['postgres']` under a `schema/*` id still
/// reproduces its documented failure — with the SAME SQLSTATE the
/// allowlist reason cites, not just "some failure occurred" (a regression
/// to a *different* failure shape would otherwise slip through unnoticed).
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
import 'postgres_schema_ddl_profiles.dart';

/// The SQLSTATE (or, for the one non-ServerException case, a distinctive
/// substring of the client-side error) each allowlisted schema-DDL case's
/// `unsupported_engine_allowlist.dart` reason cites as ITS failure, not
/// just "any" failure.
const Map<String, String> _expectedAllowlistFailureMarkers = {
  'schema/create-extension': '0A000',
  'schema/create-extension-if-not-exists': '0A000',
  'schema/drop-extension': '42704',
  'schema/create-table-primary-composite-with-increments': '42P16',
  'schema/raw-with-binding': '42601',
};

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
  ///
  /// [expectFailure]: for the allowlist-ratchet test, where the case is
  /// SUPPOSED to fail — once that expected failure has been observed and
  /// verified, the ephemeral schema has already served its purpose and
  /// keeping it around (this adapter's normal "keep on failure, for
  /// inspection" behavior) would just leak it for up to 6 hours on every
  /// green run for no benefit.
  Future<MechanicalResult> runSchemaCase(
    String caseId,
    String profileId, {
    bool expectFailure = false,
  }) async {
    final adapter = PostgresLiveAdapter(client);
    if (postgresSchemaDdlProfilesNeedingPublicFallback.contains(profileId)) {
      adapter.extraSearchPathSchemas = const ['public'];
    }
    await adapter.setUpRun();
    // Must happen before anything below has a chance to create/mutate a
    // named schema (myschema/mySchema/billing) — see
    // recordPreexistingNamedSchemas's doc comment.
    await adapter.recordPreexistingNamedSchemas();
    var cleanupSucceeded = false;
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
      final executedCleanly =
          result.status == MechanicalStatus.executedWithoutError;
      cleanupSucceeded = expectFailure ? !executedCleanly : executedCleanly;
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
      // Keep the schema around (runSucceeded: false) only when something
      // genuinely unexpected happened, mirroring tearDownRun's own "keep
      // failures reproducible" contract — an *expected* failure that was
      // just verified needs no further inspection.
      //
      // Cleanup itself failing (e.g. connection contention when many test
      // files run concurrently against the same Postgres container, as
      // `dart test --tags=postgres` does by default) must never propagate
      // out of a `finally` and abort the whole case loop mid-run, silently
      // skipping every case still queued behind it — best-effort only.
      try {
        await adapter.tearDownRun(runSucceeded: cleanupSucceeded);
        await adapter.cleanUpNamedSchemas();
      } catch (_) {}
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

  test('every unsupported-engine-allowlisted schema-DDL case still fails with '
      'the exact SQLSTATE its allowlist reason cites (ratchet: a case that '
      'starts succeeding — or starts failing for a DIFFERENT reason — '
      'demands re-triage, not a silently-stale or silently-wrong allowlist '
      'entry)', () async {
    final allowlist = unsupportedEngineAllowlist['postgres']!;
    final schemaAllowlist = Map.fromEntries(
      allowlist.entries.where((e) => e.key.startsWith('schema/')),
    );
    final problems = <String>[];

    for (final caseId in schemaAllowlist.keys) {
      final result = await runSchemaCase(
        caseId,
        'schema_ddl_empty_v1',
        expectFailure: true,
      );
      if (result.status == MechanicalStatus.executedWithoutError) {
        problems.add('$caseId: now executes cleanly, expected a failure');
        continue;
      }
      final expectedMarker = _expectedAllowlistFailureMarkers[caseId];
      if (expectedMarker == null) {
        problems.add(
          '$caseId: missing an entry in _expectedAllowlistFailureMarkers '
          '— add one so this ratchet actually checks something',
        );
      } else if (!(result.detail ?? '').contains(expectedMarker)) {
        problems.add(
          '$caseId: expected failure to mention "$expectedMarker" '
          '(per its allowlist reason) but got: ${result.detail}',
        );
      }
    }

    expect(schemaAllowlist, isNotEmpty);
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
