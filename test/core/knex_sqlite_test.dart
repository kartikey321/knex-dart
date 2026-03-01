import 'package:knex_dart/knex_dart.dart';
import 'package:test/test.dart';

void main() {
  // ── Knex._createClient dialect aliases ────────────────────────────────────

  group('Knex._createClient dialect aliases', () {
    test('sqlite3 alias works', () {
      final knex = Knex(
        KnexConfig(client: 'sqlite3', connection: {'filename': ':memory:'}),
      );
      expect(knex.client.driverName, equals('sqlite3'));
    });

    test('postgresql alias throws UnimplementedError', () {
      expect(
        () => Knex(
          KnexConfig(client: 'postgresql', connection: {}),
        ),
        throwsUnimplementedError,
      );
    });

    test('mysql2 alias throws UnimplementedError', () {
      expect(
        () => Knex(
          KnexConfig(client: 'mysql2', connection: {}),
        ),
        throwsUnimplementedError,
      );
    });

    test('unknown dialect throws UnimplementedError', () {
      expect(
        () => Knex(KnexConfig(client: 'oracle', connection: {})),
        throwsUnimplementedError,
      );
    });
  });

  // ── Knex getters ──────────────────────────────────────────────────────────

  group('Knex getters', () {
    late Knex knex;

    setUp(() {
      knex = Knex(
        KnexConfig(client: 'sqlite', connection: {'filename': ':memory:'}),
      );
    });

    tearDown(() => knex.destroy());

    test('client getter returns the underlying Client', () {
      expect(knex.client, isNotNull);
      expect(knex.client.driverName, equals('sqlite3'));
    });

    test('schema getter returns a SchemaBuilder', () {
      expect(knex.schema, isNotNull);
    });

    test('migrate getter returns a Migrator', () {
      expect(knex.migrate, isNotNull);
    });

    test('ref() returns a Ref', () {
      final r = knex.ref('users.id');
      expect(r, isNotNull);
      expect(r.toSQL().sql, contains('users'));
    });

    test('raw() with bindings returns a Raw object', () {
      final r = knex.raw('select ?', [1]);
      expect(r, isNotNull);
    });
  });

  // ── KnexSQLite via Knex.sqlite() ──────────────────────────────────────────

  group('KnexSQLite', () {
    late KnexSQLite db;

    setUp(() async {
      db = await Knex.sqlite(filename: ':memory:');
      await db.executeSchema((s) {
        s.createTable('items', (t) {
          t.increments('id');
          t.string('name');
          t.integer('qty').defaultTo(0);
        });
      });
    });

    tearDown(() => db.close());

    test('queryBuilder() returns a usable QueryBuilder', () {
      final qb = db.queryBuilder();
      expect(qb.toSQL().sql, equals('select *'));
    });

    test('schema getter returns a SchemaBuilder', () {
      expect(db.schema, isNotNull);
    });

    test('raw() returns a Raw with correct SQL', () {
      final r = db.raw('select 1');
      expect(r.toSQL().sql, equals('select 1'));
    });

    test('insert then select', () async {
      await db.insert(
        db.queryBuilder().table('items').insert({'name': 'apple', 'qty': 5}),
      );
      final rows = await db.select(db.queryBuilder().table('items'));
      expect(rows.length, equals(1));
      expect(rows.first['name'], equals('apple'));
    });

    test('update changes a row', () async {
      await db.insert(
        db.queryBuilder().table('items').insert({'name': 'banana', 'qty': 3}),
      );
      await db.update(
        db
            .queryBuilder()
            .table('items')
            .where('name', 'banana')
            .update({'qty': 10}),
      );
      final rows = await db.select(
        db.queryBuilder().table('items').where('name', 'banana'),
      );
      expect(rows.first['qty'], equals(10));
    });

    test('delete removes a row', () async {
      await db.insert(
        db.queryBuilder().table('items').insert({'name': 'cherry', 'qty': 1}),
      );
      await db.delete(
        db
            .queryBuilder()
            .table('items')
            .where('name', 'cherry')
            .delete(),
      );
      final rows = await db.select(db.queryBuilder().table('items'));
      expect(rows, isEmpty);
    });

    test('execute returns result list', () async {
      await db.insert(
        db.queryBuilder().table('items').insert({'name': 'date', 'qty': 2}),
      );
      final result = await db.execute(db.queryBuilder().table('items'));
      expect(result, isA<List<Map<String, dynamic>>>());
    });

    test('trx commits on success', () async {
      await db.trx((trx) async {
        await trx.insert(
          trx
              .queryBuilder()
              .table('items')
              .insert({'name': 'elderberry', 'qty': 7}),
        );
      });
      final rows = await db.select(
        db.queryBuilder().table('items').where('name', 'elderberry'),
      );
      expect(rows.length, equals(1));
    });

    test('executeSchema creates table and allows insert', () async {
      await db.executeSchema((s) {
        s.createTable('tags', (t) {
          t.increments('id');
          t.string('label');
        });
      });
      await db.insert(
        db.queryBuilder().table('tags').insert({'label': 'dart'}),
      );
      final rows = await db.select(db.queryBuilder().table('tags'));
      expect(rows.first['label'], equals('dart'));
    });
  });
}
