/// SQLite implementation of [LiveDriverAdapter]/[LiveCaseSession].
///
/// Isolation mode: SQLite has no concept of schemas/namespaces the way
/// Postgres does, so the simplest available isolation is used instead — a
/// disposable file database, created fresh in its own temp directory once
/// per run and seeded once. Each case still runs inside its own
/// rollback-only transaction (`SQLiteClient.trx`), so concurrent/successive
/// cases never see each other's mutations, mirroring the postgres adapter's
/// per-case isolation guarantee even though the run-level isolation
/// mechanism differs (a disposable file vs. an ephemeral shared-database
/// schema).
///
/// A case that reaches [runCase] has, by construction, already been linked
/// to a fixture profile by a human (via `fixtureLinksByDialect` — see
/// `knex_dart_live_test`). Any failure here is therefore always reported as
/// [MechanicalStatus.executionFailed] — this adapter never self-reports
/// [MechanicalStatus.deferredFixture] or [MechanicalStatus.unsupportedEngine]
/// for a live outcome. Those statuses are assigned only by a reviewer,
/// external to this class, based on the link table and the allowlist.
library;

import 'package:knex_dart/knex_dart.dart';
import 'package:knex_dart_live_test/knex_dart_live_test.dart';
import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;
import 'package:universal_io/io.dart';

import 'sqlite_fixture_profiles.dart';

/// Raw outcome of one case attempt, before any [MechanicalStatus]
/// collapsing — used by fixture-linking triage, which needs the actual
/// SQLite extended result code to tell "no fixture provides this
/// table/column yet" (`SQLITE_ERROR`, "no such table"/"no such column")
/// apart from other failure shapes. [runCase] does not use this
/// distinction for its own return value; only the triage tooling that
/// builds the fixture-link table reads [resultCode]/[message] directly.
class SqliteCaseOutcome {
  final bool ok;
  final int? resultCode;
  final String? message;

  const SqliteCaseOutcome.ok() : ok = true, resultCode = null, message = null;
  const SqliteCaseOutcome.failed(this.resultCode, this.message) : ok = false;
}

class _RollbackAfterCase implements Exception {
  const _RollbackAfterCase();
}

class SqliteLiveAdapter implements LiveDriverAdapter {
  late final SQLiteClient client;
  late final Directory _tempDir;
  late final String dbPath;

  @override
  String get dialect => 'sqlite';

  @override
  Future<void> setUpRun() async {
    _tempDir = await Directory.systemTemp.createTemp('knex_sqlite_live_');
    dbPath = '${_tempDir.path}/live.db';
    client = await SQLiteClient.connect(filename: dbPath);
  }

  /// Applies one fixture profile's DDL then seed statements, in order,
  /// against this run's disposable database file. Must be called (once per
  /// profile actually needed) before any case linked to that profile runs.
  Future<void> applyFixtureProfile(String profileId) async {
    final profile = sqliteFixtureProfiles[profileId];
    if (profile == null) {
      throw ArgumentError('Unknown sqlite fixture profile: $profileId');
    }
    for (final stmt in profile.ddl) {
      await client.rawQuery(stmt, const []);
    }
    for (final stmt in profile.seed) {
      await client.rawQuery(stmt, const []);
    }
  }

  @override
  Future<void> tearDownRun({required bool runSucceeded}) async {
    await client.close();
    if (runSucceeded) {
      if (await _tempDir.exists()) {
        await _tempDir.delete(recursive: true);
      }
    } else {
      // Keep the disposable database file for inspection — a run with any
      // executionFailed case is not "succeeded", so the failure stays
      // reproducible on disk rather than being silently deleted.
      // ignore: avoid_print
      print('SQLite live-execution run kept for inspection: $dbPath');
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
      detail: '${outcome.resultCode}: ${outcome.message}',
      fixtureProfile: fixtureProfileId,
    );
  }

  /// Runs [body] in a rollback-only transaction against this run's
  /// disposable database file and returns the raw outcome, SQLite's
  /// extended result code included. Used directly by fixture-linking
  /// triage tooling; [runCase] wraps this for the framework's own
  /// [MechanicalResult] contract.
  Future<SqliteCaseOutcome> runCaseRaw({
    required Future<void> Function(LiveCaseSession session) body,
  }) async {
    try {
      // The callback always throws (either the sentinel below, on success,
      // or a real error) — client.trx rethrows it, so this never returns
      // normally; the outcome is always decided in a catch clause below.
      await client.trx<void>((trx) async {
        await body(_SqliteLiveCaseSession(trx));
        throw const _RollbackAfterCase();
      });
      throw StateError('unreachable: client.trx always rethrows');
    } on _RollbackAfterCase {
      return const SqliteCaseOutcome.ok();
    } on SqliteException catch (e) {
      return SqliteCaseOutcome.failed(e.extendedResultCode, e.message);
    } catch (e) {
      return SqliteCaseOutcome.failed(null, e.toString());
    }
  }
}

class _SqliteLiveCaseSession implements LiveCaseSession {
  final SQLiteClient trx;

  _SqliteLiveCaseSession(this.trx);

  @override
  Future<List<Map<String, dynamic>>> execute(QueryBuilder query) =>
      trx.execute(query);

  @override
  Future<void> executeSchema(SchemaBuilder schema) async {
    for (final stmt in schema.toSQL()) {
      await trx.rawQuery(
        stmt['sql'] as String,
        (stmt['bindings'] as List<dynamic>?) ?? const [],
      );
    }
  }
}
