/// Exhaustive transaction / error-path tests for KnexMssql.
@Tags(['mssql'])
library;

import 'package:universal_io/io.dart';
import 'package:knex_dart_mssql/knex_dart_mssql.dart';
import 'package:test/test.dart';

// ── Connection helpers ────────────────────────────────────────────────────────

String get _host => Platform.environment['MSSQL_HOST'] ?? 'localhost';
String get _port => Platform.environment['MSSQL_PORT'] ?? '1433';
String get _database => Platform.environment['MSSQL_DATABASE'] ?? 'knex_test';
String get _user => Platform.environment['MSSQL_USER'] ?? 'sa';
String get _password => Platform.environment['MSSQL_PASSWORD'] ?? 'Knex_Test1!';

const _table = 'trx_test_mssql';

Future<KnexMssql?> _tryConnect() async {
  try {
    final db = await KnexMssql.connect(
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
  group('KnexMssql transaction exhaustive', () {
    KnexMssql? db;
    String? skipReason;

    setUpAll(() async {
      final candidate = await _tryConnect();
      if (candidate == null) {
        skipReason =
            'MSSQL not reachable at $_host:$_port — start via `docker compose up mssql -d`';
        return;
      }
      db = candidate;
      await db!.rawSql(
        'IF NOT EXISTS (SELECT * FROM sysobjects WHERE name=\'$_table\') '
        'CREATE TABLE $_table (id INT PRIMARY KEY, name NVARCHAR(255))',
      );
    });

    tearDownAll(() async {
      await db?.rawSql('IF OBJECT_ID(\'$_table\') IS NOT NULL DROP TABLE $_table');
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

    // ── 4. Nested trx — SAVE TRANSACTION, inner rolls back, outer commits ─────

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

      final c = await _tryConnect();
      expect(c, isNotNull);
      await c!.close();
      await expectLater(c.close(), completes);
    });

    // ── 8. Query after close throws StateError ────────────────────────────────

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
