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
    await client.raw('SELECT 1');
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

      await db!.raw(
        'INSERT INTO users (id, name, score) VALUES (1, ?, ?)',
        ['Alice', 9.5],
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

      await db!.raw(
        'INSERT INTO users (id, name, score) VALUES (1, ?, ?)',
        ['Bob', 7.0],
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

      await db!.raw('INSERT INTO users (id, name) VALUES (1, ?)', ['Carol']);
      await db!.execute(
        db!.queryBuilder().table('users').where('id', '=', 1).delete(),
      );
      final rows = await db!.select(db!.queryBuilder().from('users'));
      expect(rows, isEmpty);
    });

    test('select with limit and orderBy', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.raw(
        'INSERT INTO users (id, name, score) VALUES (1,?,?),(2,?,?),(3,?,?)',
        ['A', 5.0, 'B', 9.0, 'C', 3.0],
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

      await db!.raw(
        'INSERT INTO users (id, name, score) VALUES (1, ?, NULL)',
        ['Dave'],
      );
      final rows = await db!.select(
        db!.queryBuilder().from('users').where('id', '=', 1),
      );
      expect(rows.first['score'], isNull);
    });

    test('boolean 1/0 round-trips', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.raw(
        'INSERT INTO users (id, name, active) VALUES (1, ?, ?)',
        ['Eve', 1],
      );
      final rows = await db!.select(db!.queryBuilder().from('users'));
      expect(rows.first['active'], 1);
    });
  });

  group('Turso (sqld) — transactions', () {
    test('commits on success', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.trx((trx) async {
        await trx.raw('INSERT INTO users (id, name) VALUES (1, ?)', ['Frank']);
      });

      final rows = await db!.select(db!.queryBuilder().from('users'));
      expect(rows, hasLength(1));
    });

    test('rolls back on error', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await expectLater(
        db!.trx((trx) async {
          await trx.raw('INSERT INTO users (id, name) VALUES (1, ?)', ['Ghost']);
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
        await outer.raw('INSERT INTO users (id, name) VALUES (1, ?)', ['Outer']);
        try {
          await outer.trx((inner) async {
            await inner.raw(
              'INSERT INTO users (id, name) VALUES (2, ?)',
              ['Inner'],
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
      await db!.raw('''
        INSERT INTO users (id, name, role, score) VALUES
          (1,'Alice','admin',90),
          (2,'Bob','user',70),
          (3,'Carol','admin',85),
          (4,'Dave','user',60)
      ''');
    });

    test('GROUP BY + AVG', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      final rows = await db!.raw(
        'SELECT role, AVG(score) as avg_score FROM users GROUP BY role ORDER BY role',
      );
      final adminRow = rows.firstWhere((r) => r['role'] == 'admin');
      expect((adminRow['avg_score'] as num), closeTo(87.5, 0.01));
    });

    test('JOIN between tables', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.raw(
        'INSERT INTO orders VALUES (1,1,99.99,?),(2,2,49.99,?)',
        ['open', 'closed'],
      );

      final rows = await db!.raw('''
        SELECT u.name, o.amount
        FROM users u
        JOIN orders o ON u.id = o.user_id
        WHERE o.status = 'open'
      ''');
      expect(rows, hasLength(1));
      expect(rows.first['name'], 'Alice');
    });
  });

  group('Turso (sqld) — WHERE variants', () {
    setUp(() async {
      if (skipReason != null) return;
      await db!.raw('''
        INSERT INTO users (id, name, role, score) VALUES
          (1,'Alice','admin',90),(2,'Bob','user',70),(3,'Carol','admin',85),(4,'Dave','user',NULL)
      ''');
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
      await db!.raw("INSERT INTO users (id, name) VALUES (1, ?)", ["O'Brien"]);
      final rows = await db!.select(
        db!.queryBuilder().from('users').where('id', '=', 1),
      );
      expect(rows.first['name'], "O'Brien");
    });

    test('unicode string round-trips', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      await db!.raw('INSERT INTO users (id, name) VALUES (1, ?)', ['日本語テスト']);
      final rows = await db!.select(
        db!.queryBuilder().from('users').where('id', '=', 1),
      );
      expect(rows.first['name'], '日本語テスト');
    });

    test('empty string stored and returned correctly', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      await db!.raw('INSERT INTO users (id, name) VALUES (1, ?)', ['']);
      final rows = await db!.select(
        db!.queryBuilder().from('users').where('id', '=', 1),
      );
      expect(rows.first['name'], '');
    });

    test('zero and negative numbers round-trip', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      await db!.raw('INSERT INTO users (id, name, score) VALUES (1, ?, ?)', ['Zero', 0.0]);
      await db!.raw('INSERT INTO users (id, name, score) VALUES (2, ?, ?)', ['Neg', -99.5]);
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
      await db!.raw('''
        INSERT INTO users (id, name, role, score) VALUES
          (1,'Alice','admin',90),(2,'Bob','user',70),(3,'Carol','admin',85),(4,'Dave','user',60)
      ''');
    });

    test('COUNT(*)', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.raw('SELECT COUNT(*) as total FROM users');
      expect(rows.first['total'], 4);
    });

    test('MIN and MAX', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.raw(
        'SELECT MIN(score) as min_s, MAX(score) as max_s FROM users',
      );
      expect((rows.first['min_s'] as num).toDouble(), closeTo(60.0, 0.01));
      expect((rows.first['max_s'] as num).toDouble(), closeTo(90.0, 0.01));
    });

    test('UNION ALL combines result sets', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.raw('''
        SELECT name FROM users WHERE role = 'admin'
        UNION ALL
        SELECT name FROM users WHERE score < 65
        ORDER BY name
      ''');
      expect(rows, hasLength(3)); // Alice, Carol + Dave
    });

    test('RANK() OVER window function', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.raw(
        'SELECT name, RANK() OVER (ORDER BY score DESC) as rnk FROM users ORDER BY rnk',
      );
      expect(rows.first['name'], 'Alice');
      expect(rows.first['rnk'], 1);
    });

    test('CTE query', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.raw('''
        WITH top AS (SELECT name FROM users WHERE score > 80)
        SELECT name FROM top ORDER BY name
      ''');
      expect(rows.map((r) => r['name']).toList(), ['Alice', 'Carol']);
    });
  });

  group('Turso (sqld) — outer rollback loses all changes', () {
    test('outer trx rollback removes both outer and inner changes', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await expectLater(
        db!.trx((outer) async {
          await outer.raw('INSERT INTO users (id, name) VALUES (1, ?)', ['Outer']);
          await outer.trx((inner) async {
            await inner.raw('INSERT INTO users (id, name) VALUES (2, ?)', ['Inner']);
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
