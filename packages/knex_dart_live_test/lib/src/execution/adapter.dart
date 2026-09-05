/// The contract a per-dialect live-execution adapter implements.
///
/// Framework code (the future runner, the report collector) depends only on
/// this interface — every dialect-specific detail (connection setup,
/// isolation mechanism, SQLSTATE-style error classification) lives entirely
/// in the adapter's own package (e.g. `drivers/knex_dart_postgres/test/
/// live_execution/`), never here. This package cannot depend on any driver
/// package without creating a real dependency cycle (drivers already
/// dev-depend on this package for the shared corpus), so adapters are
/// implemented downstream and simply satisfy this shape.
library;

import 'package:knex_dart/knex_dart.dart';

import 'report.dart';

/// One isolated case's execution handle, scoped by the adapter to whatever
/// guarantees isolation for that engine (a rollback-only transaction under
/// a private schema, a disposable file, etc).
///
/// [execute] and [executeSchema] must always run the real builder object
/// through the driver's real execution path — never compile it down to a
/// hand-authored SQL string first. A raw-SQL fallback would silently
/// bypass exactly the builder-vs-dispatch bugs this framework exists to
/// catch.
abstract class LiveCaseSession {
  /// Executes a query-corpus case's builder and returns its rows, if any.
  Future<List<Map<String, dynamic>>> execute(QueryBuilder query);

  /// Executes a schema-corpus case's compiled DDL statements in order.
  Future<void> executeSchema(SchemaBuilder schema);
}

/// A per-dialect live-execution adapter.
abstract class LiveDriverAdapter {
  String get dialect;

  /// Prepares whatever the whole run needs once — e.g. creating and
  /// seeding an ephemeral, isolated schema/database. Called once before
  /// any case runs.
  Future<void> setUpRun();

  /// Tears down run-level state. [runSucceeded] controls whether the
  /// isolated state is dropped (success) or kept for inspection (a run
  /// with any [MechanicalStatus.executionFailed] case is not "succeeded"
  /// — keep it so the failure is reproducible).
  Future<void> tearDownRun({required bool runSucceeded});

  /// Runs [body] for one case inside a freshly isolated [LiveCaseSession],
  /// applying [fixtureProfileId] first if non-null, and classifies the
  /// outcome. Returns null if [fixtureProfileId] is null — the caller
  /// (the runner) is expected to record [MechanicalStatus.deferredFixture]
  /// itself in that case rather than asking the adapter to run anything.
  Future<MechanicalResult> runCase({
    required String caseId,
    required String fixtureProfileId,
    required Future<void> Function(LiveCaseSession session) body,
  });
}
