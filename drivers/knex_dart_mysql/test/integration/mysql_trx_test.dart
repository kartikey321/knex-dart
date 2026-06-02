/// Exhaustive transaction / error-path tests for KnexMySQL.
@Tags(['mysql'])
library;

import 'package:universal_io/io.dart';
import 'package:knex_dart_mysql/knex_dart_mysql.dart';
import 'package:test/test.dart';

// ── Connection helpers ────────────────────────────────────────────────────────

String get _host => Platform.environment['MYSQL_HOST'] ?? 'localhost';
int get _port => int.parse(Platform.environment['MYSQL_PORT'] ?? '3306');
String get _user => Platform.environment['MYSQL_USER'] ?? 'knex';
String get _password => Platform.environment['MYSQL_PASSWORD'] ?? 'knex';
String get _database => Platform.environment['MYSQL_DATABASE'] ?? 'knex_test';

const _table = 'trx_test_mysql';

Future<KnexMySQL?> _tryConnect() async {
  try {
    final db = await KnexMySQL.connect(
      host: _host,
      port: _port,
      user: _user,
      password: _password,
      database: _database,
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
  group('KnexMySQL transaction exhaustive', () {
    KnexMySQL? db;
    String? skipReason;

    setUpAll(() async {
      final candidate = await _tryConnect();
      if (candidate == null) {
        skipReason =
            'MySQL not reachable at $_host:$_port — start via `docker compose up mysql -d`';
        return;
      }
      db = candidate;
      await db!.rawSql(
        'CREATE TABLE IF NOT EXISTS $_table '
        '(id INT PRIMARY KEY, name VARCHAR(255))',
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

    // ── 3. Original exception type preserved ─────────────────────────────────

    test('original exception type and message preserved through rollback', () async {
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

    // ── 6. Inner and outer both roll back — nothing committed ─────────────────

    test('nested trx: inner and outer both roll back', () async {
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

      final result = await db!.rawSql('SELECT 1 AS n');
      expect(result.first['n'], isNotNull);
    });

    // ── 8. Concurrent transactions ────────────────────────────────────────────

    test('concurrent transactions each commit their own rows', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await Future.wait([
        db!.trx((tx) async {
          await tx.insert(tx(_table).insert({'id': 40, 'name': 'A'}));
        }),
        db!.trx((tx) async {
          await tx.insert(tx(_table).insert({'id': 41, 'name': 'B'}));
        }),
        db!.trx((tx) async {
          await tx.insert(tx(_table).insert({'id': 42, 'name': 'C'}));
        }),
      ]);

      final rows = await db!.select(db!(_table).select(['*']));
      expect(rows, hasLength(3));
    });

    // ── 9. Double close is safe ───────────────────────────────────────────────

    test('double close does not throw', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      final c = await _tryConnect();
      expect(c, isNotNull);
      await c!.close();
      await expectLater(c.close(), completes);
    });

    // ── 10. Query after close throws StateError ───────────────────────────────

    test('query after close throws StateError', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      final c = await _tryConnect();
      expect(c, isNotNull);
      await c!.close();

      await expectLater(
        c.rawSql('SELECT 1'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
