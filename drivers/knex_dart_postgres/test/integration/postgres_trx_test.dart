/// Exhaustive transaction / error-path tests for KnexPostgres.
@Tags(['postgres'])
library;

import 'package:universal_io/io.dart';
import 'package:knex_dart_postgres/knex_dart_postgres.dart';
import 'package:test/test.dart';

// ── Connection helpers ────────────────────────────────────────────────────────

String get _host => Platform.environment['PG_HOST'] ?? 'localhost';
int get _port => int.parse(Platform.environment['PG_PORT'] ?? '5432');
String get _database => Platform.environment['PG_DATABASE'] ?? 'knex_test';
String get _user => Platform.environment['PG_USER'] ?? 'knex';
String get _password => Platform.environment['PG_PASSWORD'] ?? 'knex';

const _table = 'trx_test_postgres';

Future<KnexPostgres?> _tryConnect() async {
  try {
    final db = await KnexPostgres.connect(
      host: _host,
      port: _port,
      database: _database,
      username: _user,
      password: _password,
    );
    await db.rawSql('SELECT 1');
    return db;
  } catch (_) {
    return null;
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

Never _throwFromHelper(Object e) => throw e;

void main() {
  group('KnexPostgres transaction exhaustive', () {
    KnexPostgres? db;
    String? skipReason;

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

    // ── 3. Original exception preserved through rollback ─────────────────────

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

    // ── 4. Nested trx — inner rollback, outer commits ─────────────────────────

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

    // ── 5. Nested trx — both inner and outer commit ───────────────────────────

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

    // ── 6. Nested trx — inner rolls back, outer also rolls back ──────────────

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

    // ── 7. Pool releases connection after rollback ────────────────────────────

    test('pool releases connection after rollback — further queries work', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await expectLater(
        db!.trx((_) async => throw Exception('fail')),
        throwsA(isA<Exception>()),
      );

      // Pool must not be exhausted — this query must succeed.
      final result = await db!.rawSql('SELECT 1 AS n');
      expect(result.first['n'], isNotNull);
    });

    // ── 8. Concurrent transactions don't interfere ────────────────────────────

    test('concurrent transactions each commit their own rows', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await Future.wait([
        db!.trx((tx) async {
          await tx.insert(tx(_table).insert({'id': 40, 'name': 'Concurrent-A'}));
        }),
        db!.trx((tx) async {
          await tx.insert(tx(_table).insert({'id': 41, 'name': 'Concurrent-B'}));
        }),
        db!.trx((tx) async {
          await tx.insert(tx(_table).insert({'id': 42, 'name': 'Concurrent-C'}));
        }),
      ]);

      final rows = await db!.select(db!(_table).select(['*']));
      expect(rows, hasLength(3));
    });

    // ── 9. Double close is safe ───────────────────────────────────────────────

    test('double close does not throw', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      final pg = await _tryConnect();
      expect(pg, isNotNull);
      await pg!.close();
      await expectLater(pg.close(), completes);
    });

    // ── 10. Query after close throws StateError ───────────────────────────────

    test('query after close throws StateError', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      final pg = await _tryConnect();
      expect(pg, isNotNull);
      await pg!.close();

      await expectLater(
        pg.rawSql('SELECT 1'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
