/// Exhaustive transaction / error-path tests for KnexTurso.
@Tags(['turso'])
library;

import 'package:universal_io/io.dart';
import 'package:knex_dart_turso/knex_dart_turso.dart';
import 'package:test/test.dart';

// ── Connection helpers ────────────────────────────────────────────────────────

String get _url => Platform.environment['TURSO_URL'] ?? 'http://127.0.0.1:18080';
String? get _token => Platform.environment['TURSO_AUTH_TOKEN'];

const _table = 'trx_test_turso';

Future<KnexTurso?> _tryOpen() async {
  try {
    final db = KnexTurso(url: _url, authToken: _token ?? '');
    await db.rawSql('SELECT 1');
    return db;
  } catch (_) {
    return null;
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

Never _throwFromHelper(Object e) => throw e;

void main() {
  group('KnexTurso transaction exhaustive', () {
    KnexTurso? db;
    String? skipReason;

    setUpAll(() async {
      final candidate = await _tryOpen();
      if (candidate == null) {
        skipReason =
            'sqld not reachable at $_url — start via `docker compose up sqld -d`';
        return;
      }
      db = candidate;
      await db!.executeSchema((s) {
        s.dropTableIfExists(_table);
        s.createTable(_table, (t) {
          t.integer('id').primary();
          t.string('name');
        });
      });
    });

    tearDownAll(() async {
      await db?.executeSchema((s) => s.dropTableIfExists(_table));
      db?.close();
    });

    setUp(() async {
      if (db == null) return;
      await db!.rawSql('DELETE FROM $_table');
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

    // ── 4. Nested trx — inner savepoint rolls back, outer commits ─────────────

    test('nested trx: inner savepoint rolls back, outer commits', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.trx((outer) async {
        await outer.insert(outer(_table).insert({'id': 10, 'name': 'Outer'}));

        await expectLater(
          outer.trx((inner) async {
            await inner.insert(inner(_table).insert({'id': 11, 'name': 'Inner'}));
            throw Exception('inner failure');
          }),
          throwsA(isA<Exception>()),
        );
      });

      final rows = await db!.select(db!(_table).select(['*']));
      expect(rows, hasLength(1));
      expect(rows.first['name'], 'Outer');
    });

    // ── 5. Nested trx — both commit ───────────────────────────────────────────

    test('nested trx: inner and outer both commit', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.trx((outer) async {
        await outer.insert(outer(_table).insert({'id': 20, 'name': 'Outer'}));
        await outer.trx((inner) async {
          await inner.insert(inner(_table).insert({'id': 21, 'name': 'Inner'}));
        });
      });

      final rows = await db!.select(db!(_table).select(['*']));
      expect(rows, hasLength(2));
    });

    // ── 6. Inner and outer both roll back ─────────────────────────────────────

    test('nested trx: inner and outer both roll back — nothing committed', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await expectLater(
        db!.trx((outer) async {
          await outer.insert(outer(_table).insert({'id': 30, 'name': 'Outer'}));
          try {
            await outer.trx((inner) async {
              await inner.insert(inner(_table).insert({'id': 31, 'name': 'Inner'}));
              throw Exception('inner');
            });
          } catch (_) {}
          throw Exception('outer');
        }),
        throwsA(isA<Exception>()),
      );

      final rows = await db!.select(db!(_table).select(['*']));
      expect(rows, isEmpty);
    });

    // ── 7. Double close is safe ───────────────────────────────────────────────

    test('double close does not throw', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      final c = await _tryOpen();
      expect(c, isNotNull);
      c!.close();
      expect(() => c.close(), returnsNormally);
    });

    // ── 8. Query after close throws StateError ────────────────────────────────

    test('query after close throws StateError', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      final c = await _tryOpen();
      expect(c, isNotNull);
      c!.close();

      await expectLater(
        c.rawSql('SELECT 1'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
