import 'package:knex_dart/src/schema/table_builder.dart';
import 'package:test/test.dart';

import '../mocks/mock_client.dart';

void main() {
  // ── Dialect type resolution ────────────────────────────────────────────────

  group('TableBuilder - MySQL dialect type mapping', () {
    late MockClient mysql;

    setUp(() => mysql = MockClient(driverName: 'mysql'));

    test('increments uses int unsigned auto_increment primary key', () {
      final t = TableBuilder(mysql, 'create', 'tbl');
      t.increments('id');
      expect(t.columns.first.type, contains('auto_increment'));
    });

    test('bigIncrements uses bigint unsigned auto_increment primary key', () {
      final t = TableBuilder(mysql, 'create', 'tbl');
      t.bigIncrements('id');
      expect(t.columns.first.type, contains('bigint'));
    });

    test('boolean uses tinyint(1)', () {
      final t = TableBuilder(mysql, 'create', 'tbl');
      t.boolean('active');
      expect(t.columns.first.type, equals('tinyint(1)'));
    });

    test('datetime uses datetime (not timestamptz)', () {
      final t = TableBuilder(mysql, 'create', 'tbl');
      t.datetime('created_at');
      expect(t.columns.first.type, equals('datetime'));
    });

    test('float uses float', () {
      final t = TableBuilder(mysql, 'create', 'tbl');
      t.float('score');
      expect(t.columns.first.type, equals('float'));
    });

    test('uuid uses char(36)', () {
      final t = TableBuilder(mysql, 'create', 'tbl');
      t.uuid('uid');
      expect(t.columns.first.type, equals('char(36)'));
    });

    test('json uses json', () {
      final t = TableBuilder(mysql, 'create', 'tbl');
      t.json('meta');
      expect(t.columns.first.type, equals('json'));
    });

    test('jsonb uses json (no jsonb in MySQL)', () {
      final t = TableBuilder(mysql, 'create', 'tbl');
      t.jsonb('meta');
      expect(t.columns.first.type, equals('json'));
    });

    test('binary uses blob', () {
      final t = TableBuilder(mysql, 'create', 'tbl');
      t.binary('data');
      expect(t.columns.first.type, equals('blob'));
    });

    test('enu uses enum(...) syntax', () {
      final t = TableBuilder(mysql, 'create', 'tbl');
      t.enu('status', ['active', 'inactive']);
      expect(t.columns.first.type, contains("enum('active', 'inactive')"));
    });
  });

  group('TableBuilder - SQLite dialect type mapping', () {
    late MockClient sqlite;

    setUp(() => sqlite = MockClient(driverName: 'sqlite'));

    test('increments uses integer primary key autoincrement', () {
      final t = TableBuilder(sqlite, 'create', 'tbl');
      t.increments('id');
      expect(t.columns.first.type, equals('integer primary key autoincrement'));
    });

    test('uuid uses char(36)', () {
      final t = TableBuilder(sqlite, 'create', 'tbl');
      t.uuid('uid');
      expect(t.columns.first.type, equals('char(36)'));
    });

    test('jsonb uses text (SQLite has no jsonb)', () {
      final t = TableBuilder(sqlite, 'create', 'tbl');
      t.jsonb('meta');
      expect(t.columns.first.type, equals('text'));
    });

    test('float uses float', () {
      final t = TableBuilder(sqlite, 'create', 'tbl');
      t.float('score');
      expect(t.columns.first.type, equals('float'));
    });
  });

  // ── Column type methods not elsewhere tested ───────────────────────────────

  group('TableBuilder - column types', () {
    late MockClient pg;

    setUp(() => pg = MockClient(driverName: 'pg'));

    test('time() creates time column', () {
      final t = TableBuilder(pg, 'create', 'tbl');
      t.time('start_time');
      expect(t.columns.first.type, equals('time'));
    });

    test('doublePrecision() creates double precision column', () {
      final t = TableBuilder(pg, 'create', 'tbl');
      t.doublePrecision('amount');
      expect(t.columns.first.type, equals('double precision'));
    });

    test('specificType() creates column with raw SQL type', () {
      final t = TableBuilder(pg, 'create', 'tbl');
      t.specificType('data', 'citext');
      expect(t.columns.first.type, equals('citext'));
    });

    test('timestamps(defaultToNow: true) adds NOT NULL + default', () {
      final t = TableBuilder(pg, 'create', 'tbl');
      t.timestamps(false, true);
      expect(t.columns.length, equals(2));
      expect(t.columns.first.name, equals('created_at'));
      expect(t.columns.last.name, equals('updated_at'));
      // Both should produce 'not null' in their SQL
      expect(t.columns.first.toSQL(), contains('not null'));
      expect(t.columns.last.toSQL(), contains('not null'));
    });
  });

  // ── Alter table operations not elsewhere tested ───────────────────────────

  group('TableBuilder - alter statements', () {
    late MockClient pg;

    setUp(() => pg = MockClient(driverName: 'pg'));

    test('comment() stores table comment in single map', () {
      final t = TableBuilder(pg, 'alter', 'tbl');
      t.comment('Users table');
      expect(t.single['comment'], equals('Users table'));
    });

    test('dropPrimary() records alter statement', () {
      final t = TableBuilder(pg, 'alter', 'tbl');
      t.dropPrimary();
      expect(t.alterStatements.any((s) => s['method'] == 'dropPrimary'), isTrue);
    });

    test('dropPrimary() with constraint name', () {
      final t = TableBuilder(pg, 'alter', 'tbl');
      t.dropPrimary('pk_tbl');
      final stmt = t.alterStatements.firstWhere((s) => s['method'] == 'dropPrimary');
      expect(stmt['args'], contains('pk_tbl'));
    });

    test('dropUnique() records alter statement', () {
      final t = TableBuilder(pg, 'alter', 'tbl');
      t.dropUnique('email');
      expect(t.alterStatements.any((s) => s['method'] == 'dropUnique'), isTrue);
    });

    test('dropIndex() records alter statement', () {
      final t = TableBuilder(pg, 'alter', 'tbl');
      t.dropIndex('idx_name');
      expect(t.alterStatements.any((s) => s['method'] == 'dropIndex'), isTrue);
    });
  });

  // ── ForeignBuilder ─────────────────────────────────────────────────────────

  group('ForeignBuilder', () {
    late MockClient pg;

    setUp(() => pg = MockClient(driverName: 'pg'));

    test('foreign().references().inTable().onDelete().onUpdate() chains', () {
      final t = TableBuilder(pg, 'alter', 'tbl');
      t
          .foreign('user_id')
          .references('id')
          .inTable('users')
          .onDelete('cascade')
          .onUpdate('restrict');

      final stmt = t.alterStatements.firstWhere((s) => s['method'] == 'foreign');
      final data = stmt['args'][0] as Map<String, dynamic>;

      expect(data['references'], equals('id'));
      expect(data['inTable'], equals('users'));
      expect(data['onDelete'], equals('CASCADE'));
      expect(data['onUpdate'], equals('RESTRICT'));
    });
  });
}
