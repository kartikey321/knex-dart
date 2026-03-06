import 'package:knex_dart/knex_dart.dart';
import 'package:test/test.dart';

import '../mocks/mock_client.dart';
import '../mocks/sqlite_mock_client.dart';

void main() {
  late Knex db;
  late Knex pgDb;

  setUpAll(() {
    db = Knex(SqliteMockClient());
    pgDb = Knex(MockClient());
  });

  tearDownAll(() async {
    await db.destroy();
    await pgDb.destroy();
  });

  group('JoinClause coverage tests', () {
    test('crossJoin', () {
      final q = db('users').crossJoin('accounts');
      expect(q.toSQL().sql, 'select * from "users" cross join "accounts"');
    });

    test('joinRaw', () {
      final q = db('users').joinRaw('natural full join "accounts"');
      expect(
        q.toSQL().sql,
        'select * from "users" natural full join "accounts"',
      );
    });

    test('onNull, onNotNull, etc', () {
      final q = db('users').leftJoin('accounts', (j) {
        j
            .onNull('accounts.deleted_at')
            .andOnNotNull('accounts.active')
            .orOnNull('accounts.expires_at')
            .orOnNotNull('accounts.blocked_at');
      });
      final sql = q.toSQL().sql;
      expect(sql, contains('"accounts"."deleted_at" is null'));
      expect(sql, contains('and "accounts"."active" is not null'));
      expect(sql, contains('or "accounts"."expires_at" is null'));
      expect(sql, contains('or "accounts"."blocked_at" is not null'));
    });

    test('onIn, onNotIn, etc', () {
      final q = db('users').join('accounts', (j) {
        j
            .onIn('accounts.id', [1, 2])
            .andOnNotIn('accounts.status', ['deleted'])
            .orOnIn('accounts.type', ['admin'])
            .orOnNotIn('accounts.role', ['guest']);
      });
      final sql = q.toSQL().sql;
      expect(sql, contains('"accounts"."id" in (?, ?)'));
      expect(sql, contains('and "accounts"."status" not in (?)'));
      expect(sql, contains('or "accounts"."type" in (?)'));
      expect(sql, contains('or "accounts"."role" not in (?)'));
    });

    test('onBetween, onNotBetween, etc', () {
      final q = db('users').rightJoin('accounts', (j) {
        j
            .onBetween('accounts.score', [10, 20])
            .andOnNotBetween('accounts.age', [0, 18])
            .orOnBetween('accounts.level', [5, 10])
            .orOnNotBetween('accounts.rank', [100, 200]);
      });
      final sql = q.toSQL().sql;
      expect(sql, contains('"accounts"."score" between ? and ?'));
      expect(sql, contains('and "accounts"."age" not between ? and ?'));
      expect(sql, contains('or "accounts"."level" between ? and ?'));
      expect(sql, contains('or "accounts"."rank" not between ? and ?'));

      expect(
        () => db('u').join('a', (j) => j.onBetween('x', [1])),
        throwsArgumentError,
      );
    });

    test('onExists, onNotExists, etc', () {
      final q = db('users').leftJoin('accounts', (j) {
        j
            .onExists(
              (q) => q
                  .select([db.raw('1')])
                  .from('logs')
                  .where(db.raw('logs.u_id = users.id')),
            )
            .andOnNotExists(
              (q) => q
                  .select([db.raw('1')])
                  .from('bans')
                  .where(db.raw('bans.u_id = users.id')),
            )
            .orOnExists(
              (q) => q
                  .select([db.raw('1')])
                  .from('vip')
                  .where(db.raw('vip.u_id = users.id')),
            )
            .orOnNotExists(
              (q) => q
                  .select([db.raw('1')])
                  .from('spam')
                  .where(db.raw('spam.u_id = users.id')),
            );
      });
      final sql = q.toSQL().sql;
      expect(
        sql,
        contains('exists (select 1 from "logs" where logs.u_id = users.id)'),
      );
      expect(
        sql,
        contains(
          'and not exists (select 1 from "bans" where bans.u_id = users.id)',
        ),
      );
      expect(
        sql,
        contains('or exists (select 1 from "vip" where vip.u_id = users.id)'),
      );
      expect(
        sql,
        contains(
          'or not exists (select 1 from "spam" where spam.u_id = users.id)',
        ),
      );
    });

    test('using', () {
      final q = db('users').join('accounts', (j) {
        j.using('user_id');
      });
      expect(
        q.toSQL().sql,
        'select * from "users" inner join "accounts" using ("user_id")',
      );
    });

    test('onJsonPathEquals', () {
      final q = db('users').join('accounts', (j) {
        j
            .onJsonPathEquals(
              'users.meta',
              r'$.id',
              'accounts.meta',
              r'$.user_id',
            )
            .andOnJsonPathEquals('users.data', r'$.x', 'accounts.data', r'$.y')
            .orOnJsonPathEquals('users.info', r'$.a', 'accounts.info', r'$.b');
      });
      final result = q.toSQL();
      expect(
        result.sql,
        contains(
          'json_extract("users"."meta", ?) = json_extract("accounts"."meta", ?)',
        ),
      );
      expect(result.bindings, containsAllInOrder([r'$.id', r'$.user_id']));
    });

    test('onVal variants', () {
      final q = db('users').join('accounts', (j) {
        j
            .onVal('accounts.status', '=', 'active')
            .andOnVal('accounts.type', 'admin')
            .orOnVal('accounts.role', 'moderator')
            .orOnVal({'accounts.deleted': false});
      });
      final sql = q.toSQL().sql;
      expect(sql, contains('"accounts"."status" = ?'));
      expect(sql, contains('and "accounts"."type" = ?'));
      expect(sql, contains('or "accounts"."role" = ?'));
      expect(sql, contains('or "accounts"."deleted" = ?'));
    });

    test('on mapping', () {
      final q = db('users').join('accounts', (j) {
        j.on({'accounts.user_id': 'users.id'}).orOn({
          'accounts.org_id': 'users.org_id',
        });
      });
      final sql = q.toSQL().sql;
      expect(sql, contains('"accounts"."user_id" = "users"."id"'));
      expect(sql, contains('or "accounts"."org_id" = "users"."org_id"'));
    });

    test('on in with empty list compiles to 1 = 0', () {
      final q = db('users').join('accounts', (j) => j.onIn('id', []));
      expect(q.toSQL().sql, contains('1 = 0'));
    });
  });

  // ─── Lateral joins ─────────────────────────────────────────────────────────

  group('LATERAL joins', () {
    test(
      'joinLateral with callback subquery emits join lateral ... on true',
      () {
        final q = pgDb('users').joinLateral('latest_order', (sub) {
          sub.table('orders').where('orders.user_id', 1).limit(1);
        });
        final compiled = q.toSQL();
        expect(compiled.sql, contains('join lateral ('));
        expect(compiled.sql, contains(') as "latest_order" on true'));
        expect(compiled.sql, contains('"orders"'));
        expect(compiled.bindings, containsAll([1, 1])); // where value + limit
      },
    );

    test('leftJoinLateral emits left join lateral ... on true', () {
      final q = pgDb('users').leftJoinLateral('recent_event', (sub) {
        sub.table('events').where('events.user_id', 99).limit(5);
      });
      final compiled = q.toSQL();
      expect(compiled.sql, contains('left join lateral ('));
      expect(compiled.sql, contains(') as "recent_event" on true'));
      expect(compiled.bindings, containsAll([99, 5]));
    });

    test('crossJoinLateral emits cross join lateral without ON clause', () {
      final q = pgDb('users').crossJoinLateral('stats', (sub) {
        sub.table('metrics').where('user_id', 7);
      });
      final sql = q.toSQL().sql;
      expect(sql, contains('cross join lateral ('));
      expect(sql, contains(') as "stats"'));
      expect(sql, isNot(contains('on true')));
    });

    test('joinLateral with pre-built QueryBuilder', () {
      final sub = pgDb().table('orders').where('active', true).limit(1);
      final q = pgDb('users').joinLateral('first_order', sub);
      final compiled = q.toSQL();
      expect(compiled.sql, contains('join lateral ('));
      expect(compiled.sql, contains('"orders"'));
      expect(compiled.sql, contains(') as "first_order" on true'));
      expect(compiled.bindings, containsAll([true, 1]));
    });

    test('joinLateral with Raw subquery', () {
      final q = pgDb('users').joinLateral(
        'top_score',
        pgDb.raw(
          'select max(score) as score from scores where user_id = users.id',
        ),
      );
      final sql = q.toSQL().sql;
      expect(sql, contains('join lateral ('));
      expect(sql, contains('max(score)'));
      expect(sql, contains(') as "top_score" on true'));
    });

    test(
      'bindings from lateral subquery are collected alongside outer bindings',
      () {
        final q = pgDb('users').where('active', true).joinLateral('latest', (
          sub,
        ) {
          sub.table('orders').where('user_id', 999).limit(3);
        });
        final compiled = q.toSQL();
        // Joins are compiled before WHERE, so lateral bindings (999, 3) come
        // first in the collected list; the outer WHERE binding (true) follows.
        expect(compiled.bindings, equals([999, 3, true]));
      },
    );

    test('lateral join full SQL structure', () {
      final q = pgDb('users')
          .select(['users.id', 'users.name', 'lo.total'])
          .leftJoinLateral('lo', (sub) {
            sub
                .table('orders')
                .where('orders.user_id', 42)
                .sum('amount as total');
          })
          .where('users.active', true);
      final compiled = q.toSQL();
      expect(compiled.sql, startsWith('select'));
      expect(compiled.sql, contains('left join lateral ('));
      expect(compiled.sql, contains(') as "lo" on true'));
      expect(compiled.sql, contains('where "users"."active" ='));
    });
  });

  group('Dialect guards', () {
    test('fullOuterJoin throws on SQLite dialect', () {
      expect(
        () => db(
          'users',
        ).fullOuterJoin('accounts', 'users.id', 'accounts.user_id').toSQL(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('FULL OUTER JOIN is not supported'),
          ),
        ),
      );
    });

    test('joinLateral throws on SQLite dialect', () {
      expect(
        () => db('users').joinLateral('latest', (sub) {
          sub.table('orders').limit(1);
        }).toSQL(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('LATERAL JOIN is not supported'),
          ),
        ),
      );
    });
  });
}
