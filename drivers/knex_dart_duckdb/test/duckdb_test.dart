import 'package:knex_dart_duckdb/knex_dart_duckdb.dart';
import 'package:test/test.dart';

/// Try to open DuckDB — returns null if the native library is not available.
Future<KnexDuckDB?> _tryOpen() async {
  try {
    return await KnexDuckDB.memory();
  } catch (e) {
    final msg = e.toString();
    if (msg.contains('Unsupported platform') ||
        msg.contains('Failed to load dynamic library') ||
        msg.contains('Cannot open shared object file') ||
        msg.contains('dlopen')) {
      return null;
    }
    rethrow;
  }
}

/// DuckDB integration tests — run against a real in-memory DuckDB instance.
/// Requires DuckDB to be installed system-wide:
///   macOS:  brew install duckdb
///   Linux:  see https://duckdb.org/docs/installation
void main() {
  KnexDuckDB? db;
  String? skipReason;

  setUpAll(() async {
    final candidate = await _tryOpen();
    if (candidate == null) {
      skipReason =
          'DuckDB native library not found — install via `brew install duckdb`';
      await candidate?.close();
    } else {
      await candidate.close(); // just a probe; real db opened per test
    }
  });

  setUp(() async {
    if (skipReason != null) return;

    db = await KnexDuckDB.memory();

    await db!.executeSchema((schema) {
      schema.createTable('users', (t) {
        t.integer('id').primary();
        t.string('name').notNullable();
        t.string('role').nullable().defaultTo('user');
        t.doublePrecision('score').nullable();
        t.boolean('active').defaultTo(true);
      });
      schema.createTable('orders', (t) {
        t.integer('id').primary();
        t.integer('user_id').nullable();
        t.doublePrecision('amount').nullable();
        t.string('status').nullable();
      });
    });
  });

  tearDown(() async {
    if (db != null) {
      await db!.close();
      db = null;
    }
  });

  group('DuckDB — basic CRUD', () {
    test('insert and select', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      final qb = db!.queryBuilder();
      await db!.execute(
        qb.table('users').insert({'id': 1, 'name': 'Alice', 'score': 9.5}),
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
        db!.queryBuilder().table('users').where('id', '=', 1).update({
          'score': 8.0,
        }),
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

  group('DuckDB — null / type handling', () {
    test('null value round-trips correctly', () async {
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

    test('boolean values round-trip', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.execute(
        db!.queryBuilder().table('users').insert({
          'id': 1,
          'name': 'Eve',
          'active': true,
        }),
      );
      final rows = await db!.select(db!.queryBuilder().from('users'));
      expect(rows.first['active'], isTrue);
    });
  });

  group('DuckDB — transactions', () {
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
            db!.queryBuilder().table('users').insert({
              'id': 1,
              'name': 'Ghost',
            }),
          );
          throw Exception('force rollback');
        }),
        throwsException,
      );
      final rows = await db!.select(db!.queryBuilder().from('users'));
      expect(rows, isEmpty);
    });

    test('nested trx — inner saves, outer rolls back → both gone', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await expectLater(
        db!.trx((outer) async {
          await outer.execute(
            db!.queryBuilder().table('users').insert({
              'id': 1,
              'name': 'Outer',
            }),
          );
          await outer.trx((inner) async {
            await inner.execute(
              db!.queryBuilder().table('users').insert({
                'id': 2,
                'name': 'Inner',
              }),
            );
          });
          throw Exception('outer fails');
        }),
        throwsException,
      );
      final rows = await db!.select(db!.queryBuilder().from('users'));
      expect(rows, isEmpty);
    });

    test('nested trx — inner rolls back, outer catches and commits', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.trx((outer) async {
        await outer.execute(
          db!.queryBuilder().table('users').insert({'id': 1, 'name': 'Outer'}),
        );
        try {
          await outer.trx((inner) async {
            await inner.execute(
              db!.queryBuilder().table('users').insert({
                'id': 2,
                'name': 'Inner',
              }),
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

  group('DuckDB — analytical SQL', () {
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

    test('GROUP BY + aggregate', () async {
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
               RANK() OVER (ORDER BY score DESC) as rnk
        FROM users
        ORDER BY rnk
      ''');
      expect(rows.first['name'], 'Alice');
      expect(rows.first['rnk'], 1);
    });

    test('CTE query', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      final rows = await db!.raw('''
        WITH top_users AS (
          SELECT * FROM users WHERE score > 80
        )
        SELECT name FROM top_users ORDER BY name
      ''');
      expect(rows.map((r) => r['name']).toList(), ['Alice', 'Carol']);
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

  group('DuckDB — executeSchema', () {
    test('creates a table via SchemaBuilder', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.executeSchema((s) {
        s.createTable('products', (t) {
          t.integer('id').primary();
          t.string('sku').notNullable();
          t.doublePrecision('price');
        });
      });

      await db!.execute(
        db!.queryBuilder().table('products').insert({
          'id': 1,
          'sku': 'ABC',
          'price': 9.99,
        }),
      );
      final rows = await db!.select(db!.queryBuilder().from('products'));
      expect(rows, hasLength(1));
      expect(rows.first['sku'], 'ABC');
    });
  });

  // ════════════════════════════════════════════════════════════════════════════
  // New detailed test groups
  // ════════════════════════════════════════════════════════════════════════════

  group('DuckDB — filtering with QueryBuilder', () {
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

    test('whereNotNull excludes NULL rows', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.select(
        db!.queryBuilder().from('users').whereNotNull('score'),
      );
      expect(rows, hasLength(3));
    });

    test('orWhere matches either condition', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.select(
        db!
            .queryBuilder()
            .from('users')
            .where('name', 'Alice')
            .orWhere('name', 'Bob'),
      );
      expect(rows, hasLength(2));
    });

    test('where with > operator', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.select(
        db!.queryBuilder().from('users').where('score', '>', 80),
      );
      expect(rows, hasLength(2)); // Alice(90), Carol(85)
    });

    test('offset + limit paginates', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final page = await db!.select(
        db!.queryBuilder().from('users').orderBy('id').limit(2).offset(1),
      );
      expect(page, hasLength(2));
      expect(page.first['id'], 2); // skipped id=1
    });
  });

  group('DuckDB — UNION / INTERSECT / EXCEPT', () {
    test('UNION ALL combines result sets', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.raw(
        'SELECT 1 AS n UNION ALL SELECT 2 AS n UNION ALL SELECT 3 AS n ORDER BY n',
      );
      expect(rows.map((r) => r['n']).toList(), [1, 2, 3]);
    });

    test('INTERSECT returns common rows', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      await db!.raw('''
        INSERT INTO users (id, name, role, score) VALUES
          (1, 'Alice', 'admin', 90), (2, 'Bob', 'user', 70)
      ''');
      final rows = await db!.raw('''
        SELECT id FROM users WHERE score > 80
        INTERSECT
        SELECT id FROM users WHERE role = 'admin'
      ''');
      expect(rows, hasLength(1));
      expect(rows.first['id'], 1);
    });

    test('EXCEPT removes overlapping rows', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      await db!.raw('''
        INSERT INTO users (id, name, role, score) VALUES
          (1, 'Alice', 'admin', 90), (2, 'Bob', 'user', 70), (3, 'Carol', 'admin', 85)
      ''');
      final rows = await db!.raw('''
        SELECT id FROM users WHERE role = 'admin'
        EXCEPT
        SELECT id FROM users WHERE score > 88
      ''');
      expect(rows, hasLength(1));
      expect(rows.first['id'], 3); // Carol is admin but score<=88
    });
  });

  group('DuckDB — advanced window functions', () {
    setUp(() async {
      if (skipReason != null) return;
      await db!.raw('''
        INSERT INTO users (id, name, role, score) VALUES
          (1, 'Alice', 'admin', 90),
          (2, 'Bob',   'user',  70),
          (3, 'Carol', 'admin', 85),
          (4, 'Dave',  'user',  70)
      ''');
    });

    test('DENSE_RANK handles ties', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.raw('''
        SELECT name, DENSE_RANK() OVER (ORDER BY score DESC) AS rnk
        FROM users ORDER BY score DESC, name
      ''');
      final bobRow = rows.firstWhere((r) => r['name'] == 'Bob');
      final daveRow = rows.firstWhere((r) => r['name'] == 'Dave');
      expect(bobRow['rnk'], daveRow['rnk']); // tie → same rank
    });

    test('LEAD accesses next row value', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.raw('''
        SELECT name, score,
               LEAD(score) OVER (ORDER BY score DESC) AS next_score
        FROM users ORDER BY score DESC
      ''');
      expect(rows.first['name'], 'Alice');
      expect(rows.first['next_score'], closeTo(85, 0.01)); // Carol's score
    });

    test('LAG accesses previous row value', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.raw('''
        SELECT name, LAG(score) OVER (ORDER BY score DESC) AS prev_score
        FROM users ORDER BY score DESC
      ''');
      expect(rows.first['prev_score'], isNull); // no previous for top row
      expect(rows[1]['prev_score'], closeTo(90, 0.01)); // Alice's score
    });

    test('PARTITION BY in window function', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.raw('''
        SELECT name, role,
               RANK() OVER (PARTITION BY role ORDER BY score DESC) AS role_rank
        FROM users ORDER BY role, role_rank
      ''');
      final adminRows = rows.where((r) => r['role'] == 'admin').toList();
      expect(adminRows.first['role_rank'], 1);
    });

    test(
      'running SUM with ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW',
      () async {
        if (skipReason != null) return markTestSkipped(skipReason!);
        final rows = await db!.raw('''
        SELECT name, score,
               SUM(score) OVER (ORDER BY id
                 ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total
        FROM users ORDER BY id
      ''');
        expect(rows.first['running_total'], closeTo(90, 0.01));
        expect(rows[1]['running_total'], closeTo(160, 0.01)); // 90+70
      },
    );
  });

  group('DuckDB — LATERAL join', () {
    test('LATERAL join expands per-row subquery', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      await db!.raw('''
        INSERT INTO users (id, name, score) VALUES (1, 'Alice', 90), (2, 'Bob', 70)
      ''');
      await db!.raw('''
        INSERT INTO orders (id, user_id, amount, status) VALUES
          (1, 1, 99.99, 'open'), (2, 1, 49.99, 'closed'), (3, 2, 29.99, 'open')
      ''');

      final rows = await db!.raw('''
        SELECT u.name, latest.amount
        FROM users u
        JOIN LATERAL (
          SELECT amount FROM orders WHERE user_id = u.id ORDER BY id DESC LIMIT 1
        ) AS latest ON true
        ORDER BY u.id
      ''');
      expect(rows, hasLength(2));
      expect(rows.first['name'], 'Alice');
      expect(rows.first['amount'], closeTo(49.99, 0.01)); // most recent order
    });
  });

  group('DuckDB — type edge cases', () {
    test('integer arithmetic result', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.raw('SELECT 10 * 20 AS product');
      expect(rows.first['product'], 200);
    });

    test('string concatenation via ||', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.raw(
        "SELECT 'hello' || ' ' || 'world' AS greeting",
      );
      expect(rows.first['greeting'], 'hello world');
    });

    test('CURRENT_DATE returns a non-null value', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final rows = await db!.raw('SELECT CURRENT_DATE AS today');
      expect(rows.first['today'], isNotNull);
    });
  });

  group('DuckDB — schema builder extended', () {
    test('dropTable removes the table', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      await db!.executeSchema((s) {
        s.createTable('temp_tbl', (t) {
          t.integer('id').primary();
          t.string('val');
        });
      });
      await db!.raw("INSERT INTO temp_tbl VALUES (1, 'x')");
      final before = await db!.raw('SELECT * FROM temp_tbl');
      expect(before, hasLength(1));

      await db!.executeSchema((s) => s.dropTable('temp_tbl'));
      expect(() => db!.raw('SELECT * FROM temp_tbl'), throwsA(anything));
    });

    test('createTable with multiple column types', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      await db!.executeSchema((s) {
        s.createTable('catalog', (t) {
          t.integer('id').primary();
          t.string('name').notNullable();
          t.text('description').nullable();
          t.doublePrecision('price').defaultTo(0.0);
          t.boolean('available').defaultTo(true);
        });
      });
      await db!.raw(
        "INSERT INTO catalog (id, name, price) VALUES (1, 'Widget', 9.99)",
      );
      final rows = await db!.raw('SELECT * FROM catalog');
      expect(rows, hasLength(1));
      expect(rows.first['name'], 'Widget');
      expect(rows.first['available'], isTrue);
    });
  });

  group('DuckDB — QueryBuilder SQL compilation', () {
    test('INSERT via QueryBuilder', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      await db!.execute(
        db!.queryBuilder().table('users').insert({
          'id': 99,
          'name': 'Zelda',
          'role': 'admin',
          'score': 100.0,
        }),
      );
      final rows = await db!.select(
        db!.queryBuilder().from('users').where('id', '=', 99),
      );
      expect(rows, hasLength(1));
      expect(rows.first['name'], 'Zelda');
    });

    test('UPDATE via QueryBuilder', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      await db!.execute(
        db!.queryBuilder().table('users').insert({
          'id': 1,
          'name': 'Original',
          'score': 50.0,
        }),
      );
      await db!.execute(
        db!.queryBuilder().table('users').where('id', '=', 1).update({
          'score': 99.0,
        }),
      );
      final rows = await db!.select(
        db!.queryBuilder().from('users').where('id', '=', 1),
      );
      expect(rows.first['score'], closeTo(99.0, 0.001));
    });

    test('DELETE via QueryBuilder removes correct row', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      await db!.execute(
        db!.queryBuilder().table('users').insert([
          {'id': 1, 'name': 'Keep'},
          {'id': 2, 'name': 'Remove'},
        ]),
      );
      await db!.execute(
        db!.queryBuilder().table('users').where('name', 'Remove').delete(),
      );
      final rows = await db!.select(db!.queryBuilder().from('users'));
      expect(rows, hasLength(1));
      expect(rows.first['name'], 'Keep');
    });

    test('SELECT with expression alias via raw', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);
      await db!.raw('INSERT INTO users (id, name, score) VALUES (1, ?, ?)', [
        'Alice',
        90.0,
      ]);
      final rows = await db!.raw(
        'SELECT name AS full_name, score * 2 AS doubled FROM users WHERE id = ?',
        [1],
      );
      expect(rows.first['full_name'], 'Alice');
      expect(rows.first['doubled'], closeTo(180.0, 0.01));
    });
  });

  group('DuckDB QueryBuilder — joins', () {
    test('inner join between in-memory tables', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.execute(
        db!.queryBuilder().table('users').insert([
          {'id': 1, 'name': 'Alice'},
          {'id': 2, 'name': 'Bob'},
        ]),
      );
      await db!.execute(
        db!.queryBuilder().table('orders').insert({
          'id': 1,
          'user_id': 1,
          'amount': 99.99,
          'status': 'open',
        }),
      );

      final rows = await db!.select(
        db!
            .queryBuilder()
            .from('users')
            .join('orders', 'users.id', 'orders.user_id')
            .select(['users.name', 'orders.amount'])
            .orderBy('users.id'),
      );

      expect(rows, hasLength(1));
      expect(rows.first['name'], 'Alice');
      expect(rows.first['amount'], closeTo(99.99, 0.01));
    });

    test('left join between in-memory tables', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.execute(
        db!.queryBuilder().table('users').insert([
          {'id': 1, 'name': 'Alice'},
          {'id': 2, 'name': 'Bob'},
        ]),
      );
      await db!.execute(
        db!.queryBuilder().table('orders').insert({
          'id': 1,
          'user_id': 1,
          'amount': 50.00,
          'status': 'open',
        }),
      );

      final rows = await db!.select(
        db!
            .queryBuilder()
            .from('users')
            .leftJoin('orders', 'users.id', 'orders.user_id')
            .select(['users.id', 'users.name', 'orders.amount'])
            .orderBy('users.id'),
      );

      expect(rows, hasLength(2));
      expect(rows.first['name'], 'Alice');
      expect(rows.last['name'], 'Bob');
      expect(rows.last['amount'], isNull);
    });
  });

  group('DuckDB QueryBuilder — groupBy and having', () {
    test('groupBy + havingRaw filters grouped rows', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.execute(
        db!.queryBuilder().table('users').insert([
          {'id': 1, 'name': 'Alice', 'role': 'admin'},
          {'id': 2, 'name': 'Bob', 'role': 'user'},
          {'id': 3, 'name': 'Carol', 'role': 'admin'},
        ]),
      );

      final rows = await db!.select(
        db!
            .queryBuilder()
            .from('users')
            .select(['role'])
            .groupBy('role')
            .havingRaw('count(*) > ?', [1])
            .orderBy('role'),
      );

      expect(rows, hasLength(1));
      expect(rows.first['role'], 'admin');
    });
  });

  group('DuckDB QueryBuilder — distinct', () {
    test('distinct() returns unique role values', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.execute(
        db!.queryBuilder().table('users').insert([
          {'id': 1, 'name': 'Alice', 'role': 'admin'},
          {'id': 2, 'name': 'Bob', 'role': 'admin'},
          {'id': 3, 'name': 'Carol', 'role': 'user'},
        ]),
      );

      final rows = await db!.select(
        db!.queryBuilder().from('users').distinct(['role']).orderBy('role'),
      );

      expect(rows, hasLength(2));
      expect(rows.map((r) => r['role']).toList(), ['admin', 'user']);
    });
  });

  group('DuckDB QueryBuilder — whereBetween and whereNotIn', () {
    test('whereBetween filters by score range', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.execute(
        db!.queryBuilder().table('users').insert([
          {'id': 1, 'name': 'Alice', 'score': 60},
          {'id': 2, 'name': 'Bob', 'score': 70},
          {'id': 3, 'name': 'Carol', 'score': 85},
          {'id': 4, 'name': 'Dave', 'score': 95},
        ]),
      );

      final rows = await db!.select(
        db!
            .queryBuilder()
            .from('users')
            .whereBetween('score', [70, 90])
            .orderBy('id'),
      );

      expect(rows, hasLength(2));
      expect(rows.map((r) => r['name']).toList(), ['Bob', 'Carol']);
    });

    test('whereNotIn excludes selected names', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.execute(
        db!.queryBuilder().table('users').insert([
          {'id': 1, 'name': 'Alice'},
          {'id': 2, 'name': 'Bob'},
          {'id': 3, 'name': 'Carol'},
        ]),
      );

      final rows = await db!.select(
        db!
            .queryBuilder()
            .from('users')
            .whereNotIn('name', ['Bob'])
            .orderBy('id'),
      );

      expect(rows, hasLength(2));
      expect(rows.map((r) => r['name']).toList(), ['Alice', 'Carol']);
    });
  });

  group('DuckDB SchemaBuilder — alterTable addColumn and dropColumn', () {
    test('addColumn then dropColumn updates table schema', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      const table = 'duckdb_schema_alter_local';

      await db!.executeSchema((s) {
        s.createTable(table, (t) {
          t.integer('id').primary();
        });
      });

      try {
        await db!.executeSchema((s) {
          s.alterTable(table, (t) {
            t.string('nickname').nullable();
          });
        });

        final afterAdd = await db!.raw("PRAGMA table_info('$table')");
        expect(afterAdd.any((row) => row['name'] == 'nickname'), isTrue);

        await db!.executeSchema((s) {
          s.alterTable(table, (t) {
            t.dropColumn('nickname');
          });
        });

        final afterDrop = await db!.raw("PRAGMA table_info('$table')");
        expect(afterDrop.any((row) => row['name'] == 'nickname'), isFalse);
      } finally {
        await db!.executeSchema((s) {
          s.dropTableIfExists(table);
        });
      }
    });
  });

  group(
    'DuckDB SchemaBuilder — createTableIfNotExists and dropTableIfExists',
    () {
      test('idempotent create/drop operations succeed', () async {
        if (skipReason != null) return markTestSkipped(skipReason!);

        const table = 'duckdb_schema_if_exists_local';

        await db!.executeSchema((s) {
          s.createTableIfNotExists(table, (t) {
            t.integer('id').primary();
            t.string('label');
          });
        });
        await db!.executeSchema((s) {
          s.createTableIfNotExists(table, (t) {
            t.integer('id').primary();
            t.string('label');
          });
        });

        await db!.raw("INSERT INTO $table (id, label) VALUES (1, 'ok')");
        final rows = await db!.raw('SELECT * FROM $table');
        expect(rows, hasLength(1));

        await db!.executeSchema((s) {
          s.dropTableIfExists(table);
        });
        await db!.executeSchema((s) {
          s.dropTableIfExists(table);
        });

        expect(() => db!.raw('SELECT * FROM $table'), throwsA(anything));
      });
    },
  );
}
