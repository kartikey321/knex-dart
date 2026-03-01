import 'package:test/test.dart';
import '../mocks/mock_client.dart';

void main() {
  group('SchemaBuilder Extras Comparison', () {
    test('PG dropTimestamps', () {
      final pg = MockClient(driverName: 'pg');
      final sql = pg.schemaBuilder().alterTable('users', (t) {
        t.dropTimestamps();
      }).toSQL();

      expect(sql.map((q) => q['sql']).toList(), [
        'alter table "users" drop column "created_at", drop column "updated_at"',
      ]);
    });

    test('PG dropTimestamps camelCase', () {
      final pg = MockClient(driverName: 'pg');
      final sql = pg.schemaBuilder().alterTable('users', (t) {
        t.dropTimestamps(true);
      }).toSQL();

      expect(sql.map((q) => q['sql']).toList(), [
        'alter table "users" drop column "createdAt", drop column "updatedAt"',
      ]);
    });

    test('PG setNullable', () {
      final pg = MockClient(driverName: 'pg');
      final sql = pg.schemaBuilder().alterTable('users', (t) {
        t.setNullable('email');
      }).toSQL();

      expect(sql.map((q) => q['sql']).toList(), [
        'alter table "users" alter column "email" drop not null',
      ]);
    });

    test('PG dropNullable', () {
      final pg = MockClient(driverName: 'pg');
      final sql = pg.schemaBuilder().alterTable('users', (t) {
        t.dropNullable('email');
      }).toSQL();

      expect(sql.map((q) => q['sql']).toList(), [
        'alter table "users" alter column "email" set not null',
      ]);
    });

    test('PG fluent foreign', () {
      final pg = MockClient(driverName: 'pg');
      final sql = pg.schemaBuilder().alterTable('users', (t) {
        t
            .foreign('company_id')
            .references('id')
            .inTable('companies')
            .onDelete('CASCADE')
            .onUpdate('RESTRICT');
      }).toSQL();

      expect(sql.map((q) => q['sql']).toList(), [
        'alter table "users" add constraint "users_company_id_foreign" foreign key ("company_id") references "companies" ("id") on delete CASCADE on update RESTRICT',
      ]);
    });

    test('MYSQL dropTimestamps', () {
      final mysql = MockClient(driverName: 'mysql');
      final sql = mysql.schemaBuilder().alterTable('users', (t) {
        t.dropTimestamps();
      }).toSQL();

      expect(sql.map((q) => q['sql']).toList(), [
        'alter table `users` drop `created_at`, drop `updated_at`',
      ]);
    });

    test('MYSQL fluent foreign', () {
      final mysql = MockClient(driverName: 'mysql');
      final sql = mysql.schemaBuilder().alterTable('users', (t) {
        t
            .foreign('company_id')
            .references('id')
            .inTable('companies')
            .onDelete('CASCADE')
            .onUpdate('RESTRICT');
      }).toSQL();

      expect(sql.map((q) => q['sql']).toList(), [
        'alter table `users` add constraint `users_company_id_foreign` foreign key (`company_id`) references `companies` (`id`) on delete CASCADE on update RESTRICT',
      ]);
    });

    test('PG createTableIfNotExists', () {
      final pg = MockClient(driverName: 'pg');
      final sql = pg.schemaBuilder().createTableIfNotExists('users', (t) {
        t.increments('id');
      }).toSQL();

      expect(sql.map((q) => q['sql']).toList(), [
        'create table if not exists "users" ("id" serial primary key)',
      ]);
    });

    test('PG bigIncrements', () {
      final pg = MockClient(driverName: 'pg');
      final sql = pg.schemaBuilder().createTable('users', (t) {
        t.bigIncrements('id');
      }).toSQL();

      expect(sql.map((q) => q['sql']).toList(), [
        'create table "users" ("id" bigserial primary key)',
      ]);
    });

    test('PG composite unique', () {
      final pg = MockClient(driverName: 'pg');
      final sql = pg.schemaBuilder().alterTable('users', (t) {
        t.unique(['email', 'username']);
      }).toSQL();

      expect(sql.map((q) => q['sql']).toList(), [
        'alter table "users" add constraint "users_email_username_unique" unique ("email", "username")',
      ]);
    });

    test('SQLite composite index', () {
      final sqlite = MockClient(driverName: 'sqlite');
      final sql = sqlite.schemaBuilder().alterTable('users', (t) {
        t.index(['email', 'username']);
      }).toSQL();

      expect(sql.map((q) => q['sql']).toList(), [
        'create index "users_email_username_index" on "users" ("email", "username")',
      ]);
    });
  });
}
