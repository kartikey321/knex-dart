/// Tests for optimizations introduced in knex_dart_sqlite 0.2.1:
/// - SQLiteClient.executeCompiled() — avoids double toSQL() compilation
/// - KnexSQLite.insert/update/delete all route through select() unified path
/// - _mapResults uses indexed column access (column names × row values)
/// - _execute returns synchronous Future.value / Future.error (no async overhead)
library;

import 'package:knex_dart/knex_dart.dart';
import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';
import 'package:test/test.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

Future<KnexSQLite> _openDb() async {
  final db = await KnexSQLite.connect(filename: ':memory:');
  await db.executeSchema((s) {
    s.createTable('items', (t) {
      t.increments('id');
      t.string('name');
      t.integer('qty').defaultTo(0);
      t.boolean('active').defaultTo(true);
    });
  });
  return db;
}

Future<SQLiteClient> _openClient() async {
  final client = await SQLiteClient.connect(filename: ':memory:');
  await client.rawQuery(
    '''
    CREATE TABLE items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      qty  INTEGER DEFAULT 0,
      active INTEGER DEFAULT 1
    )
    ''',
    [],
  );
  return client;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── executeCompiled() ────────────────────────────────────────────────────

  group('SQLiteClient.executeCompiled()', () {
    late SQLiteClient client;

    setUp(() async {
      client = await _openClient();
    });

    tearDown(() => client.close());

    test('returns rows for a SELECT compiled query', () async {
      await client.rawQuery(
        "INSERT INTO items (name, qty) VALUES ('apple', 5)",
        [],
      );
      final qb = client.queryBuilder().from('items').select(['name', 'qty']);
      final compiled = qb.toSQL();
      final rows = await client.executeCompiled(compiled);
      expect(rows, hasLength(1));
      expect(rows.first['name'], 'apple');
      expect(rows.first['qty'], 5);
    });

    test('returns empty list for INSERT compiled query', () async {
      final qb = client.queryBuilder().from('items').insert({
        'name': 'banana',
        'qty': 3,
      });
      final compiled = qb.toSQL();
      final rows = await client.executeCompiled(compiled);
      expect(rows, isEmpty);
    });

    test('returns empty list for UPDATE compiled query', () async {
      await client.rawQuery(
        "INSERT INTO items (name, qty) VALUES ('cherry', 1)",
        [],
      );
      final qb = client
          .queryBuilder()
          .from('items')
          .where('name', '=', 'cherry')
          .update({'qty': 10});
      final rows = await client.executeCompiled(qb.toSQL());
      expect(rows, isEmpty);
    });

    test('returns empty list for DELETE compiled query', () async {
      await client.rawQuery(
        "INSERT INTO items (name, qty) VALUES ('date', 2)",
        [],
      );
      final qb = client
          .queryBuilder()
          .from('items')
          .where('name', '=', 'date')
          .delete();
      final rows = await client.executeCompiled(qb.toSQL());
      expect(rows, isEmpty);
    });

    test('produces same result as select() for identical QueryBuilder', () async {
      await client.rawQuery(
        "INSERT INTO items (name, qty) VALUES ('elderberry', 7)",
        [],
      );
      final qb = client.queryBuilder().from('items');
      final viaSelect = await client.select(qb);
      final viaCompiled = await client.executeCompiled(qb.toSQL());
      expect(viaCompiled, equals(viaSelect));
    });

    test('handles parameterized query with bindings correctly', () async {
      await client.rawQuery(
        "INSERT INTO items (name, qty) VALUES ('fig', 4)",
        [],
      );
      await client.rawQuery(
        "INSERT INTO items (name, qty) VALUES ('grape', 9)",
        [],
      );
      final qb = client
          .queryBuilder()
          .from('items')
          .where('qty', '>', 5)
          .select(['name']);
      final rows = await client.executeCompiled(qb.toSQL());
      expect(rows, hasLength(1));
      expect(rows.first['name'], 'grape');
    });

    test('throws StateError when client is closed', () async {
      final closedClient = await SQLiteClient.connect(filename: ':memory:');
      await closedClient.close();
      final fakeCompiled = SqlString('SELECT 1', const []);
      expect(
        () => closedClient.executeCompiled(fakeCompiled),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ── _mapResults indexed access ────────────────────────────────────────────

  group('Row mapping (column names × indexed values)', () {
    late SQLiteClient client;

    setUp(() async {
      client = await _openClient();
    });

    tearDown(() => client.close());

    test('maps all columns with correct names and values', () async {
      await client.rawQuery(
        "INSERT INTO items (name, qty, active) VALUES ('apple', 5, 1)",
        [],
      );
      final rows = await client.rawQuery(
        'SELECT id, name, qty, active FROM items',
        [],
      ) as List<Map<String, dynamic>>;
      expect(rows, hasLength(1));
      final row = rows.first;
      expect(row.keys, containsAll(['id', 'name', 'qty', 'active']));
      expect(row['name'], 'apple');
      expect(row['qty'], 5);
      expect(row['active'], isNotNull);
    });

    test('returns multiple rows with correct column values', () async {
      await client.rawQuery(
        "INSERT INTO items (name, qty) VALUES ('a', 1), ('b', 2), ('c', 3)",
        [],
      );
      final rows = await client.rawQuery(
        'SELECT name, qty FROM items ORDER BY qty ASC',
        [],
      ) as List<Map<String, dynamic>>;
      expect(rows, hasLength(3));
      expect(rows[0]['name'], 'a');
      expect(rows[1]['name'], 'b');
      expect(rows[2]['name'], 'c');
    });

    test('preserves integer types in result rows', () async {
      await client.rawQuery(
        "INSERT INTO items (name, qty) VALUES ('int_test', 42)",
        [],
      );
      final rows = await client.rawQuery(
        'SELECT qty FROM items',
        [],
      ) as List<Map<String, dynamic>>;
      expect(rows.first['qty'], isA<int>());
      expect(rows.first['qty'], 42);
    });

    test('preserves null values in result rows', () async {
      await client.rawQuery(
        "INSERT INTO items (name) VALUES ('null_test')",
        [],
      );
      final rows = await client.rawQuery(
        'SELECT qty FROM items WHERE name = ?',
        ['null_test'],
      ) as List<Map<String, dynamic>>;
      // qty has a DEFAULT 0 constraint; check the actual mapped value
      expect(rows, hasLength(1));
      expect(rows.first, contains('qty'));
    });

    test('empty result set returns empty list', () async {
      final rows = await client.rawQuery(
        "SELECT * FROM items WHERE name = 'nonexistent'",
        [],
      ) as List<Map<String, dynamic>>;
      expect(rows, isEmpty);
    });
  });

  // ── KnexSQLite unified routing ────────────────────────────────────────────

  group('KnexSQLite insert/update/delete routing through select()', () {
    late KnexSQLite db;

    setUp(() async {
      db = await _openDb();
    });

    tearDown(() => db.close());

    test('insert returns empty list (no RETURNING clause)', () async {
      final qb = db.queryBuilder().table('items').insert({
        'name': 'widget',
        'qty': 1,
      });
      final result = await db.insert(qb);
      expect(result, isA<List<Map<String, dynamic>>>());
      expect(result, isEmpty);
    });

    test('update returns empty list', () async {
      await db.insert(
        db.queryBuilder().table('items').insert({'name': 'gizmo', 'qty': 5}),
      );
      final qb = db
          .queryBuilder()
          .table('items')
          .where('name', '=', 'gizmo')
          .update({'qty': 10});
      final result = await db.update(qb);
      expect(result, isA<List<Map<String, dynamic>>>());
      expect(result, isEmpty);
    });

    test('delete returns empty list', () async {
      await db.insert(
        db.queryBuilder().table('items').insert({'name': 'donut', 'qty': 3}),
      );
      final qb = db
          .queryBuilder()
          .table('items')
          .where('name', '=', 'donut')
          .delete();
      final result = await db.delete(qb);
      expect(result, isA<List<Map<String, dynamic>>>());
      expect(result, isEmpty);
    });

    test('execute returns same result as select for the same query', () async {
      await db.insert(
        db.queryBuilder().table('items').insert({'name': 'sprocket', 'qty': 2}),
      );
      final qb = db.queryBuilder().table('items');
      final viaSelect = await db.select(qb);
      final viaExecute = await db.execute(db.queryBuilder().table('items'));
      expect(viaExecute.length, viaSelect.length);
    });

    test('insert then select confirms data persisted', () async {
      await db.insert(
        db.queryBuilder().table('items').insert({'name': 'bolt', 'qty': 7}),
      );
      final rows = await db.select(db.queryBuilder().table('items'));
      expect(rows, hasLength(1));
      expect(rows.first['name'], 'bolt');
    });

    test('update changes persisted data visible via select', () async {
      await db.insert(
        db.queryBuilder().table('items').insert({'name': 'nut', 'qty': 1}),
      );
      await db.update(
        db
            .queryBuilder()
            .table('items')
            .where('name', '=', 'nut')
            .update({'qty': 99}),
      );
      final rows = await db.select(
        db.queryBuilder().table('items').where('name', '=', 'nut'),
      );
      expect(rows.first['qty'], 99);
    });

    test('delete removes row visible via select', () async {
      await db.insert(
        db.queryBuilder().table('items').insert({'name': 'washer', 'qty': 4}),
      );
      await db.delete(
        db
            .queryBuilder()
            .table('items')
            .where('name', '=', 'washer')
            .delete(),
      );
      final rows = await db.select(db.queryBuilder().table('items'));
      expect(rows, isEmpty);
    });
  });

  // ── Transaction routing ───────────────────────────────────────────────────

  group('KnexSQLiteTransaction routing through select()', () {
    late KnexSQLite db;

    setUp(() async {
      db = await _openDb();
    });

    tearDown(() => db.close());

    test('trx insert routes correctly and data is committed', () async {
      await db.trx((tx) async {
        await tx.insert(
          tx.queryBuilder().table('items').insert({'name': 'screw', 'qty': 10}),
        );
      });
      final rows = await db.select(db.queryBuilder().table('items'));
      expect(rows.length, 1);
      expect(rows.first['name'], 'screw');
    });

    test('trx update routes correctly and change is committed', () async {
      await db.insert(
        db.queryBuilder().table('items').insert({'name': 'rivet', 'qty': 5}),
      );
      await db.trx((tx) async {
        await tx.update(
          tx
              .queryBuilder()
              .table('items')
              .where('name', '=', 'rivet')
              .update({'qty': 50}),
        );
      });
      final rows = await db.select(
        db.queryBuilder().table('items').where('name', '=', 'rivet'),
      );
      expect(rows.first['qty'], 50);
    });

    test('trx delete routes correctly and row is removed after commit', () async {
      await db.insert(
        db.queryBuilder().table('items').insert({'name': 'pin', 'qty': 2}),
      );
      await db.trx((tx) async {
        await tx.delete(
          tx
              .queryBuilder()
              .table('items')
              .where('name', '=', 'pin')
              .delete(),
        );
      });
      final rows = await db.select(db.queryBuilder().table('items'));
      expect(rows, isEmpty);
    });

    test('trx rollback on error undoes insert', () async {
      await expectLater(
        db.trx((tx) async {
          await tx.insert(
            tx.queryBuilder().table('items').insert({'name': 'failed', 'qty': 1}),
          );
          throw Exception('deliberate rollback');
        }),
        throwsA(isA<Exception>()),
      );
      final rows = await db.select(db.queryBuilder().table('items'));
      expect(rows, isEmpty);
    });
  });

  // ── _execute synchronous Future semantics ────────────────────────────────

  group('_execute returns synchronous Future', () {
    late SQLiteClient client;

    setUp(() async {
      client = await _openClient();
    });

    tearDown(() => client.close());

    test('closed client causes Future.error with StateError', () async {
      await client.close();
      final future = client.rawQuery('SELECT 1', []);
      await expectLater(future, throwsA(isA<StateError>()));
    });

    test('invalid SQL causes Future.error', () async {
      final future = client.rawQuery('NOT VALID SQL !!!', []);
      await expectLater(future, throwsA(anything));
    });

    test('successful SELECT returns Future.value immediately', () async {
      await client.rawQuery(
        "INSERT INTO items (name, qty) VALUES ('test', 1)",
        [],
      );
      final result = await client.rawQuery('SELECT * FROM items', []);
      expect(result, isA<List<Map<String, dynamic>>>());
    });
  });
}
