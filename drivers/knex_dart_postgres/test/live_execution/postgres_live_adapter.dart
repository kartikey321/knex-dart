/// Postgres implementation of [LiveDriverAdapter]/[LiveCaseSession].
///
/// Isolation mode: ephemeral private schema (`live_pg_<runId>`), created and
/// seeded once per run. Each case runs inside its own rollback-only
/// transaction with `SET LOCAL search_path` pointed at that schema, so
/// concurrent/successive cases never see each other's mutations and nothing
/// this framework does ever touches the real integration-suite tables.
///
/// A case that reaches [runCase] has, by construction, already been linked
/// to a fixture profile by a human (via `fixtureLinksByDialect` — see
/// `knex_dart_live_test`). Any failure here is therefore always reported as
/// [MechanicalStatus.executionFailed] — this adapter never self-reports
/// [MechanicalStatus.deferredFixture] or [MechanicalStatus.unsupportedEngine]
/// for a live outcome. Those statuses are assigned only by a reviewer,
/// external to this class, based on the link table and the allowlist.
library;

import 'dart:math';

import 'package:knex_dart/knex_dart.dart';
import 'package:knex_dart_live_test/knex_dart_live_test.dart';
import 'package:knex_dart_postgres/knex_dart_postgres.dart';
import 'package:postgres/postgres.dart' show ServerException;

import 'postgres_fixture_profiles.dart';

/// Raw outcome of one case attempt, before any [MechanicalStatus]
/// collapsing — used by fixture-linking triage, which needs the actual
/// SQLSTATE to tell "no fixture provides this table/column yet"
/// (`42P01`/`42703`) apart from "knex-dart generated invalid SQL"
/// (`42601`) apart from every other failure. [runCase] does not use this
/// distinction for its own return value; only the triage tooling that
/// builds the fixture-link table reads [sqlstate] directly.
class PgCaseOutcome {
  final bool ok;
  final String? sqlstate;
  final String? message;

  const PgCaseOutcome.ok() : ok = true, sqlstate = null, message = null;
  const PgCaseOutcome.failed(this.sqlstate, this.message) : ok = false;
}

class _RollbackAfterCase implements Exception {
  const _RollbackAfterCase();
}

class PostgresLiveAdapter implements LiveDriverAdapter {
  final PostgresClient client;
  late final String schemaName;
  final _random = Random.secure();

  PostgresLiveAdapter(this.client);

  @override
  String get dialect => 'postgres';

  @override
  Future<void> setUpRun() async {
    await _sweepStaleSchemas();
    final suffix = _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    schemaName = 'live_pg_${DateTime.now().millisecondsSinceEpoch}_$suffix';
    await client.rawSql('CREATE SCHEMA "$schemaName"');
  }

  /// Applies one fixture profile's DDL then seed statements, in order,
  /// inside this run's private schema. Must be called (once per profile
  /// actually needed) before any case linked to that profile runs.
  Future<void> applyFixtureProfile(String profileId) async {
    final profile = postgresFixtureProfiles[profileId];
    if (profile == null) {
      throw ArgumentError('Unknown postgres fixture profile: $profileId');
    }
    await client.rawSql('SET search_path TO "$schemaName"');
    for (final stmt in profile.ddl) {
      await client.rawSql(stmt);
    }
    for (final stmt in profile.seed) {
      await client.rawSql(stmt);
    }
  }

  /// Drops schemas from prior runs older than [maxAge] (default 6 hours) so
  /// keep-on-failure runs don't accumulate forever. A run kept for
  /// inspection has that long to be looked at before the next run sweeps
  /// it; this is a best-effort safety net, not a guarantee.
  Future<void> _sweepStaleSchemas({Duration maxAge = const Duration(hours: 6)}) async {
    final rows = await client.rawSql(
      "select schema_name from information_schema.schemata "
      "where schema_name like 'live\\_pg\\_%' escape '\\'",
    );
    final cutoff = DateTime.now().subtract(maxAge).millisecondsSinceEpoch;
    for (final row in rows) {
      final name = row['schema_name'] as String;
      final parts = name.split('_');
      if (parts.length < 4) continue;
      final createdAtMs = int.tryParse(parts[2]);
      if (createdAtMs == null || createdAtMs >= cutoff) continue;
      await client.rawSql('DROP SCHEMA IF EXISTS "$name" CASCADE');
    }
  }

  @override
  Future<void> tearDownRun({required bool runSucceeded}) async {
    if (runSucceeded) {
      await client.rawSql('DROP SCHEMA IF EXISTS "$schemaName" CASCADE');
    }
  }

  @override
  Future<MechanicalResult> runCase({
    required String caseId,
    required String fixtureProfileId,
    required Future<void> Function(LiveCaseSession session) body,
  }) async {
    final outcome = await runCaseRaw(body: body);
    if (outcome.ok) {
      return MechanicalResult(
        MechanicalStatus.executedWithoutError,
        fixtureProfile: fixtureProfileId,
      );
    }
    return MechanicalResult(
      MechanicalStatus.executionFailed,
      detail: '${outcome.sqlstate}: ${outcome.message}',
      fixtureProfile: fixtureProfileId,
    );
  }

  /// Runs [body] in a rollback-only transaction scoped to this run's
  /// private schema and returns the raw outcome, SQLSTATE included. Used
  /// directly by fixture-linking triage tooling; [runCase] wraps this for
  /// the framework's own [MechanicalResult] contract.
  Future<PgCaseOutcome> runCaseRaw({
    required Future<void> Function(LiveCaseSession session) body,
  }) async {
    try {
      // The callback always throws (either the sentinel below, on success,
      // or a real error) — client.trx rethrows it, so this never returns
      // normally; the outcome is always decided in a catch clause below.
      await client.trx<void>((trx) async {
        await trx.rawSql('SET LOCAL search_path TO "$schemaName"');
        await body(_PostgresLiveCaseSession(trx));
        throw const _RollbackAfterCase();
      });
      throw StateError('unreachable: client.trx always rethrows');
    } on _RollbackAfterCase {
      return const PgCaseOutcome.ok();
    } on ServerException catch (e) {
      return PgCaseOutcome.failed(e.code, e.message);
    } catch (e) {
      return PgCaseOutcome.failed(null, e.toString());
    }
  }
}

class _PostgresLiveCaseSession implements LiveCaseSession {
  final PostgresTrxClient trx;

  _PostgresLiveCaseSession(this.trx);

  @override
  Future<List<Map<String, dynamic>>> execute(QueryBuilder query) =>
      trx.execute(query);

  @override
  Future<void> executeSchema(SchemaBuilder schema) async {
    for (final stmt in schema.toSQL()) {
      await trx.rawSql(
        stmt['sql'] as String,
        stmt['bindings'] as List<dynamic>?,
      );
    }
  }
}
