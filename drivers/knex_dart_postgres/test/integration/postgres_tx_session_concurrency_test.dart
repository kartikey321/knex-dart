/// Regression tests for [PostgresClient.runInTransaction]'s concurrency
/// isolation.
///
/// `runInTransaction`'s pinned session used to live in a plain instance
/// field (`_txSession`). That field's reentrancy guard —
/// `if (_txSession != null) return action();` — could only ask "is a
/// session currently pinned", not "is this the SAME logical transaction
/// re-entering". Two genuinely concurrent `runInTransaction()` calls on the
/// same [PostgresClient] instance would both see the field non-null once
/// either was mid-flight, so the second caller's action silently ran on the
/// FIRST caller's session — with the second call still returning normally
/// (no exception) even though its write was then discarded by the first
/// caller's unrelated rollback. Worse: if the second caller's action
/// straddled the moment the field was cleared, its own writes could be torn
/// in half — part discarded by the first caller's rollback, part
/// autocommitted outside any transaction.
///
/// The fix (see [PostgresClient._txSessionZoneKey]) pins the session as a
/// [Zone] value instead of a plain field: `runInTransaction` forks a new
/// zone per top-level call. A genuine nested call (made from within
/// [action]'s own async call graph) inherits that zone and correctly reuses
/// the session — the reentrancy guard still works. A concurrent, unrelated
/// call runs in a sibling zone that never sees it, so it correctly acquires
/// its own connection and opens its own independent transaction instead of
/// colliding with someone else's.
///
/// These tests exist so a future refactor of `runInTransaction`'s session
/// storage cannot silently regress back to the old field-based behavior
/// without a test failing.
@Tags(['postgres'])
library;

import 'dart:async';

import 'package:universal_io/io.dart';
import 'package:knex_dart_postgres/knex_dart_postgres.dart';
import 'package:knex_dart/src/query/query_builder.dart';
import 'package:test/test.dart';

import '../mocks/mock_client.dart';

// ── Connection helpers ────────────────────────────────────────────────────────

String get _host => Platform.environment['PG_HOST'] ?? 'localhost';
int get _port => int.parse(Platform.environment['PG_PORT'] ?? '5432');
String get _database => Platform.environment['PG_DATABASE'] ?? 'knex_test';
String get _user => Platform.environment['PG_USER'] ?? 'knex';
String get _password => Platform.environment['PG_PASSWORD'] ?? 'knex';

const _table = 'tx_session_concurrency_test_postgres';
const _timeout = Duration(seconds: 10);

Future<PostgresClient?> _tryConnect() async {
  try {
    final client = await PostgresClient.connect(
      host: _host,
      port: _port,
      database: _database,
      username: _user,
      password: _password,
    );
    await client.rawSql('SELECT 1');
    return client;
  } catch (_) {
    return null;
  }
}

