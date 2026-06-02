/// Exhaustive transaction / error-path tests for KnexDuckDB (in-memory, no Docker).
library;

import 'package:knex_dart_duckdb/knex_dart_duckdb.dart';
import 'package:test/test.dart';

const _table = 'trx_test';

Never _throwFromHelper(Object e) => throw e;

Future<KnexDuckDB?> _tryOpen() async {
  try {
    return await KnexDuckDB.memory().timeout(const Duration(minutes: 2));
  } catch (_) {
    return null;
  }
}

void main() {
  group('KnexDuckDB transaction exhaustive', () {
    KnexDuckDB? db;
    String? skipReason;

    setUpAll(() async {
      final candidate = await _tryOpen();
      if (candidate == null) {
        skipReason =
            'DuckDB native library not found — install via `brew install duckdb`';
      }
      await candidate?.close();
    });

    setUp(() async {
      if (skipReason != null) return;
      db = await _tryOpen();
      await db!.executeSchema((s) {
        s.createTable(_table, (t) {
          t.integer('id').primary();
          t.string('name');
        });
      });
    });

    tearDown(() async {
      await db?.close();
      db = null;
    });

    // ── 1. Commit on success ──────────────────────────────────────────────────

    test('commit on success — row visible after trx', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.trx((tx) async {
        await tx.insert(tx(_table).insert({'id': 1, 'name': 'Alice'}));
      });

      final rows = await db!.select(db!(_table).select(['*']));
      expect(rows, hasLength(1));
      expect(rows.first['name'], 'Alice');
    });

    // ── 2. Rollback on callback error ─────────────────────────────────────────

    test('rollback on callback error — no rows committed', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await expectLater(
        db!.trx((tx) async {
          await tx.insert(tx(_table).insert({'id': 2, 'name': 'Bob'}));
          throw Exception('deliberate failure');
        }),
        throwsA(isA<Exception>()),
      );

      final rows = await db!.select(db!(_table).select(['*']));
      expect(rows, isEmpty);
    });

    // ── 3. Original exception type preserved ─────────────────────────────────

    test('original exception type and message preserved', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      final err = ArgumentError('bad argument');
      Object? caught;
      StackTrace? caughtTrace;
      try {
        await db!.trx((_) async => _throwFromHelper(err));
      } catch (e, st) {
        caught = e;
        caughtTrace = st;
      }
      expect(caught, isA<ArgumentError>());
      expect((caught as ArgumentError).message, 'bad argument');
      // Verify original stack preserved — must reference _throwFromHelper, not the rollback path.
      expect(caughtTrace.toString(), contains('_throwFromHelper'));
    });

    // ── 4. raw() alias works inside trx callback ─────────────────────────────

    test('raw() alias usable inside trx callback', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      late List<Map<String, dynamic>> result;
      await db!.trx((tx) async {
        // raw() must be callable on the transaction object — was missing before.
        result = await (tx as dynamic).raw('SELECT 1 AS n');
      });
      expect(result.first['n'], isNotNull);
    });

    // ── 5. Two separate in-memory instances are isolated ─────────────────────
    // NOTE: DuckDB does not support SQL-level SAVEPOINT, so nested trx tests
    // are omitted. Only top-level BEGIN/COMMIT/ROLLBACK is supported.

    test('two in-memory instances do not share state', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      final db2 = await _tryOpen();
      expect(db2, isNotNull);
      addTearDown(db2!.close);

      await db2.executeSchema(
        (s) => s.createTable(_table, (t) {
          t.integer('id').primary();
          t.string('name');
        }),
      );

      await db!.insert(db!(_table).insert({'id': 1, 'name': 'DB1'}));
      final rows2 = await db2.select(db2(_table).select(['*']));
      expect(rows2, isEmpty);
    });

    // ── 8. Double close is safe ───────────────────────────────────────────────

    test('double close does not throw', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      final db2 = await _tryOpen();
      expect(db2, isNotNull);
      await db2!.close();
      await expectLater(db2.close(), completes);
    });

    // ── 9. Query after close throws StateError ────────────────────────────────

    test('query after close throws StateError', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      final db2 = await _tryOpen();
      expect(db2, isNotNull);
      await db2!.close();

      await expectLater(
        db2.rawSql('SELECT 1'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
