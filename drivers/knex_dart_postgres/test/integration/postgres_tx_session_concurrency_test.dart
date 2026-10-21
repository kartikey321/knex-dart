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
/// zone per top-level call, keyed by a fresh `Object()` unique to each
/// [PostgresClient] instance (not a shared static key — an earlier version
/// of this fix used one, which let one client's session leak to a second
/// client instance called from inside the first's transaction; see test 4).
/// A genuine nested call (made from within [action]'s own async call graph)
/// inherits that zone and correctly reuses the session — the reentrancy
/// guard still works. A concurrent, unrelated call runs in a sibling zone
/// that never sees it, so it correctly acquires its own connection and
/// opens its own independent transaction instead of colliding with
/// someone else's.
///
/// Zone values are retained by anything scheduled from within the zone, not
/// just by [action]'s own direct execution — so a detached
/// `Future`/`Timer`/stream listener that outlives [action] would otherwise
/// silently reuse a session whose connection may already be back in the
/// pool. [PostgresClient._txSession] guards against this with a completion
/// flag that turns late use into a clear `StateError` (see test 5).
///
/// These tests exist so a future refactor of `runInTransaction`'s session
/// storage cannot silently regress back to the old field-based behavior, or
/// reintroduce the shared-key/leaked-callback hazards above, without a test
/// failing.
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

        // B starts as its own top-level runInTransaction() call — a fresh
        // zone/session from the moment it's invoked, never A's — while A's
        // transaction happens to still be open. B's own action pauses
        // partway through, straddling the moment A's rollback completes.
        final futureB = db!.runInTransaction<String>(() async {
          await db!.rawSql(
            'INSERT INTO $_table (id, name) VALUES (101, \'B-row-1\')',
          );
          bReady.complete();
          await bProceed.future.timeout(_timeout);
          // B's session is still its own regardless of what happened to A
          // in the meantime — this must land in the same transaction as
          // B-row-1, not autocommit independently.
          await db!.rawSql(
            'INSERT INTO $_table (id, name) VALUES (102, \'B-row-2\')',
          );
          return 'B-done';
        });

        await bReady.future.timeout(_timeout);

        // Release A; its rollback completes before A's runInTransaction
        // future settles. This must have no effect on B's own session.
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

    // ── 4. Two DIFFERENT PostgresClient instances never share a session ──────
    //
    // Regression for a bug in an earlier version of this fix: the Zone key
    // that pins the session was `static`, so it was shared by every
    // PostgresClient instance in the isolate — meaning client B's queries,
    // if code reached into B from inside client A's runInTransaction
    // callback, would incorrectly execute on A's pinned session/connection
    // instead of acquiring B's own. The key is now a fresh Object() per
    // instance; this test proves a second client's runInTransaction() opens
    // its own independent transaction even when invoked from directly
    // inside the first client's still-open one.

    test(
      'a second PostgresClient instance, called from inside the first\'s '
      'runInTransaction(), does not see or share the first\'s session',
      () async {
        if (skipReason != null) return markTestSkipped(skipReason!);

        final dbB = await _tryConnect();
        if (dbB == null) {
          return markTestSkipped(
            'Could not open a second PostgreSQL connection at $_host:$_port',
          );
        }
        addTearDown(dbB.close);

        String? resultB;
        try {
          await db!.runInTransaction<void>(() async {
            await db!.rawSql(
              'INSERT INTO $_table (id, name) VALUES (100, \'A-row\')',
            );

            // Called from directly inside A's pinned zone. If the zone key
            // were shared across instances, dbB would incorrectly pick up
            // A's session here instead of acquiring its own connection.
            resultB = await dbB.runInTransaction<String>(() async {
              await dbB.rawSql(
                'INSERT INTO $_table (id, name) VALUES (101, \'B-row\')',
              );
              return 'B-committed';
            });

            throw Exception('A deliberately fails');
          });
        } catch (e) {
          expect(e, isA<Exception>());
        }

        expect(resultB, 'B-committed');

        // A's row is rolled back; B's independent transaction committed.
        final rows = await db!.select(selectAll());
        expect(rows, hasLength(1));
        expect(rows.single['id'], 101);
        expect(rows.single['name'], 'B-row');
      },
    );

    // ── 5. A leaked callback can't reuse a completed session ──────────────────
    //
    // Zone values are retained by anything scheduled from within the zone,
    // not just by `action`'s own direct execution — so a detached
    // Future/Timer/stream listener that `action` starts but doesn't await
    // still "sees" the pinned session even after runInTransaction() itself
    // has returned and the underlying connection may already be back in
    // the pool. `_PinnedSession.completed` (set in runInTransaction's
    // `finally`) turns that into a loud StateError instead of a silent,
    // potentially-corrupting reuse of a stale session.

    test(
      'a detached callback that outlives runInTransaction() throws instead '
      'of silently reusing the completed session',
      () async {
        if (skipReason != null) return markTestSkipped(skipReason!);

        final leakedAttempted = Completer<void>();
        final leakedResult = Completer<Object>();

        await db!.runInTransaction<void>(() async {
          // Deliberately NOT awaited — this is the leak under test. It
          // waits for the outer call to fully complete before firing.
          unawaited(
            Future(() async {
              await leakedAttempted.future;
              try {
                await db!.rawSql(
                  'INSERT INTO $_table (id, name) VALUES (999, \'leaked\')',
                );
                leakedResult.complete('no-error');
              } catch (e) {
                leakedResult.complete(e);
              }
            }),
          );
          await db!.rawSql(
            'INSERT INTO $_table (id, name) VALUES (100, \'A-row\')',
          );
        });

        // runInTransaction() has now returned — pinned.completed is true.
        leakedAttempted.complete();
        final result = await leakedResult.future.timeout(_timeout);

        expect(result, isA<StateError>());
        expect(
          (result as StateError).message,
          contains('already completed'),
        );

        // A's own transaction committed normally; the leaked callback never
        // got to insert its row.
        final rows = await db!.select(selectAll());
        expect(rows, hasLength(1));
        expect(rows.single['id'], 100);
      },
    );
  });
}
