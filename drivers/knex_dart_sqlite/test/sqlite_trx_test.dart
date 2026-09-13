/// Exhaustive transaction / error-path tests for KnexSQLite (in-memory, no Docker).
library;

import 'package:knex_dart/knex_dart.dart';
import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';
import 'package:test/test.dart';

const _table = 'trx_test';
const _isWeb = bool.fromEnvironment('dart.library.js_interop');

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
            await inner.insert(
              inner(_table).insert({'id': 11, 'name': 'Inner'}),
            );
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

    test(
      'nested trx: inner and outer both roll back — nothing committed',
      () async {
        await expectLater(
          db.trx((outer) async {
            await outer.insert(
              outer(_table).insert({'id': 30, 'name': 'Outer'}),
            );
            try {
              await outer.trx((inner) async {
                await inner.insert(
                  inner(_table).insert({'id': 31, 'name': 'Inner'}),
                );
                throw Exception('inner');
              });
            } catch (_) {}
            throw Exception('outer');
          }),
          throwsA(isA<Exception>()),
        );

        final rows = await db.select(db(_table).select(['*']));
        expect(rows, isEmpty);
      },
    );

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

      await expectLater(db2.rawSql('SELECT 1'), throwsA(isA<StateError>()));
    });

    // ── 10. Concurrent top-level transactions are serialized ──────────────────

    test(
      'concurrent top-level trx calls are serialized — no interleaving',
      () async {
        // Fire two trx() calls without awaiting the first.
        // If serialization is broken, the second BEGIN would race with the first,
        // producing a "cannot start a transaction within a transaction" error.
        final f1 = db.trx((tx) async {
          await tx.insert(tx(_table).insert({'id': 40, 'name': 'Concurrent1'}));
        });
        final f2 = db.trx((tx) async {
          await tx.insert(tx(_table).insert({'id': 41, 'name': 'Concurrent2'}));
        });

        await Future.wait([f1, f2]);

        final rows = await db.select(db(_table).select(['*']));
        expect(rows, hasLength(2));
        final names = rows.map((r) => r['name']).toSet();
        expect(names, containsAll(['Concurrent1', 'Concurrent2']));
      },
    );

    // ── 11. Failed trx does not block the queue ───────────────────────────────

    test('failed trx does not block subsequent transactions', () async {
      // First trx rolls back.
      await expectLater(
        db.trx((_) async => throw Exception('fail')),
        throwsA(isA<Exception>()),
      );

      // Second trx should still work.
      await db.trx((tx) async {
        await tx.insert(tx(_table).insert({'id': 50, 'name': 'AfterFail'}));
      });

      final rows = await db.select(db(_table).select(['*']));
      expect(rows, hasLength(1));
      expect(rows.first['name'], 'AfterFail');
    });

    // ── 11b. A failing ROLLBACK must not mask the original error or corrupt
    //         the update-hook stack ─────────────────────────────────────────
    //
    // If the callback already ended the transaction via raw SQL (or the
    // connection is torn down concurrently), sqlite3.execute('ROLLBACK')
    // itself throws ("cannot rollback - no transaction is active"). Before
    // this was guarded (mirroring the SAVEPOINT branch's existing
    // try/catch), that secondary failure propagated *instead of* the
    // original callback error, and skipped _txUpdateStack.removeLast() —
    // leaving a permanent stale entry that made watch() silently stop seeing
    // non-transactional writes for the rest of the client's lifetime (the
    // update hook buffers into _txUpdateStack.last instead of forwarding to
    // _updateController whenever the stack is non-empty).

    test(
      'rollback failure inside a failed trx preserves the original error',
      () async {
        Object? caught;
        try {
          await db.trx((tx) async {
            await tx.rawSql('COMMIT'); // ends the transaction early
            throw Exception('boom');
          });
        } catch (e) {
          caught = e;
        }
        expect(caught, isA<Exception>());
        expect(caught.toString(), contains('boom'));
      },
    );

    test(
      'watch() still emits for non-transactional writes after a rollback '
      'failure',
      () async {
        try {
          await db.trx((tx) async {
            await tx.rawSql('COMMIT');
            throw Exception('boom');
          });
        } catch (_) {
          // Expected — asserted by the previous test; ignored here.
        }

        final emissions = <int>[];
        final sub = db
            .watch(db(_table).select(['*']))
            .listen((rows) => emissions.add(rows.length));
        await Future<void>.delayed(Duration.zero);

        await db.insert(db(_table).insert({'id': 60, 'name': 'AfterBadRollback'}));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await sub.cancel();

        // Before the fix: only the initial (empty) emission ever arrived —
        // the insert's update-hook event was buffered into a stale
        // _txUpdateStack entry that no top-level commit will ever flush.
        expect(emissions, hasLength(2));
        expect(emissions.last, 1);
      },
    );

    // ── 12. webStorageMode must fail fast on native ───────────────────────────

    test(
      'connect() with webStorageMode throws UnsupportedError on native',
      () async {
        if (_isWeb) return;
        await expectLater(
          KnexSQLite.connect(filename: ':memory:', webStorageMode: 'indexedDb'),
          throwsA(isA<UnsupportedError>()),
        );
      },
    );

    test('fromConfig() with storageMode throws UnsupportedError on native', () {
      if (_isWeb) return;
      expect(
        () => SQLiteClient.fromConfig(
          KnexConfig(
            client: 'sqlite3',
            connection: {'filename': ':memory:', 'storageMode': 'indexedDb'},
          ),
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test(
      'invalid webStorageMode still throws ArgumentError on native',
      () async {
        await expectLater(
          KnexSQLite.connect(filename: ':memory:', webStorageMode: 'bogus'),
          throwsA(isA<ArgumentError>()),
        );
      },
    );
  });
}
