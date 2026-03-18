@Tags(['mssql'])
library;

import 'dart:io';

import 'package:knex_dart_mssql/knex_dart_mssql.dart';
import 'package:test/test.dart';

// ─── Connection config from environment ──────────────────────────────────────

String get _host => Platform.environment['MSSQL_HOST'] ?? 'localhost';
String get _port => Platform.environment['MSSQL_PORT'] ?? '1433';
String get _database => Platform.environment['MSSQL_DATABASE'] ?? 'knex_test';
String get _user => Platform.environment['MSSQL_USER'] ?? 'sa';
String get _password =>
    Platform.environment['MSSQL_PASSWORD'] ?? 'Knex_Test1!';

// ─── Helpers ─────────────────────────────────────────────────────────────────

Future<KnexMssql?> _tryConnect() async {
  try {
    return await KnexMssql.connect(
      host: _host,
      port: _port,
      database: _database,
      username: _user,
      password: _password,
    );
  } catch (e) {
    return null;
  }
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  KnexMssql? db;
  String? skipReason;

  setUpAll(() async {
    final candidate = await _tryConnect();
    if (candidate == null) {
      skipReason =
          'SQL Server not reachable at $_host:$_port — start via `docker compose up mssql -d`';
      return;
    }
    await candidate.close();
  });

  setUp(() async {
    if (skipReason != null) return;
    db = await KnexMssql.connect(
      host: _host,
      port: _port,
      database: _database,
      username: _user,
      password: _password,
    );

    await db!.executeSchema((schema) {
      schema.dropTableIfExists('orders');
      schema.dropTableIfExists('users');
      schema.createTable('users', (t) {
        t.integer('id').notNullable().primary();
        t.string('name').notNullable();
        t.string('role').notNullable().defaultTo('user');
        t.float('score').nullable();
        t.specificType('active', 'bit').notNullable().defaultTo(1);
      });
      schema.createTable('orders', (t) {
        t.integer('id').notNullable().primary();
        t.integer('user_id').nullable();
        t.float('amount').nullable();
        t.string('status').nullable();
      });
    });
    await db!.raw('DELETE FROM orders');
    await db!.raw('DELETE FROM users');
  });

  tearDown(() async {
    await db?.close();
    db = null;
  });

  group('MssqlClient — basic CRUD', () {
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

      await db!.raw(
        'INSERT INTO users (id, name) VALUES (1, ?)',
        ['Carol'],
      );
      await db!.execute(
        db!.queryBuilder().table('users').where('id', '=', 1).delete(),
      );
      final rows = await db!.select(db!.queryBuilder().from('users'));
      expect(rows, isEmpty);
    });
  });

  group('MssqlClient — transactions', () {
    test('commits on success — changes visible', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.trx((trx) async {
        await trx.raw(
          'INSERT INTO users (id, name) VALUES (1, ?)',
          ['Frank'],
        );
      });

      final rows = await db!.select(db!.queryBuilder().from('users'));
      expect(rows, hasLength(1));
    });

    test('rolls back on error — changes not visible', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await expectLater(
        db!.trx((trx) async {
          await trx.raw(
            'INSERT INTO users (id, name) VALUES (1, ?)',
            ['Ghost'],
          );
          throw Exception('force rollback');
        }),
        throwsException,
      );

      final rows = await db!.select(db!.queryBuilder().from('users'));
      expect(rows, isEmpty);
    });

    test('nested trx uses SAVE TRANSACTION — inner rollback, outer commits',
        () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.trx((outer) async {
        await outer.raw(
          'INSERT INTO users (id, name) VALUES (1, ?)',
          ['Outer'],
        );
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

  group('MssqlClient — analytical SQL', () {
    setUp(() async {
      if (skipReason != null) return;
      await db!.raw('''
        INSERT INTO users (id, name, role, score) VALUES
          (1, \'Alice\', \'admin\', 90),
          (2, \'Bob\',   \'user\',  70),
          (3, \'Carol\', \'admin\', 85),
          (4, \'Dave\',  \'user\',  60)
      ''');
    });

    test('GROUP BY + AVG aggregate', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      final rows = await db!.raw(
        'SELECT role, AVG(score) as avg_score FROM users GROUP BY role ORDER BY role',
      );
      final adminRow = rows.firstWhere((r) => r['role'] == 'admin');
      expect((adminRow['avg_score'] as num), closeTo(87.5, 0.01));
    });

    test('window function — RANK() OVER', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      final rows = await db!.raw('''
        SELECT name, score,
               RANK() OVER (ORDER BY score DESC) AS rnk
        FROM users
        ORDER BY rnk
      ''');
      expect(rows.first['name'], 'Alice');
      expect(rows.first['rnk'], 1);
    });

    test('JOIN between tables', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.raw(
        'INSERT INTO orders VALUES (1, 1, 99.99, ?), (2, 2, 49.99, ?)',
        ['open', 'closed'],
      );

      final rows = await db!.raw('''
        SELECT u.name, o.amount
        FROM users u
        JOIN orders o ON u.id = o.user_id
        WHERE o.status = \'open\'
      ''');
      expect(rows, hasLength(1));
      expect(rows.first['name'], 'Alice');
    });
  });

  group('MssqlClient — filtering variants', () {
    setUp(() async {
      if (skipReason != null) return;
      await db!.raw(
        'INSERT INTO users (id, name, role, score) VALUES (1, ?, ?, ?), (2, ?, ?, ?), (3, ?, ?, ?), (4, ?, ?, ?)',
        ['Alice', 'admin', 90.0, 'Bob', 'user', 70.0, 'Carol', 'admin', 85.0, 'Dave', 'user', null],
      );
    });

    test('WHERE with single ? binding', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.raw('SELECT name FROM users WHERE name = ?', ['Alice']);
      expect(rows, hasLength(1));
      expect(rows.first['name'], 'Alice');
    });

    test('whereIn via QueryBuilder', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.select(
        db!.queryBuilder().from('users').whereIn('role', ['admin']),
      );
      expect(rows, hasLength(2));
      expect(rows.every((r) => r['role'] == 'admin'), isTrue);
    });

    test('IS NULL check via raw', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.raw('SELECT name FROM users WHERE score IS NULL');
      expect(rows, hasLength(1));
      expect(rows.first['name'], 'Dave');
    });

    test('IS NOT NULL check via raw', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.raw('SELECT name FROM users WHERE score IS NOT NULL');
      expect(rows, hasLength(3));
    });

    test('multiple WHERE conditions with AND', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.raw(
        'SELECT name FROM users WHERE role = ? AND score > ?',
        ['admin', 87.0],
      );
      expect(rows, hasLength(1));
      expect(rows.first['name'], 'Alice');
    });

    test('ORDER BY multiple columns', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.raw(
        'SELECT name, role FROM users WHERE score IS NOT NULL ORDER BY role ASC, score DESC',
      );
      expect(rows.first['name'], 'Alice');   // admin, score 90
      expect(rows[1]['name'], 'Carol');       // admin, score 85
    });
  });

  group('MssqlClient — pagination (TOP / OFFSET-FETCH)', () {
    setUp(() async {
      if (skipReason != null) return;
      await db!.raw(
        'INSERT INTO users (id, name) VALUES (1, ?), (2, ?), (3, ?), (4, ?), (5, ?)',
        ['A', 'B', 'C', 'D', 'E'],
      );
    });

    test('TOP N limits results', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.raw('SELECT TOP 3 name FROM users ORDER BY id');
      expect(rows, hasLength(3));
    });

    test('OFFSET-FETCH paginates correctly', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.raw(
        'SELECT name FROM users ORDER BY id OFFSET 2 ROWS FETCH NEXT 2 ROWS ONLY',
      );
      expect(rows, hasLength(2));
      expect(rows.first['name'], 'C'); // skipped A, B
    });
  });

  group('MssqlClient — GROUP BY / HAVING', () {
    setUp(() async {
      if (skipReason != null) return;
      await db!.raw(
        'INSERT INTO users (id, name, role, score) VALUES (1, ?, ?, ?), (2, ?, ?, ?), (3, ?, ?, ?), (4, ?, ?, ?)',
        ['Alice', 'admin', 90.0, 'Bob', 'user', 70.0, 'Carol', 'admin', 85.0, 'Dave', 'user', 60.0],
      );
    });

    test('GROUP BY role with COUNT', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.raw(
        'SELECT role, COUNT(*) AS cnt FROM users GROUP BY role ORDER BY role',
      );
      expect(rows, hasLength(2));
      final adminRow = rows.firstWhere((r) => r['role'] == 'admin');
      expect(adminRow['cnt'], 2);
    });

    test('HAVING filters groups', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.raw(
        'SELECT role, AVG(score) AS avg_s FROM users GROUP BY role HAVING AVG(score) > 80 ORDER BY role',
      );
      expect(rows, hasLength(1));
      expect(rows.first['role'], 'admin'); // avg 87.5; users avg 65 fails
    });
  });

  group('MssqlClient — CTEs and subqueries', () {
    setUp(() async {
      if (skipReason != null) return;
      await db!.raw(
        'INSERT INTO users (id, name, role, score) VALUES (1, ?, ?, ?), (2, ?, ?, ?), (3, ?, ?, ?)',
        ['Alice', 'admin', 90.0, 'Bob', 'user', 70.0, 'Carol', 'admin', 85.0],
      );
      await db!.raw(
        'INSERT INTO orders (id, user_id, amount, status) VALUES (1, 1, 99.99, ?), (2, 2, 49.99, ?), (3, 1, 29.99, ?)',
        ['open', 'closed', 'open'],
      );
    });

    test('subquery in WHERE IN', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.raw('''
        SELECT name FROM users
        WHERE id IN (SELECT user_id FROM orders WHERE status = 'open')
        ORDER BY name
      ''');
      expect(rows, hasLength(1));
      expect(rows.first['name'], 'Alice');
    });

    test('CTE (WITH clause)', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.raw('''
        WITH top_users AS (SELECT id, name FROM users WHERE score > 80)
        SELECT name FROM top_users ORDER BY name
      ''');
      expect(rows.map((r) => r['name']).toList(), ['Alice', 'Carol']);
    });

    test('EXISTS correlated subquery', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.raw('''
        SELECT name FROM users u
        WHERE EXISTS (
          SELECT 1 FROM orders o WHERE o.user_id = u.id AND o.status = 'open'
        )
        ORDER BY name
      ''');
      expect(rows, hasLength(1));
      expect(rows.first['name'], 'Alice');
    });
  });

  group('MssqlClient — nested transaction scenarios extended', () {
    test('outer rollback — both outer and inner changes lost', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await expectLater(
        db!.trx((outer) async {
          await outer.raw('INSERT INTO users (id, name) VALUES (1, ?)', ['Outer']);
          await outer.trx((inner) async {
            await inner.raw('INSERT INTO users (id, name) VALUES (2, ?)', ['Inner']);
          });
          throw Exception('outer fails');
        }),
        throwsException,
      );

      final rows = await db!.select(db!.queryBuilder().from('users'));
      expect(rows, isEmpty);
    });

    test('two sequential savepoints both succeed', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.trx((outer) async {
        await outer.trx((sp1) async {
          await sp1.raw('INSERT INTO users (id, name) VALUES (1, ?)', ['SP1']);
        });
        await outer.trx((sp2) async {
          await sp2.raw('INSERT INTO users (id, name) VALUES (2, ?)', ['SP2']);
        });
      });

      final rows = await db!.select(
        db!.queryBuilder().from('users').orderBy('id'),
      );
      expect(rows, hasLength(2));
      expect(rows.first['name'], 'SP1');
      expect(rows.last['name'], 'SP2');
    });
  });

  group('MssqlClient — type handling', () {
    test('multiple ? bindings round-trip', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      await db!.raw(
        'INSERT INTO users (id, name, role, score) VALUES (?, ?, ?, ?)',
        [42, 'Multi', 'user', 7.7],
      );
      final rows = await db!.raw('SELECT * FROM users WHERE id = ?', [42]);
      expect(rows, hasLength(1));
      expect(rows.first['name'], 'Multi');
      expect((rows.first['score'] as num).toDouble(), closeTo(7.7, 0.001));
    });

    test('NULL score returns null in Dart', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      await db!.raw('INSERT INTO users (id, name) VALUES (1, ?)', ['NullScore']);
      final rows = await db!.raw('SELECT score FROM users WHERE id = 1');
      expect(rows.first['score'], isNull);
    });

    test('FLOAT precision round-trips', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      await db!.raw(
        'INSERT INTO users (id, name, score) VALUES (1, ?, ?)',
        ['Precise', 3.14159],
      );
      final rows = await db!.raw('SELECT score FROM users WHERE id = 1');
      expect((rows.first['score'] as num).toDouble(), closeTo(3.14159, 0.0001));
    });
  });

  group('MssqlClient — QueryBuilder SQL shape', () {
    test('queryBuilder generates double-quote identifiers', () {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final compiled = db!
          .queryBuilder()
          .from('users')
          .where('role', 'admin')
          .select(['name', 'score'])
          .toSQL();
      expect(compiled.sql, contains('"users"'));
      expect(compiled.sql, contains('"name"'));
      expect(compiled.sql, contains('?'));
      expect(compiled.bindings, ['admin']);
    });

    test('INSERT QueryBuilder executes correctly', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      await db!.execute(
        db!.queryBuilder().table('users').insert({
          'id': 77,
          'name': 'QBUser',
          'role': 'admin',
          'score': 88.0,
        }),
      );
      final rows = await db!.select(
        db!.queryBuilder().from('users').where('id', '=', 77),
      );
      expect(rows, hasLength(1));
      expect(rows.first['name'], 'QBUser');
    });
  });
}
