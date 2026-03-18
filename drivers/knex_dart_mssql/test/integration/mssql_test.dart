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
    await db!.execute(db!.queryBuilder().table('orders').delete());
    await db!.execute(db!.queryBuilder().table('users').delete());
  });

  tearDown(() async {
    await db?.close();
    db = null;
  });

  group('MssqlClient — basic CRUD', () {
    test('insert and select', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.execute(
        db!.queryBuilder().table('users').insert({'id': 1, 'name': 'Alice', 'score': 9.5}),
      );

      final rows = await db!.select(
        db!.queryBuilder().from('users').where('id', '=', 1),
      );
      expect(rows, hasLength(1));
      expect(rows.first['name'], 'Alice');
    });

    test('update changes a value', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.execute(
        db!.queryBuilder().table('users').insert({'id': 1, 'name': 'Bob', 'score': 7.0}),
      );
      await db!.execute(
        db!.queryBuilder().table('users').where('id', '=', 1).update({'score': 8.0}),
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
  });

  group('MssqlClient — transactions', () {
    test('commits on success — changes visible', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.trx((trx) async {
        await trx.execute(
          db!.queryBuilder().table('users').insert({'id': 1, 'name': 'Frank'}),
        );
      });

      final rows = await db!.select(db!.queryBuilder().from('users'));
      expect(rows, hasLength(1));
    });

    test('rolls back on error — changes not visible', () async {
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

    test('nested trx uses SAVE TRANSACTION — inner rollback, outer commits',
        () async {
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

  group('MssqlClient — analytical SQL', () {
    setUp(() async {
      if (skipReason != null) return;
      await db!.execute(db!.queryBuilder().table('users').insert([
        {'id': 1, 'name': 'Alice', 'role': 'admin', 'score': 90.0},
        {'id': 2, 'name': 'Bob',   'role': 'user',  'score': 70.0},
        {'id': 3, 'name': 'Carol', 'role': 'admin', 'score': 85.0},
        {'id': 4, 'name': 'Dave',  'role': 'user',  'score': 60.0},
      ]));
    });

    test('GROUP BY + AVG aggregate', () async {
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

    test('window function — RANK() OVER', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      final rows = await db!.select(
        db!
            .queryBuilder()
            .from('users')
            .select(['name', 'score'])
            .rank('rnk', db!.raw('"score" desc'))
            .orderBy('rnk'),
      );
      expect(rows.first['name'], 'Alice');
      expect(rows.first['rnk'], 1);
    });

    test('JOIN between tables', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.execute(db!.queryBuilder().table('orders').insert([
        {'id': 1, 'user_id': 1, 'amount': 99.99, 'status': 'open'},
        {'id': 2, 'user_id': 2, 'amount': 49.99, 'status': 'closed'},
      ]));

      final rows = await db!.select(
        db!.queryBuilder()
            .from('users')
            .join('orders', 'users.id', 'orders.user_id')
            .where('orders.status', '=', 'open')
            .select(['users.name', 'orders.amount']),
      );
      expect(rows, hasLength(1));
      expect(rows.first['name'], 'Alice');
    });
  });

  group('MssqlClient — filtering variants', () {
    setUp(() async {
      if (skipReason != null) return;
      await db!.execute(db!.queryBuilder().table('users').insert([
        {'id': 1, 'name': 'Alice', 'role': 'admin', 'score': 90.0},
        {'id': 2, 'name': 'Bob',   'role': 'user',  'score': 70.0},
        {'id': 3, 'name': 'Carol', 'role': 'admin', 'score': 85.0},
        {'id': 4, 'name': 'Dave',  'role': 'user',  'score': null},
      ]));
    });

    test('WHERE with single binding', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.select(
        db!.queryBuilder().from('users').where('name', '=', 'Alice').select(['name']),
      );
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

    test('whereNull check', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.select(
        db!.queryBuilder().from('users').whereNull('score').select(['name']),
      );
      expect(rows, hasLength(1));
      expect(rows.first['name'], 'Dave');
    });

    test('whereNotNull check', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.select(
        db!.queryBuilder().from('users').whereNotNull('score').select(['name']),
      );
      expect(rows, hasLength(3));
    });

    test('multiple WHERE conditions with AND', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.select(
        db!.queryBuilder()
            .from('users')
            .where('role', '=', 'admin')
            .where('score', '>', 87.0)
            .select(['name']),
      );
      expect(rows, hasLength(1));
      expect(rows.first['name'], 'Alice');
    });

    test('ORDER BY multiple columns', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.select(
        db!.queryBuilder()
            .from('users')
            .whereNotNull('score')
            .orderBy('role', 'asc')
            .orderBy('score', 'desc')
            .select(['name', 'role']),
      );
      expect(rows.first['name'], 'Alice');   // admin, score 90
      expect(rows[1]['name'], 'Carol');       // admin, score 85
    });
  });

  group('MssqlClient — pagination (TOP / OFFSET-FETCH)', () {
    setUp(() async {
      if (skipReason != null) return;
      await db!.execute(db!.queryBuilder().table('users').insert([
        {'id': 1, 'name': 'A'},
        {'id': 2, 'name': 'B'},
        {'id': 3, 'name': 'C'},
        {'id': 4, 'name': 'D'},
        {'id': 5, 'name': 'E'},
      ]));
    });

    test('TOP N limits results', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.select(
        db!
            .queryBuilder()
            .from('users')
            .select(['name'])
            .orderBy('id')
            .limit(3),
      );
      expect(rows, hasLength(3));
    });

    test('OFFSET-FETCH paginates correctly', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.select(
        db!.queryBuilder().from('users').orderBy('id').offset(2).limit(2).select(['name']),
      );
      expect(rows, hasLength(2));
      expect(rows.first['name'], 'C'); // skipped A, B
    });
  });

  group('MssqlClient — GROUP BY / HAVING', () {
    setUp(() async {
      if (skipReason != null) return;
      await db!.execute(db!.queryBuilder().table('users').insert([
        {'id': 1, 'name': 'Alice', 'role': 'admin', 'score': 90.0},
        {'id': 2, 'name': 'Bob',   'role': 'user',  'score': 70.0},
        {'id': 3, 'name': 'Carol', 'role': 'admin', 'score': 85.0},
        {'id': 4, 'name': 'Dave',  'role': 'user',  'score': 60.0},
      ]));
    });

    test('GROUP BY role with COUNT', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.select(
        db!
            .queryBuilder()
            .from('users')
            .select(['role', db!.raw('COUNT(*) AS cnt')])
            .groupBy('role')
            .orderBy('role'),
      );
      expect(rows, hasLength(2));
      final adminRow = rows.firstWhere((r) => r['role'] == 'admin');
      expect(adminRow['cnt'], 2);
    });

    test('HAVING filters groups', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.select(
        db!
            .queryBuilder()
            .from('users')
            .select(['role', db!.raw('AVG(score) AS avg_s')])
            .groupBy('role')
            .havingRaw('AVG(score) > ?', [80])
            .orderBy('role'),
      );
      expect(rows, hasLength(1));
      expect(rows.first['role'], 'admin');
    });
  });

  group('MssqlClient — CTEs and subqueries', () {
    setUp(() async {
      if (skipReason != null) return;
      await db!.execute(db!.queryBuilder().table('users').insert([
        {'id': 1, 'name': 'Alice', 'role': 'admin', 'score': 90.0},
        {'id': 2, 'name': 'Bob',   'role': 'user',  'score': 70.0},
        {'id': 3, 'name': 'Carol', 'role': 'admin', 'score': 85.0},
      ]));
      await db!.execute(db!.queryBuilder().table('orders').insert([
        {'id': 1, 'user_id': 1, 'amount': 99.99, 'status': 'open'},
        {'id': 2, 'user_id': 2, 'amount': 49.99, 'status': 'closed'},
        {'id': 3, 'user_id': 1, 'amount': 29.99, 'status': 'open'},
      ]));
    });

    test('subquery in WHERE IN', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.select(
        db!.queryBuilder()
            .from('users')
            .whereIn('id', (qb) => qb.from('orders').where('status', '=', 'open').select(['user_id']))
            .orderBy('name')
            .select(['name']),
      );
      expect(rows, hasLength(1));
      expect(rows.first['name'], 'Alice');
    });

    test('CTE (WITH clause)', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.select(
        db!
            .queryBuilder()
            .withQuery(
              'top_users',
              db!.queryBuilder().from('users').select(['id', 'name']).where('score', '>', 80),
            )
            .from('top_users')
            .select(['name'])
            .orderBy('name'),
      );
      expect(rows.map((r) => r['name']).toList(), ['Alice', 'Carol']);
    });

    test('EXISTS correlated subquery', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.select(
        db!
            .queryBuilder()
            .from('users as u')
            .select(['u.name'])
            .whereExists((qb) {
              qb
                  .from('orders as o')
                  .select(['o.id'])
                  .whereColumn('o.user_id', '=', 'u.id')
                  .where('o.status', '=', 'open');
            })
            .orderBy('u.name'),
      );
      expect(rows, hasLength(1));
      expect(rows.first['name'], 'Alice');
    });
  });

  group('MssqlClient — nested transaction scenarios extended', () {
    test('outer rollback — both outer and inner changes lost', () async {
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
        throwsException,
      );

      final rows = await db!.select(db!.queryBuilder().from('users'));
      expect(rows, isEmpty);
    });

    test('two sequential savepoints both succeed', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.trx((outer) async {
        await outer.trx((sp1) async {
          await sp1.execute(
            db!.queryBuilder().table('users').insert({'id': 1, 'name': 'SP1'}),
          );
        });
        await outer.trx((sp2) async {
          await sp2.execute(
            db!.queryBuilder().table('users').insert({'id': 2, 'name': 'SP2'}),
          );
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
    test('multiple bindings round-trip', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      await db!.execute(
        db!.queryBuilder().table('users').insert({'id': 42, 'name': 'Multi', 'role': 'user', 'score': 7.7}),
      );
      final rows = await db!.select(
        db!.queryBuilder().from('users').where('id', '=', 42),
      );
      expect(rows, hasLength(1));
      expect(rows.first['name'], 'Multi');
      expect((rows.first['score'] as num).toDouble(), closeTo(7.7, 0.001));
    });

    test('NULL score returns null in Dart', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      await db!.execute(
        db!.queryBuilder().table('users').insert({'id': 1, 'name': 'NullScore'}),
      );
      final rows = await db!.select(
        db!.queryBuilder().from('users').where('id', '=', 1).select(['score']),
      );
      expect(rows.first['score'], isNull);
    });

    test('FLOAT precision round-trips', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      await db!.execute(
        db!.queryBuilder().table('users').insert({'id': 1, 'name': 'Precise', 'score': 3.14159}),
      );
      final rows = await db!.select(
        db!.queryBuilder().from('users').where('id', '=', 1).select(['score']),
      );
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
