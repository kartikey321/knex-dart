import 'dart:async';

import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';
import 'package:test/test.dart';

/// Regression tests for the findings of an adversarial review of this driver.
///
/// Each group names the behavior that used to be wrong, because every one of
/// these failed *silently* — wrong results or a hung stream, never an error —
/// so a plain "it works" assertion would not have caught any of them.
void main() {
  group('statement kind is decided by sqlite, not by the SQL text', () {
    late KnexSQLite db;

    setUp(() async {
      db = await KnexSQLite.connect(filename: ':memory:');
      await db.rawSql('CREATE TABLE t (v INTEGER)');
      await db.rawSql('INSERT INTO t VALUES (7)');
    });

    tearDown(() => db.close());

    test('a CTE select returns its rows', () async {
      // `with ... select` begins with neither SELECT nor PRAGMA and contains no
      // RETURNING, so the old text heuristic routed it to the no-rows branch
      // and returned [] for a query that had a row.
      expect(
        await db.rawSql('WITH c AS (SELECT v FROM t) SELECT * FROM c'),
        [
          {'v': 7},
        ],
      );
    });

    test('a CTE select through the typed builder returns its rows', () async {
      // The same defect was reachable from the public typed API, not just raw
      // SQL — this is the shape a caller is most likely to hit.
      final query = db
          .queryBuilder()
          .withQuery('c', db.raw('select v from t'))
          .from('c')
          .select(['v']);

      expect(query.toSQL().sql, 'with "c" as (select v from t) select "v" from "c"');
      expect(await db.select(query), [
        {'v': 7},
      ]);
    });

    test('a comment before SELECT does not hide the rows', () async {
      expect(await db.rawSql('/* lead */ SELECT v FROM t'), [
        {'v': 7},
      ]);
    });

    test('a PRAGMA read returns its row', () async {
      expect(await db.rawSql('PRAGMA user_version'), [
        {'user_version': 0},
      ]);
    });

    test('statements with no result columns still return an empty list', () {
      // The contract callers already rely on: DML reports no rows rather than
      // throwing now that everything goes through select().
      expect(db.rawSql('UPDATE t SET v = 7'), completion(isEmpty));
    });

    test('a PRAGMA assignment applies and returns no rows', () async {
      expect(await db.rawSql('PRAGMA user_version = 3'), isEmpty);
      expect(await db.rawSql('PRAGMA user_version'), [
        {'user_version': 3},
      ]);
    });

    test('RETURNING still yields its rows', () async {
      expect(await db.rawSql('INSERT INTO t VALUES (8) RETURNING v'), [
        {'v': 8},
      ]);
    });

    test('a value containing the word returning is not misread', () async {
      await db.rawSql('CREATE TABLE notes (s TEXT)');
      expect(
        await db.rawSql("INSERT INTO notes VALUES ('returning soon')"),
        isEmpty,
      );
      expect(await db.rawSql('SELECT s FROM notes'), [
        {'s': 'returning soon'},
      ]);
    });
  });

  group('a second statement is an error, not a silent drop', () {
    late KnexSQLite db;

    setUp(() async => db = await KnexSQLite.connect(filename: ':memory:'));
    tearDown(() => db.close());

    test('two statements in one call are rejected', () async {
      // `prepare` compiles only the first statement, so this used to create
      // m1, ignore m2 and report success.
      await expectLater(
        db.rawSql('CREATE TABLE m1 (x INTEGER); CREATE TABLE m2 (y INTEGER);'),
        throwsA(isA<ArgumentError>()),
      );

      final tables = await db.rawSql(
        "SELECT name FROM sqlite_master WHERE name IN ('m1','m2')",
      );
      expect(
        tables,
        isEmpty,
        reason: 'the rejected call must not have applied half of itself',
      );
    });

    test('an ordinary trailing semicolon is still accepted', () async {
      await db.rawSql('CREATE TABLE ok (x INTEGER);');
      expect(await db.rawSql('SELECT x FROM ok;   '), isEmpty);
    });
  });

  group('transaction state is per client, not global', () {
    test('one client\'s transaction does not make another think it is nested',
        () async {
      // The marker lived in a `static` field, so every client shared it:
      // client B's top-level trx inside client A's transaction saw A's marker,
      // skipped B's own serialization queue, and emitted SAVEPOINT/RELEASE
      // without B ever having run BEGIN — failing with "no such savepoint".
      final a = await KnexSQLite.connect(filename: ':memory:');
      final b = await KnexSQLite.connect(filename: ':memory:');
      addTearDown(() async {
        await a.close();
        await b.close();
      });
      await b.rawSql('CREATE TABLE z (v INTEGER)');

      await a.trx((_) async {
        await Future.wait([
          b.trx((t) async => t.rawSql('INSERT INTO z VALUES (1)')),
          b.trx((t) async => t.rawSql('INSERT INTO z VALUES (2)')),
        ]);
      });

      expect(await b.rawSql('SELECT v FROM z ORDER BY v'), [
        {'v': 1},
        {'v': 2},
      ]);
    });
  });

  group('streamQuery releases its statement when cancelled early', () {
    test('a later DROP TABLE is not blocked by a leaked cursor', () async {
      // The stream was `Stream.fromIterable` over a `sync*` generator.
      // Cancelling abandons that iterator without running its `finally`, so
      // the statement stayed open and its cursor held a read lock: the DROP
      // below failed with "database table is locked" (SqliteException 6).
      final db = await KnexSQLite.connect(filename: ':memory:');
      addTearDown(db.close);
      await db.rawSql('CREATE TABLE t (v INTEGER)');
      for (var i = 0; i < 50; i++) {
        await db.rawSql('INSERT INTO t VALUES (?)', [i]);
      }

      final sub = db
          .streamQuery(db.queryBuilder().from('t').select(['v']))
          .listen(null);
      // Take one row, then abandon the stream.
      final first = Completer<void>();
      sub.onData((_) {
        if (!first.isCompleted) first.complete();
      });
      await first.future.timeout(const Duration(seconds: 2));
      await sub.cancel();

      await expectLater(db.rawSql('DROP TABLE t'), completes);
    });

    test('a fully drained stream still returns every row', () async {
      final db = await KnexSQLite.connect(filename: ':memory:');
      addTearDown(db.close);
      await db.rawSql('CREATE TABLE t (v INTEGER)');
      await db.rawSql('INSERT INTO t VALUES (1)');
      await db.rawSql('INSERT INTO t VALUES (2)');

      final rows = await db
          .streamQuery(db.queryBuilder().from('t').select(['v']).orderBy('v'))
          .toList();
      expect(rows.map((r) => r['v']), [1, 2]);
    });
  });

  group('the prepared-statement cache is bounded', () {
    test('results stay correct once eviction starts', () async {
      // The cache is capped at 128 entries and evicts least-recently-used.
      // Distinct SQL beyond the cap must evict and re-prepare transparently —
      // this fails loudly if an evicted statement is reused after close().
      final db = await KnexSQLite.connect(filename: ':memory:');
      addTearDown(db.close);
      await db.rawSql('CREATE TABLE t (v INTEGER)');
      await db.rawSql('INSERT INTO t VALUES (1)');

      // 200 distinct statements, comfortably past the 128 cap.
      for (var i = 0; i < 200; i++) {
        final rows = await db.rawSql('SELECT v + $i AS shifted FROM t');
        expect(rows, [
          {'shifted': 1 + i},
        ]);
      }

      // Re-run the very first one, long since evicted: it must be re-prepared
      // and still correct rather than reusing a closed statement.
      expect(await db.rawSql('SELECT v + 0 AS shifted FROM t'), [
        {'shifted': 1},
      ]);
    });
  });

  group('watch() ends when the database closes', () {
    test('the stream completes instead of hanging', () async {
      // listen() had no onDone, so the controller stayed open after the
      // client closed: `await for` over watch() never returned.
      final db = await KnexSQLite.connect(filename: ':memory:');
      await db.rawSql('CREATE TABLE t (v INTEGER)');

      final done = Completer<void>();
      final sub = db
          .watch(db.queryBuilder().from('t').select(['v']))
          .listen((_) {}, onDone: done.complete);
      addTearDown(sub.cancel);

      // Let the initial emission settle so the subscription is live.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await db.close();

      await expectLater(
        done.future.timeout(const Duration(seconds: 2)),
        completes,
      );
    });
  });
}
