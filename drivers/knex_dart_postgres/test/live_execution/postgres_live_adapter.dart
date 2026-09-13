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
import 'postgres_schema_ddl_profiles.dart';

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

  /// Extra schemas appended to `search_path` after [schemaName], for the
  /// rare schema-DDL profile whose case needs to resolve something (e.g.
  /// an extension-provided type like `citext`) that isn't — and can't be
  /// made to be — visible from an isolated ephemeral schema alone. Empty
  /// by default: every other case deliberately sees *only* [schemaName],
  /// so a leftover table from an unrelated integration-test suite can
  /// never silently satisfy a case's prerequisite. Applies to both
  /// [applySchemaDdlProfile] and [runCaseRaw]/[runCase] — the case's own
  /// compiled DDL runs under the same search_path setup did.
  List<String> extraSearchPathSchemas = const [];

  String get _searchPath =>
      ['"$schemaName"', ...extraSearchPathSchemas].join(', ');

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

  /// Records, at [recordPreexistingNamedSchemas] time (before this run does
  /// anything), which of [postgresSchemaDdlNamedSchemasToClean] already
  /// existed — anything already there belongs to something *this run did
  /// not create*, database-level and outside our own ephemeral [schemaName],
  /// and must never be touched by [cleanUpNamedSchemas]. A boolean
  /// "did our own CREATE SCHEMA statement succeed" flag is NOT sufficient
  /// here: several schema-DDL cases (e.g. schema/create-schema itself
  /// creates 'billing') mutate a named schema as their OWN compiled action,
  /// not via the prerequisite profile, so cleanup must react to what
  /// actually exists before/after, not to which specific statement ran.
  Set<String> _preexistingNamedSchemas = const {};

  Future<void> recordPreexistingNamedSchemas() async {
    final rows = await client.rawSql(
      'select schema_name from information_schema.schemata '
      'where schema_name = any(\$1)',
      [postgresSchemaDdlNamedSchemasToClean],
    );
    _preexistingNamedSchemas = rows
        .map((r) => r['schema_name'] as String)
        .toSet();
  }

  /// Applies one schema-DDL-corpus fixture profile's prerequisite DDL
  /// (`postgres_schema_ddl_profiles.dart`) inside this run's private
  /// schema. Distinct from [applyFixtureProfile] (the query corpus's
  /// profiles, which also carry seed rows) — schema-DDL profiles are
  /// DDL-only and, unlike the query corpus's profiles, are each meant to
  /// be applied into a fresh, single-case-only schema (see
  /// `postgres_schema_ddl_profiles.dart`'s docstring for why).
  ///
  /// Runs `SET LOCAL search_path` and every DDL statement inside one
  /// [PostgresClient.trx] call (committed on success) rather than as
  /// separate [PostgresClient.rawSql] calls — each `rawSql` independently
  /// leases a connection from the pool, so nothing would otherwise
  /// guarantee `SET search_path` and the DDL that follows land on the
  /// *same* physical session.
  Future<void> applySchemaDdlProfile(String profileId) async {
    final ddl = postgresSchemaDdlProfiles[profileId];
    if (ddl == null) {
      throw ArgumentError(
        'Unknown postgres schema-DDL fixture profile: $profileId',
      );
    }
    await client.trx<void>((trx) async {
      await trx.rawSql('SET LOCAL search_path TO $_searchPath');
      for (final stmt in ddl) {
        await trx.rawSql(stmt);
      }
    });
  }

  /// Drops whichever of [postgresSchemaDdlNamedSchemasToClean] now exist
  /// but did NOT exist when [recordPreexistingNamedSchemas] was called (at
  /// the start of this run) — i.e. only what this run itself created,
  /// whether via [applySchemaDdlProfile]'s own prerequisite DDL or via the
  /// case's own compiled action (some cases, e.g. schema/create-schema,
  /// create/drop a named schema as their own test subject, not via a
  /// prerequisite). Anything that already existed before this run started
  /// is left completely alone, unconditionally — confirmed by reproducing
  /// exactly the failure mode this guards against: a foreign
  /// pre-existing "billing" schema (with real data in it) survived a case
  /// whose own CREATE SCHEMA billing failed with 42P06 "already exists"
  /// only after this fix; the naive "did setup succeed" flag it replaced
  /// did not distinguish that case's cleanup from any other's and
  /// destroyed the foreign schema anyway.
  Future<void> cleanUpNamedSchemas() async {
    for (final name in postgresSchemaDdlNamedSchemasToClean) {
      if (_preexistingNamedSchemas.contains(name)) continue;
      await client.rawSql('DROP SCHEMA IF EXISTS "$name" CASCADE');
    }
  }

  /// Drops schemas from prior runs older than [maxAge] (default 6 hours) so
  /// keep-on-failure runs don't accumulate forever. A run kept for
  /// inspection has that long to be looked at before the next run sweeps
  /// it; this is a best-effort safety net, not a guarantee.
  Future<void> _sweepStaleSchemas({
    Duration maxAge = const Duration(hours: 6),
  }) async {
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
        await trx.rawSql('SET LOCAL search_path TO $_searchPath');
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
