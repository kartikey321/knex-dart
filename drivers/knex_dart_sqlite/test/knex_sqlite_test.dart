import 'dart:io';

import 'package:knex_dart/knex_dart.dart';
import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';
import 'package:test/test.dart';

void main() {
  // ── Knex with SQLiteClient ────────────────────────────────────────────────

  group('Knex with SQLiteClient', () {
    test('sqlite3 alias works via SQLiteClient.fromConfig', () {
      final client = SQLiteClient.fromConfig(
        KnexConfig(client: 'sqlite3', connection: {'filename': ':memory:'}),
      );
      final knex = Knex(client);
      expect(knex.client.driverName, equals('sqlite3'));
      knex.destroy();
    });

    test('sqlite alias works via SQLiteClient.fromConfig', () {
      final client = SQLiteClient.fromConfig(
        KnexConfig(client: 'sqlite', connection: {'filename': ':memory:'}),
      );
      final knex = Knex(client);
      expect(knex.client.driverName, equals('sqlite3'));
      knex.destroy();
    });
  });

  // ── Knex getters ──────────────────────────────────────────────────────────

  group('Knex getters', () {
    late Knex knex;

    setUp(() {
      final client = SQLiteClient.fromConfig(
        KnexConfig(client: 'sqlite', connection: {'filename': ':memory:'}),
      );
      knex = Knex(client);
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

  // ── KnexSQLite via KnexSQLite.connect() ──────────────────────────────────

  group('KnexSQLite', () {
    late KnexSQLite db;

    setUp(() async {
      db = await KnexSQLite.connect(filename: ':memory:');
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

    // ── Nested transactions (savepoints) ─────────────────────────────────────

    test('nested trx: both commit — all changes visible', () async {
      await db.trx((outer) async {
        await outer.insert(
          outer.queryBuilder().table('items').insert({'name': 'outer', 'qty': 1}),
        );
        await outer.trx((inner) async {
          await inner.insert(
            inner.queryBuilder().table('items').insert({'name': 'inner', 'qty': 2}),
          );
        });
      });
      final rows = await db.select(db.queryBuilder().table('items'));
      expect(rows.length, equals(2));
      expect(rows.any((r) => r['name'] == 'outer'), isTrue);
      expect(rows.any((r) => r['name'] == 'inner'), isTrue);
    });

    test('nested trx: inner rollback, outer continues and commits', () async {
      await db.trx((outer) async {
        await outer.insert(
          outer.queryBuilder().table('items').insert({'name': 'outer_only', 'qty': 10}),
        );
        try {
          await outer.trx((inner) async {
            await inner.insert(
              inner.queryBuilder().table('items').insert({'name': 'inner_only', 'qty': 99}),
            );
            throw Exception('inner failure');
          });
        } catch (_) {
          // inner rolled back to savepoint; outer continues
        }
        await outer.insert(
          outer.queryBuilder().table('items').insert({'name': 'outer_after', 'qty': 20}),
        );
      });
      final rows = await db.select(db.queryBuilder().table('items'));
      final names = rows.map((r) => r['name'] as String).toList();
      expect(names, contains('outer_only'));
      expect(names, contains('outer_after'));
      expect(names, isNot(contains('inner_only')));
    });

    test('nested trx: inner rollback bubbles — outer also rolls back', () async {
      await expectLater(
        () => db.trx((outer) async {
          await outer.insert(
            outer.queryBuilder().table('items').insert({'name': 'outer_bubble', 'qty': 5}),
          );
          await outer.trx((inner) async {
            await inner.insert(
              inner.queryBuilder().table('items').insert({'name': 'inner_bubble', 'qty': 50}),
            );
            throw Exception('bubble up');
          });
        }),
        throwsException,
      );
      final rows = await db.select(db.queryBuilder().table('items'));
      expect(rows, isEmpty);
    });
  });

  // ── Migration pipeline ────────────────────────────────────────────────────

  group('Migration pipeline — SQLite :memory:', () {
    late Knex knex;
    late SQLiteClient sqlite;

    setUp(() async {
      sqlite = await SQLiteClient.connect(filename: ':memory:');
      knex = Knex(sqlite);
    });

    tearDown(() async {
      await sqlite.close();
    });

    const migrations = [
      SqlMigration(
        name: '001_create_users',
        upSql: [
          'CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
        ],
        downSql: ['DROP TABLE users'],
      ),
      SqlMigration(
        name: '002_add_email',
        upSql: ['ALTER TABLE users ADD COLUMN email TEXT'],
        downSql: [
          // SQLite does not support DROP COLUMN in older versions;
          // recreate the table without the column.
          'CREATE TABLE users_tmp (id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
          'INSERT INTO users_tmp SELECT id, name FROM users',
          'DROP TABLE users',
          'ALTER TABLE users_tmp RENAME TO users',
        ],
      ),
    ];

    test('latest() creates schema and records are queryable', () async {
      await knex.migrator(migrations: migrations).latest();

      // Table exists — can insert and select.
      await sqlite.rawQuery(
        'INSERT INTO users (id, name, email) VALUES (1, \'Alice\', \'alice@example.com\')',
        [],
      );
      final rows = await sqlite.rawQuery('SELECT * FROM users', []) as List;
      expect(rows.length, 1);
      expect(rows.first['name'], 'Alice');
    });

    test('latest() is idempotent — running twice does not duplicate work',
        () async {
      final migrator = knex.migrator(migrations: migrations);
      await migrator.latest();
      await migrator.latest(); // second call should be a no-op

      final status = await migrator.status();
      expect(status.every((s) => s['status'] == 'completed'), isTrue);
    });

    test('rollback() reverts the latest batch only', () async {
      final m1 = knex.migrator(migrations: [migrations[0]]);
      final m2 = knex.migrator(migrations: migrations);

      await m1.latest(); // batch 1: 001
      await m2.latest(); // batch 2: 002

      await m2.rollback(); // rolls back batch 2 (002 only)

      // users table still exists (001 was not rolled back).
      final rows =
          await sqlite.rawQuery('SELECT name FROM sqlite_master WHERE type=\'table\' AND name=\'users\'', []) as List;
      expect(rows.length, 1);

      // But email column is gone — check via pragma.
      final cols =
          await sqlite.rawQuery('PRAGMA table_info(users)', []) as List;
      final colNames = cols.map((c) => c['name'] as String).toList();
      expect(colNames, contains('id'));
      expect(colNames, contains('name'));
      expect(colNames, isNot(contains('email')));

      // Rolling back again removes batch 1.
      await m2.rollback();
      final tables =
          await sqlite.rawQuery('SELECT name FROM sqlite_master WHERE type=\'table\' AND name=\'users\'', []) as List;
      expect(tables, isEmpty);
    });

    test('disableTransactions:false exercises runInTransaction via trx()',
        () async {
      // Build a Knex with transactions enabled for SQLite.
      final txKnex = Knex(
        sqlite,
        // ignore: invalid_use_of_visible_for_testing_member
      );
      final migrator = Migrator(
        txKnex,
        migrations: migrations,
        config: const MigrationConfig(disableTransactions: false),
      );

      await migrator.latest();

      final status = await migrator.status();
      expect(status.every((s) => s['status'] == 'completed'), isTrue);

      await migrator.rollback();
      await migrator.rollback();

      final tables =
          await sqlite.rawQuery('SELECT name FROM sqlite_master WHERE type=\'table\' AND name=\'users\'', []) as List;
      expect(tables, isEmpty);
    });

    test('fromConfig() reads .up.sql/.down.sql files from config.directory',
        () async {
      final dir = await Directory.systemTemp.createTemp('knex_sqlite_cfg_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      await File('${dir.path}/001_items.up.sql').writeAsString(
        'CREATE TABLE items (id INTEGER PRIMARY KEY, label TEXT)',
      );
      await File(
        '${dir.path}/001_items.down.sql',
      ).writeAsString('DROP TABLE items');

      final cfgKnex = Knex(
        SQLiteClient.fromConfig(
          KnexConfig(
            client: 'sqlite3',
            connection: {'filename': ':memory:'},
            migrations: MigrationConfig(directory: dir.path),
          ),
        ),
      );
      addTearDown(() => cfgKnex.destroy());

      await cfgKnex.migrate.fromConfig().latest();

      final tables =
          await (cfgKnex.client as SQLiteClient).rawQuery(
        'SELECT name FROM sqlite_master WHERE type=\'table\' AND name=\'items\'',
        [],
      ) as List;
      expect(tables.length, 1);

      await cfgKnex.migrate.fromConfig().rollback();

      final tablesAfter =
          await (cfgKnex.client as SQLiteClient).rawQuery(
        'SELECT name FROM sqlite_master WHERE type=\'table\' AND name=\'items\'',
        [],
      ) as List;
      expect(tablesAfter, isEmpty);
    });
  });
}
