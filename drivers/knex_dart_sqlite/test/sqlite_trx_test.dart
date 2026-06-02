/// Exhaustive transaction / error-path tests for KnexSQLite (in-memory, no Docker).
library;

import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';
import 'package:test/test.dart';

const _table = 'trx_test';

Future<KnexSQLite> _open() => KnexSQLite.connect(filename: ':memory:');

Never _throwFromHelper(Object e) => throw e;

void main() {
  group('KnexSQLite transaction exhaustive', () {
    late KnexSQLite db;

    setUp(() async {
      db = await _open();
      await db.executeSchema((s) {
        s.createTable(_table, (t) {
          t.integer('id').primary();
          t.string('name');
        });
      });
    });

    tearDown(() => db.close());

    // ── 1. Commit on success ──────────────────────────────────────────────────

    test('commit on success — row visible after trx', () async {
      await db.trx((tx) async {
        await tx.insert(tx(_table).insert({'id': 1, 'name': 'Alice'}));
      });

      final rows = await db.select(db(_table).select(['*']));
      expect(rows, hasLength(1));
      expect(rows.first['name'], 'Alice');
    });

    // ── 2. Rollback on callback error ─────────────────────────────────────────

    test('rollback on callback error — no rows committed', () async {
      await expectLater(
        db.trx((tx) async {
          await tx.insert(tx(_table).insert({'id': 2, 'name': 'Bob'}));
          throw Exception('deliberate failure');
        }),
        throwsA(isA<Exception>()),
      );

      final rows = await db.select(db(_table).select(['*']));
      expect(rows, isEmpty);
    });

    // ── 3. Original exception type preserved ─────────────────────────────────

    test('original exception type and message preserved', () async {
      final err = ArgumentError('bad argument');
      Object? caught;
      StackTrace? caughtTrace;
      try {
        await db.trx((_) async => _throwFromHelper(err));
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
      await db.trx((outer) async {
        await outer.insert(outer(_table).insert({'id': 10, 'name': 'Outer'}));

        await expectLater(
          outer.trx((inner) async {
            await inner.insert(inner(_table).insert({'id': 11, 'name': 'Inner'}));
            throw Exception('inner failure');
          }),
          throwsA(isA<Exception>()),
        );
      });

      final rows = await db.select(db(_table).select(['*']));
      expect(rows, hasLength(1));
      expect(rows.first['name'], 'Outer');
    });

    // ── 5. Nested trx — both commit ───────────────────────────────────────────

    test('nested trx: inner and outer both commit', () async {
      await db.trx((outer) async {
        await outer.insert(outer(_table).insert({'id': 20, 'name': 'Outer'}));
        await outer.trx((inner) async {
          await inner.insert(inner(_table).insert({'id': 21, 'name': 'Inner'}));
        });
      });

      final rows = await db.select(db(_table).select(['*']));
      expect(rows, hasLength(2));
    });

    // ── 6. Inner and outer both roll back ─────────────────────────────────────

    test('nested trx: inner and outer both roll back — nothing committed', () async {
      await expectLater(
        db.trx((outer) async {
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

      final rows = await db.select(db(_table).select(['*']));
      expect(rows, isEmpty);
    });

    // ── 7. Two separate in-memory instances are isolated ─────────────────────

    test('two in-memory instances do not share state', () async {
      final db2 = await _open();
      addTearDown(db2.close);
      await db2.executeSchema(
        (s) => s.createTable(_table, (t) {
          t.integer('id').primary();
          t.string('name');
        }),
      );

      await db.insert(db(_table).insert({'id': 1, 'name': 'DB1'}));
      final rows2 = await db2.select(db2(_table).select(['*']));
      expect(rows2, isEmpty);
    });

    // ── 8. Double close is safe ───────────────────────────────────────────────

    test('double close does not throw', () async {
      final db2 = await _open();
      await db2.close();
      await expectLater(db2.close(), completes);
    });

    // ── 9. Query after close throws StateError ────────────────────────────────

    test('query after close throws StateError', () async {
      final db2 = await _open();
      await db2.close();

      await expectLater(
        db2.rawSql('SELECT 1'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
