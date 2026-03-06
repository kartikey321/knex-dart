import 'package:knex_dart/knex_dart.dart';
import 'package:knex_dart_mysql/knex_dart_mysql.dart';
import 'package:knex_dart_postgres/knex_dart_postgres.dart';
import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';

// ── Dialect capability rules ─────────────────────────────────────────────────

Future<void> mysqlWarnings() async {
  final db = await KnexMySQL.connect(
    host: 'localhost',
    database: 'demo',
    user: 'root',
    password: 'root',
  );

  // expect: dialect_unsupported_returning
  db.queryBuilder().table('users').insert({'name': 'A'}).returning(['id']);

  // expect: dialect_unsupported_full_outer_join
  db
      .queryBuilder()
      .table('users')
      .fullOuterJoin('orders', 'users.id', 'orders.user_id');

  // expect: dialect_unsupported_intersect_except
  db.queryBuilder().table('users').select(['id', 'email']).intersect([
    db.queryBuilder().table('admins').select(['id', 'email']),
  ]);

  // expect: dialect_unsupported_intersect_except
  db.queryBuilder().table('orders').select(['user_id']).except([
    db.queryBuilder().table('banned_users').select(['id']),
  ]);
}

Future<void> sqliteWarnings() async {
  final db = await KnexSQLite.connect(filename: ':memory:');

  // expect: dialect_unsupported_lateral_join
  db.queryBuilder().table('users').joinLateral('latest', (sub) {
    sub.table('orders').limit(1);
  });

  // expect: dialect_unsupported_json
  db.queryBuilder().table('users').whereJsonSupersetOf('meta', {
    'role': 'admin',
  });

  // expect: dialect_unsupported_json
  db
      .queryBuilder()
      .table('events')
      .whereJsonPath('payload', r'$.type', '=', 'click');
}

// ── Literal value rules ───────────────────────────────────────────────────────

Future<void> badOperatorWarnings() async {
  final db = await KnexMySQL.connect(
    host: 'localhost',
    database: 'demo',
    user: 'root',
    password: 'root',
  );

  // expect: invalid_where_operator  ('==' is JS equality, not SQL)
  db.queryBuilder().table('users').where('age', '==', 18);

  // expect: invalid_where_operator  ('!==' is not a SQL operator)
  db.queryBuilder().table('orders').orWhere('status', '!==', 'cancelled');

  // expect: where_null_value  (produces WHERE deleted_at = NULL — always false)
  db.queryBuilder().table('users').where('deleted_at', null);

  // expect: where_null_value  (3-arg form is equally wrong)
  db.queryBuilder().table('posts').where('archived_at', '=', null);

  // expect: invalid_order_direction  (uppercase — knex_dart requires lowercase)
  db.queryBuilder().table('users').orderBy('name', 'ASC');

  // expect: invalid_order_direction  (misspelled direction)
  db.queryBuilder().table('events').orderBy('created_at', 'descending');
}

// ── Type-inference rules ──────────────────────────────────────────────────────

Future<void> typeInferenceWarnings() async {
  final db = await KnexSQLite.connect(filename: ':memory:');

  // expect: insert_wrong_value_type  (insert() expects Map or List<Map>)
  final badPayload = 'name=Alice';
  db.queryBuilder().table('users').insert(badPayload);

  // expect: insert_wrong_value_type  (int is not a valid insert value)
  final rowCount = 42;
  db.queryBuilder().table('logs').insert(rowCount);

  // expect: where_null_typed_value  (Null-typed var → whereNull() instead)
  Null nothing = null;
  db.queryBuilder().table('users').where('deleted_at', nothing);

  // expect: where_null_typed_value  (3-arg form with Null-typed var)
  db.queryBuilder().table('sessions').where('revoked_at', '=', nothing);
}

// ── No warnings — correct usage ───────────────────────────────────────────────

Future<void> supportedNoWarnings() async {
  final pg = await KnexPostgres.connect(
    host: 'localhost',
    database: 'demo',
    username: 'postgres',
    password: 'postgres',
  );

  // postgres supports all of these — no dialect warnings.
  pg.queryBuilder().table('users').insert({'name': 'A'}).returning(['id']);
  pg
      .queryBuilder()
      .table('users')
      .fullOuterJoin('orders', 'users.id', 'orders.user_id');
  pg.queryBuilder().table('users').joinLateral('latest', (QueryBuilder sub) {
    sub.table('orders').limit(1);
  });
  pg.queryBuilder().table('users').whereJsonSupersetOf('meta', {
    'role': 'admin',
  });
  pg.queryBuilder().table('users').select(['id']).intersect([
    pg.queryBuilder().table('admins').select(['id']),
  ]);

  // Correct operators, directions, and null checks — no literal/type warnings.
  pg.queryBuilder().table('users').where('age', '=', 18);
  pg.queryBuilder().table('users').where('name', 'like', 'Alice%');
  pg.queryBuilder().table('users').where('status', '<>', 'banned');
  pg.queryBuilder().table('users').orderBy('name', 'asc');
  pg.queryBuilder().table('users').orderBy('created_at', 'desc');
  pg.queryBuilder().table('users').whereNull('deleted_at');
  pg.queryBuilder().table('users').whereNotNull('email');
  pg.queryBuilder().table('users').insert({
    'name': 'Bob',
    'email': 'bob@example.com',
  });
}

Future<void> unknownNoWarnings(dynamic factory) async {
  final db = await factory();

  // unknown root dialect => no dialect lint by design.
  db.queryBuilder().table('users').returning(['id']);
}