void main() {
  group('PostgresClient runInTransaction() concurrency isolation', () {
    PostgresClient? db;
    final mockClient = MockClient();
    String? skipReason;

    QueryBuilder selectAll() =>
        mockClient.queryBuilder().table(_table).select(['*']);

    setUpAll(() async {
      final candidate = await _tryConnect();
      if (candidate == null) {
        skipReason =
            'PostgreSQL not reachable at $_host:$_port — start via `docker compose up postgres -d`';
        return;
      }
      db = candidate;
      await db!.rawSql(
        'CREATE TABLE IF NOT EXISTS $_table (id INT PRIMARY KEY, name TEXT)',
      );
    });

    tearDownAll(() async {
      await db?.rawSql('DROP TABLE IF EXISTS $_table');
      await db?.close();
    });

    setUp(() async {
      if (db == null) return;
      await db!.rawSql('DELETE FROM $_table');
    });

    // ── 1. runInTransaction: concurrent calls get independent sessions ────────
    //
    // Deterministic (not racy): completers force B's call to start exactly
    // while A's session is still pinned, so this exercises the exact
    // interleaving that used to trigger the reentrancy-guard bug — no
    // timing luck required. Every cross-completer await is bounded with a
    // timeout, and A is always released even if B misbehaves, so a genuine
    // regression fails this test cleanly instead of hanging the suite.

    test(
      'two concurrent runInTransaction() calls get independent sessions — '
      'the second commits its own row even though the first rolls back',
      () async {
        if (skipReason != null) return markTestSkipped(skipReason!);

        final aReady = Completer<void>();
        final aProceed = Completer<void>();

        // Transaction A: inserts a row, signals it has pinned its session,
        // waits, then deliberately fails to force a rollback.
        final futureA = db!.runInTransaction<void>(() async {
          await db!.rawSql(
            'INSERT INTO $_table (id, name) VALUES (100, \'A-row\')',
          );
          aReady.complete();
          await aProceed.future.timeout(_timeout);
          throw Exception('A deliberately fails');
        });

        // Wait until A has pinned its session and inserted its row — the
        // window in which the old field-based guard used to misroute a
        // second call onto A's session.
        await aReady.future.timeout(_timeout);

        // Transaction B starts while A's session is still pinned. It must
        // get its own independent connection/transaction, not reuse A's.
        Object? bError;
        String? resultB;
        try {
          resultB = await db!
              .runInTransaction<String>(() async {
                await db!.rawSql(
                  'INSERT INTO $_table (id, name) VALUES (101, \'B-row\')',
                );
                return 'B-committed';
              })
              .timeout(_timeout);
        } catch (e) {
          bError = e;
        }

        // Always release A — whether B succeeded, threw, or timed out —
        // otherwise a genuine regression leaves A's transaction (and
        // pooled connection) open forever, hanging every test after this
        // one instead of failing cleanly.
        if (!aProceed.isCompleted) aProceed.complete();
        await expectLater(futureA, throwsA(isA<Exception>()));

        if (bError != null) {
          fail('B\'s runInTransaction() call did not complete promptly: $bError');
        }
        expect(resultB, 'B-committed');

        // A's row must be gone (rolled back); B's row must survive
        // (committed independently) — proving the two calls used separate
        // sessions instead of colliding.
        final rows = await db!.select(selectAll());
        expect(rows, hasLength(1));
        expect(rows.single['id'], 101);
        expect(rows.single['name'], 'B-row');
      },
    );

    // ── 2. trx(): concurrent calls also stay isolated ─────────────────────────
    //
    // Same completer-forced interleaving, through the closure-scoped trx()
    // API. Complements test 1: both of the driver's transaction APIs are
    // now safe for concurrent use on the same client instance.

    test(
      'two concurrent trx() calls remain isolated — one\'s rollback does '
      'not affect the other\'s committed row',
      () async {
        if (skipReason != null) return markTestSkipped(skipReason!);

        final aReady = Completer<void>();
        final aProceed = Completer<void>();

        final futureA = db!.trx<void>((tx) async {
          await tx.insert(tx(_table).insert({'id': 200, 'name': 'A-row'}));
          aReady.complete();
          await aProceed.future.timeout(_timeout);
          throw Exception('A deliberately fails');
        });

        await aReady.future.timeout(_timeout);

        Object? bError;
        String? resultB;
        try {
          resultB = await db!
              .trx<String>((tx) async {
                await tx.insert(tx(_table).insert({'id': 201, 'name': 'B-row'}));
                return 'B-committed';
              })
              .timeout(_timeout);
        } catch (e) {
          bError = e;
        }

        if (!aProceed.isCompleted) aProceed.complete();
        await expectLater(futureA, throwsA(isA<Exception>()));

        if (bError != null) {
          fail('B\'s trx() call did not complete promptly: $bError');
        }
        expect(resultB, 'B-committed');

        final rows = await db!.select(selectAll());
        expect(rows, hasLength(1));
        expect(rows.single['id'], 201);
        expect(rows.single['name'], 'B-row');
      },
    );

    // ── 3. runInTransaction: a concurrent caller's writes are never torn ──────
    //
    // The most dangerous shape of the old bug: B's action pauses partway
    // through, straddling the moment A's rollback used to clear the shared
    // `_txSession` field. With zone-scoped sessions, B's own zone (and
    // session) are untouched by A's completion — both of B's writes must
    // land in the SAME transaction and either both survive or both roll
    // back, never split.

    test(
      'runInTransaction(): a concurrent caller\'s writes are never torn '
      'across an unrelated caller\'s rollback, even when paused mid-action',
      () async {
        if (skipReason != null) return markTestSkipped(skipReason!);

        final aReady = Completer<void>();
        final aProceed = Completer<void>();
        final bReady = Completer<void>();
        final bProceed = Completer<void>();

        final futureA = db!.runInTransaction<void>(() async {
          await db!.rawSql(
            'INSERT INTO $_table (id, name) VALUES (100, \'A-row\')',
          );
          aReady.complete();
          await aProceed.future.timeout(_timeout);
          throw Exception('A deliberately fails');
        });

        await aReady.future.timeout(_timeout);

        // B starts while A's session is still pinned — but B's own action
        // pauses partway through, straddling the moment A's rollback
        // completes and A's zone/session go out of scope.
        final futureB = db!.runInTransaction<String>(() async {
          await db!.rawSql(
            'INSERT INTO $_table (id, name) VALUES (101, \'B-row-1\')',
          );
          bReady.complete();
          await bProceed.future.timeout(_timeout);
          // B's own zone/session are still in scope here regardless of
          // what happened to A in the meantime — this must land in the
          // same transaction as B-row-1, not autocommit independently.
          await db!.rawSql(
            'INSERT INTO $_table (id, name) VALUES (102, \'B-row-2\')',
          );
          return 'B-done';
        });

        await bReady.future.timeout(_timeout);

        // Release A. Its rollback completes and its zone/session go out of
        // scope before A's runInTransaction future settles.
        if (!aProceed.isCompleted) aProceed.complete();
        await expectLater(futureA, throwsA(isA<Exception>()));

        // Now release B to make its second write.
        Object? bError;
        String? resultB;
        try {
          if (!bProceed.isCompleted) bProceed.complete();
          resultB = await futureB.timeout(_timeout);
        } catch (e) {
          bError = e;
        }

        if (bError != null) {
          fail('B\'s runInTransaction() call did not complete promptly: $bError');
        }
        expect(resultB, 'B-done');

        // A-row is gone (rolled back). Both of B's writes survive together
        // — B's transaction was never torn by A's unrelated rollback.
        final rows = await db!.select(selectAll());
        expect(rows, hasLength(2));
        final ids = rows.map((r) => r['id']).toSet();
        expect(ids, {101, 102});
      },
    );
  });
}
