@Tags(['mssql'])
library;

import 'package:universal_io/io.dart';
import 'package:knex_dart_mssql/knex_dart_mssql.dart';
// For MssqlException, which carries the server's own error number. The driver
// barrel does not re-export it, so the negative OFFSET test reaches for it here.
import 'package:mssql/mssql.dart' show MssqlException;
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
    // Surface the real cause (e.g. TLS certificate rejection) instead of a
    // generic "not reachable" that would otherwise mask it — see
    // https://github.com/kartikey321/knex-dart/pull/29 for the exact
    // failure this masked (a self-signed-certificate rejection reported as
    // "not reachable").
    print('MSSQL connect failed: $e');
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

    test('a union with .limit() and no .orderBy() runs on the server',
        () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      // T-SQL defines OFFSET/FETCH as a tail of the ORDER BY clause, so the
      // compiler supplies an inert sort when a bounded set operation carries
      // no sort of its own. That sort is the ordinal `order by 1`, not the
      // usual `(select null)`: a set operation additionally requires every
      // ORDER BY item to appear in the select list, and SQL Server rejects
      // the expression form with error 104. An ordinal names an output column
      // by position, so it satisfies both rules even for `select *`.
      //
      // Asserted against a real server rather than against a reading of the
      // grammar: without the inert sort this statement would be a syntax
      // error, so this test is what proves the emitted form actually runs.
      // Each operand is filtered to a different fixture row, so a compiler
      // that dropped an operand — or bound `top (n)`/`fetch next n` to one
      // branch instead of the combined result — would change the row set
      // rather than still returning two rows. Both regressions have actually
      // happened in this file's history, which is why the assertion names
      // the rows instead of counting them.
      //
      // The order is deterministic despite no .orderBy(): the inert sort the
      // compiler supplies is `order by 1`, i.e. ascending by the only output
      // column, so A precedes B.
      final other =
          db!.queryBuilder().from('users').where('name', '=', 'A').select(['name']);
      final rows = await db!.select(
        db!
            .queryBuilder()
            .from('users')
            .where('name', '=', 'B')
            .select(['name'])
            .union([other])
            .limit(2),
      );
      expect(rows.map((r) => r['name']), ['A', 'B']);
    });

    test('the server rejects raw OFFSET/FETCH with no ORDER BY', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      // Pins a property of T-SQL itself, so it goes through raw SQL rather
      // than the builder. It used to run through the builder, which made it
      // depend on the compiler emitting the broken form — and the compiler no
      // longer does (it supplies `order by 1`), so that version would now be
      // testing nothing. Raw SQL keeps the server as the subject.
      //
      // Differential, so the ORDER BY is the only variable: the control is the
      // identical statement WITH a sort and must succeed. That is what rules
      // out a dropped connection or a missing `users` table being mistaken for
      // the grammar verdict.
      final control = await db!.rawSql(
        'select name from users order by name offset 1 rows fetch next 2 rows only',
      );
      // Fixture is A..E, so skipping one and taking two is exactly B, C.
      expect(
        control.map((r) => r['name']),
        ['B', 'C'],
        reason: 'control (same statement, WITH order by) must succeed — '
            'otherwise the negative case proves nothing about ORDER BY',
      );

      // Logged so the exact error number can be pinned from an observed run
      // rather than guessed. SQL Server documents 153 for `FETCH` without
      // `OFFSET`, which is a different statement; the number for this shape is
      // unconfirmed, and asserting a guessed constant in the one test whose
      // job is to record what the server really does would defeat the test.
      try {
        await db!.rawSql(
          'select name from users offset 1 rows fetch next 2 rows only',
        );
      } on MssqlException catch (e) {
        print('OFFSET-without-ORDER-BY verdict: code=${e.errorCode} '
            'severity=${e.severity} message=${e.message}');
      }

      // `errorCode` is the server's own number, parsed off the TDS ERROR
      // token. Every client-side throw site in package:mssql leaves it at its
      // default 0 (pool closed, acquire timeout, TLS refusal), so requiring it
      // to be non-zero separates "the server parsed this and rejected it" from
      // "we never had a usable connection". `throwsA` rejects any other
      // exception type outright.
      await expectLater(
        db!.rawSql(
          'select name from users offset 1 rows fetch next 2 rows only',
        ),
        throwsA(
          isA<MssqlException>().having(
            (e) => e.errorCode,
            'errorCode',
            isNot(0),
          ),
        ),
        reason:
            'SQL Server ACCEPTED OFFSET/FETCH without an ORDER BY. The inert '
            'sort the compiler adds is then unnecessary, and '
            '`select/limit-offset::mssql` can go back to matching knex.js — '
            'invert this expectation and update the parity ledger note.',
      );
    });

    test('.offset().limit() with no .orderBy() runs — the inert sort works',
        () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      // The other half of the test above. knex.js emits this shape without a
      // sort and SQL Server refuses it; knex-dart prefixes `order by 1`, which
      // is why `select/limit-offset::mssql` is an ACCEPTED divergence. This is
      // what proves the divergence actually buys a runnable statement — the
      // parity ledger's claim is only as good as this assertion.
      final rows = await db!.select(
        db!.queryBuilder().from('users').select(['name']).offset(1).limit(2),
      );

      // `order by 1` sorts ascending by the only output column, so skipping
      // one of A..E and taking two is deterministically B, C.
      expect(rows.map((r) => r['name']), ['B', 'C']);
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
    test('queryBuilder generates bracket identifiers', () {
      if (skipReason != null) return markTestSkipped(skipReason!);
      final compiled = db!
          .queryBuilder()
          .from('users')
          .where('role', 'admin')
          .select(['name', 'score'])
          .toSQL();
      expect(compiled.sql, contains('[users]'));
      expect(compiled.sql, contains('[name]'));
      // mssql compiles numbered `@p0`/`@p1`/… placeholders, not `?` — see
      // the knex_dart CHANGELOG 1.3.4 entry.
      expect(compiled.sql, contains('@p0'));
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
