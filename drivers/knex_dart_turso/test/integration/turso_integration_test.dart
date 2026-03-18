/// Integration tests for knex_dart_turso against a real sqld server.
///
/// Requires sqld running locally:
///   docker compose up sqld -d
///
/// Or set TURSO_URL to point at any libSQL-compatible server (sqld / Turso cloud).
@Tags(['turso'])
library;

import 'dart:io';

import 'package:knex_dart_turso/knex_dart_turso.dart';
import 'package:test/test.dart';

// ─── Connection config ────────────────────────────────────────────────────────

String get _url =>
    Platform.environment['TURSO_URL'] ?? 'http://localhost:8080';
String? get _token => Platform.environment['TURSO_AUTH_TOKEN']; // optional

// ─── Helpers ─────────────────────────────────────────────────────────────────

Future<KnexTurso?> _tryOpen() async {
  try {
    final client = KnexTurso(url: _url, authToken: _token ?? '');
    // Probe with a simple query
    await client.executeRaw('SELECT 1');
    return client;
  } catch (e) {
    return null;
  }
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  KnexTurso? db;
  String? skipReason;

  setUpAll(() async {
    final candidate = await _tryOpen();
    if (candidate == null) {
      skipReason =
          'sqld not reachable at $_url — start via `docker compose up sqld -d`';
      return;
    }
     candidate.close();
  });

  setUp(() async {
    if (skipReason != null) return;
    db = KnexTurso(url: _url, authToken: _token ?? '');

    await db!.executeSchema((schema) {
      schema.dropTableIfExists('orders');
      schema.dropTableIfExists('users');
      schema.createTable('users', (t) {
        t.integer('id').primary();
        t.string('name').notNullable();
        t.string('role').nullable().defaultTo('user');
        t.float('score').nullable();
        t.integer('active').defaultTo(1);
      });
      schema.createTable('orders', (t) {
        t.integer('id').primary();
        t.integer('user_id').nullable();
        t.float('amount').nullable();
        t.string('status').nullable();
      });
    });
  });

  tearDown(() async {
     db?.close();
    db = null;
  });

  group('Turso (sqld) — basic CRUD', () {
    test('insert and select', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.execute(
        db!.queryBuilder().table('users').insert({
          'id': 1,
          'name': 'Alice',
          'score': 9.5,
        }),
      );

      final rows = await db!.select(
        db!.queryBuilder().from('users').where('id', '=', 1),
      );
      expect(rows, hasLength(1));
      expect(rows.first['name'], 'Alice');
      expect(rows.first['score'], closeTo(9.5, 0.001));
    });

    test('update changes a value', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.execute(
        db!.queryBuilder().table('users').insert({
          'id': 1,
          'name': 'Bob',
          'score': 7.0,
        }),
      );
      await db!.execute(
        db!.queryBuilder()
            .table('users')
            .where('id', '=', 1)
            .update({'score': 8.0}),
      );

      final rows = await db!.select(
        db!.queryBuilder().from('users').where('id', '=', 1),
      );
      expect(rows.first['score'], closeTo(8.0, 0.001));
    });

    test('delete removes a row', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.execute(
        db!.queryBuilder().table('users').insert({'id': 1, 'name': 'Carol'}),
      );
      await db!.execute(
        db!.queryBuilder().table('users').where('id', '=', 1).delete(),
      );
      final rows = await db!.select(db!.queryBuilder().from('users'));
      expect(rows, isEmpty);
    });

    test('select with limit and orderBy', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.execute(
        db!.queryBuilder().table('users').insert([
          {'id': 1, 'name': 'A', 'score': 5.0},
          {'id': 2, 'name': 'B', 'score': 9.0},
          {'id': 3, 'name': 'C', 'score': 3.0},
        ]),
      );

      final rows = await db!.select(
        db!.queryBuilder().from('users').orderBy('score', 'desc').limit(2),
      );
      expect(rows, hasLength(2));
      expect(rows.first['name'], 'B');
    });
  });

  group('Turso (sqld) — null / type handling', () {
    test('null value round-trips', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.execute(
        db!.queryBuilder().table('users').insert({
          'id': 1,
          'name': 'Dave',
          'score': null,
        }),
      );
      final rows = await db!.select(
        db!.queryBuilder().from('users').where('id', '=', 1),
      );
      expect(rows.first['score'], isNull);
    });

    test('boolean 1/0 round-trips', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.execute(
        db!.queryBuilder().table('users').insert({
          'id': 1,
          'name': 'Eve',
          'active': 1,
        }),
      );
      final rows = await db!.select(db!.queryBuilder().from('users'));
      expect(rows.first['active'], 1);
    });
  });

  group('Turso (sqld) — transactions', () {
    test('commits on success', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.trx((trx) async {
        await trx.execute(
          db!.queryBuilder().table('users').insert({'id': 1, 'name': 'Frank'}),
        );
      });

      final rows = await db!.select(db!.queryBuilder().from('users'));
      expect(rows, hasLength(1));
    });

    test('rolls back on error', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await expectLater(
        db!.trx((trx) async {
          await trx.execute(
            db!.queryBuilder().table('users').insert({'id': 1, 'name': 'Ghost'}),
          );
          throw Exception('force rollback');
        }),
        throwsException,
      );

      final rows = await db!.select(db!.queryBuilder().from('users'));
      expect(rows, isEmpty);
    });

    test('nested trx — inner rollback, outer catches and commits', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.trx((outer) async {
        await outer.execute(
          db!.queryBuilder().table('users').insert({'id': 1, 'name': 'Outer'}),
        );
        try {
          await outer.trx((inner) async {
            await inner.execute(
              db!.queryBuilder().table('users').insert({'id': 2, 'name': 'Inner'}),
            );
            throw Exception('inner fails');
          });
        } catch (_) {}
      });

      final rows = await db!.select(
        db!.queryBuilder().from('users').orderBy('id'),
      );
      expect(rows, hasLength(1));
      expect(rows.first['name'], 'Outer');
    });
  });

  group('Turso (sqld) — analytical SQL', () {
    setUp(() async {
      if (skipReason != null) return;
      await db!.execute(
        db!.queryBuilder().table('users').insert([
          {'id': 1, 'name': 'Alice', 'role': 'admin', 'score': 90},
          {'id': 2, 'name': 'Bob', 'role': 'user', 'score': 70},
          {'id': 3, 'name': 'Carol', 'role': 'admin', 'score': 85},
          {'id': 4, 'name': 'Dave', 'role': 'user', 'score': 60},
        ]),
      );
    });

    test('GROUP BY + AVG', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      final rows = await db!.select(
        db!
            .queryBuilder()
            .from('users')
            .select(['role', db!.raw('AVG(score) as avg_score')])
            .groupBy('role')
            .orderBy('role'),
      );
      final adminRow = rows.firstWhere((r) => r['role'] == 'admin');
      expect((adminRow['avg_score'] as num), closeTo(87.5, 0.01));
    });

    test('JOIN between tables', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.execute(
        db!.queryBuilder().table('orders').insert([
          {'id': 1, 'user_id': 1, 'amount': 99.99, 'status': 'open'},
          {'id': 2, 'user_id': 2, 'amount': 49.99, 'status': 'closed'},
        ]),
      );

      final rows = await db!.select(
        db!
            .queryBuilder()
            .from('users as u')
            .join('orders as o', 'u.id', 'o.user_id')
            .where('o.status', '=', 'open')
            .select(['u.name', 'o.amount']),
      );
      expect(rows, hasLength(1));
      expect(rows.first['name'], 'Alice');
    });
  });

  group('Turso (sqld) — WHERE variants', () {
    setUp(() async {
      if (skipReason != null) return;
      await db!.execute(
        db!.queryBuilder().table('users').insert([
          {'id': 1, 'name': 'Alice', 'role': 'admin', 'score': 90},
          {'id': 2, 'name': 'Bob', 'role': 'user', 'score': 70},
          {'id': 3, 'name': 'Carol', 'role': 'admin', 'score': 85},
          {'id': 4, 'name': 'Dave', 'role': 'user', 'score': null},
        ]),
      );
    });

    test('whereIn filters by list', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.select(
        db!.queryBuilder().from('users').whereIn('role', ['admin']),
      );
      expect(rows, hasLength(2));
      expect(rows.every((r) => r['role'] == 'admin'), isTrue);
    });

    test('whereNull finds NULL rows', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.select(
        db!.queryBuilder().from('users').whereNull('score'),
      );
      expect(rows, hasLength(1));
      expect(rows.first['name'], 'Dave');
    });

    test('where with > comparison', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.select(
        db!.queryBuilder().from('users').where('score', '>', 80),
      );
      expect(rows, hasLength(2));
    });

    test('orWhere expands result set', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.select(
        db!.queryBuilder().from('users')
            .where('name', 'Alice').orWhere('name', 'Dave'),
      );
      expect(rows, hasLength(2));
    });

    test('offset + limit paginates', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final page = await db!.select(
        db!.queryBuilder().from('users').orderBy('id').limit(2).offset(1),
      );
      expect(page, hasLength(2));
      expect(page.first['id'], 2);
    });
  });

  group('Turso (sqld) — string / type edge cases', () {
    test("string with single quote round-trips", () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      await db!.execute(
        db!.queryBuilder().table('users').insert({'id': 1, 'name': "O'Brien"}),
      );
      final rows = await db!.select(
        db!.queryBuilder().from('users').where('id', '=', 1),
      );
      expect(rows.first['name'], "O'Brien");
    });

    test('unicode string round-trips', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      await db!.execute(
        db!.queryBuilder().table('users').insert({'id': 1, 'name': '日本語テスト'}),
      );
      final rows = await db!.select(
        db!.queryBuilder().from('users').where('id', '=', 1),
      );
      expect(rows.first['name'], '日本語テスト');
    });

    test('empty string stored and returned correctly', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      await db!.execute(
        db!.queryBuilder().table('users').insert({'id': 1, 'name': ''}),
      );
      final rows = await db!.select(
        db!.queryBuilder().from('users').where('id', '=', 1),
      );
      expect(rows.first['name'], '');
    });

    test('zero and negative numbers round-trip', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      await db!.execute(
        db!.queryBuilder().table('users').insert([
          {'id': 1, 'name': 'Zero', 'score': 0.0},
          {'id': 2, 'name': 'Neg', 'score': -99.5},
        ]),
      );
      final rows = await db!.select(
        db!.queryBuilder().from('users').orderBy('id'),
      );
      expect((rows[0]['score'] as num).toDouble(), 0.0);
      expect((rows[1]['score'] as num).toDouble(), closeTo(-99.5, 0.001));
    });
  });

  group('Turso (sqld) — aggregate and window SQL extended', () {
    setUp(() async {
      if (skipReason != null) return;
      await db!.execute(
        db!.queryBuilder().table('users').insert([
          {'id': 1, 'name': 'Alice', 'role': 'admin', 'score': 90},
          {'id': 2, 'name': 'Bob', 'role': 'user', 'score': 70},
          {'id': 3, 'name': 'Carol', 'role': 'admin', 'score': 85},
          {'id': 4, 'name': 'Dave', 'role': 'user', 'score': 60},
        ]),
      );
    });

    test('COUNT(*)', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.select(
        db!.queryBuilder().from('users').count('* as total'),
      );
      expect(rows.first['total'], 4);
    });

    test('MIN and MAX', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.select(
        db!.queryBuilder().from('users').min('score as min_s').max('score as max_s'),
      );
      expect((rows.first['min_s'] as num).toDouble(), closeTo(60.0, 0.01));
      expect((rows.first['max_s'] as num).toDouble(), closeTo(90.0, 0.01));
    });

    test('UNION ALL combines result sets', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final admins = db!
          .queryBuilder()
          .from('users')
          .select(['name'])
          .where('role', '=', 'admin');
      final lowScores = db!
          .queryBuilder()
          .from('users')
          .select(['name'])
          .where('score', '<', 65);
      final rows = await db!.select(admins.unionAll([lowScores]).orderBy('name'));
      expect(rows, hasLength(3)); // Alice, Carol + Dave
    });

    test('RANK() OVER window function', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.select(
        db!
            .queryBuilder()
            .from('users')
            .select(['name'])
            .rank('rnk', db!.raw('"score" desc'))
            .orderBy('rnk'),
      );
      expect(rows.first['name'], 'Alice');
      expect(rows.first['rnk'], 1);
    });

    test('CTE query', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.select(
        db!
            .queryBuilder()
            .withQuery('top', db!.queryBuilder().from('users').select(['name']).where('score', '>', 80))
            .from('top')
            .select(['name'])
            .orderBy('name'),
      );
      expect(rows.map((r) => r['name']).toList(), ['Alice', 'Carol']);
    });
  });

  group('Turso (sqld) — outer rollback loses all changes', () {
    test('outer trx rollback removes both outer and inner changes', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await expectLater(
        db!.trx((outer) async {
          await outer.execute(
            db!.queryBuilder().table('users').insert({'id': 1, 'name': 'Outer'}),
          );
          await outer.trx((inner) async {
            await inner.execute(
              db!.queryBuilder().table('users').insert({'id': 2, 'name': 'Inner'}),
            );
          });
          throw Exception('outer fails');
        }),
        throwsA(isA<Object>()),
      );

      final rows = await db!.select(db!.queryBuilder().from('users'));
      expect(rows, isEmpty);
    });
  });
}
