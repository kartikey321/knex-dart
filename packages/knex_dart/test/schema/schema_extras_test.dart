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

    test('MYSQL fulltext index', () {
      final mysql = MockClient(driverName: 'mysql');
      final sql = mysql.schemaBuilder().alterTable('users', (t) {
        t.fulltext('first_name');
      }).toSQL();

      expect(sql.map((q) => q['sql']).toList(), [
        'alter table `users` add fulltext (`first_name`)',
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

  // ── Schema-mining batch 5 fixes (verified against real knex.js 3.3.0) ────

  group('fluent .unique() on an alterTable-added column', () {
    test('PG emits a deferred ADD CONSTRAINT UNIQUE', () {
      final pg = MockClient(driverName: 'pg');
      final sql = pg.schemaBuilder().alterTable('users', (t) {
        t.string('email').unique();
      }).toSQL();
      expect(sql.map((q) => q['sql']).toList(), [
        'alter table "users" add column "email" varchar(255)',
        'alter table "users" add constraint "users_email_unique" unique ("email")',
      ]);
    });

    test('MySQL uses ADD UNIQUE <name>(<col>) — no constraint keyword', () {
      final mysql = MockClient(driverName: 'mysql');
      final sql = mysql.schemaBuilder().alterTable('users', (t) {
        t.string('email').unique();
      }).toSQL();
      expect(sql.map((q) => q['sql']).toList(), [
        'alter table `users` add column `email` varchar(255)',
        'alter table `users` add unique `users_email_unique`(`email`)',
      ]);
    });

    test('SQLite uses CREATE UNIQUE INDEX', () {
      final sqlite = MockClient(driverName: 'sqlite');
      final sql = sqlite.schemaBuilder().alterTable('users', (t) {
        t.string('email').unique();
      }).toSQL();
      expect(sql.map((q) => q['sql']).toList(), [
        'alter table "users" add column "email" varchar(255)',
        'create unique index "users_email_unique" on "users" ("email")',
      ]);
    });

    test('honors a custom indexName', () {
      final pg = MockClient(driverName: 'pg');
      final sql = pg.schemaBuilder().alterTable('users', (t) {
        t.string('email').unique(indexName: 'custom_idx');
      }).toSQL();
      expect(sql.last['sql'],
          'alter table "users" add constraint "custom_idx" unique ("email")');
    });
  });

  group('MySQL createTable-time deferred unique uses ADD UNIQUE syntax', () {
    test('column-level .unique() in createTable', () {
      final mysql = MockClient(driverName: 'mysql');
      final sql = mysql.schemaBuilder().createTable('users', (t) {
        t.increments('id');
        t.string('email').unique();
      }).toSQL();
      expect(sql.map((q) => q['sql']).toList(), [
        'create table `users` (`id` int unsigned auto_increment primary key, `email` varchar(255))',
        'alter table `users` add unique `users_email_unique`(`email`)',
      ]);
    });
  });

  group('table.comment(...)', () {
    test('PG emits a separate COMMENT ON TABLE statement after CREATE TABLE', () {
      final pg = MockClient(driverName: 'pg');
      final sql = pg.schemaBuilder().createTable('users', (t) {
        t.string('username');
        t.comment('Custom comment');
      }).toSQL();
      expect(sql.map((q) => q['sql']).toList(), [
        'create table "users" ("username" varchar(255))',
        'comment on table "users" is \'Custom comment\'',
      ]);
    });

    test('MySQL folds the comment inline into CREATE TABLE', () {
      final mysql = MockClient(driverName: 'mysql');
      final sql = mysql.schemaBuilder().createTable('users', (t) {
        t.string('username');
        t.comment('Custom comment');
      }).toSQL();
      expect(sql.map((q) => q['sql']).toList(), [
        "create table `users` (`username` varchar(255)) comment = 'Custom comment'",
      ]);
    });

    test('SQLite silently drops the comment (no table-comment support)', () {
      final sqlite = MockClient(driverName: 'sqlite');
      final sql = sqlite.schemaBuilder().createTable('users', (t) {
        t.string('username');
        t.comment('Custom comment');
      }).toSQL();
      expect(sql.map((q) => q['sql']).toList(), [
        'create table "users" ("username" varchar(255))',
      ]);
    });

    test('PG alterTable comment emits COMMENT ON TABLE', () {
      final pg = MockClient(driverName: 'pg');
      final sql = pg.schemaBuilder().alterTable('users', (t) {
        t.comment('Custom comment');
      }).toSQL();
      expect(sql.map((q) => q['sql']).toList(), [
        'comment on table "users" is \'Custom comment\'',
      ]);
    });

    test('MySQL alterTable comment emits ALTER TABLE ... COMMENT =', () {
      final mysql = MockClient(driverName: 'mysql');
      final sql = mysql.schemaBuilder().alterTable('users', (t) {
        t.comment('Custom comment');
      }).toSQL();
      expect(sql.map((q) => q['sql']).toList(), [
        "alter table `users` comment = 'Custom comment'",
      ]);
    });
  });

  group('dropColumns combines into a single ALTER TABLE statement', () {
    test('PG', () {
      final pg = MockClient(driverName: 'pg');
      final sql = pg.schemaBuilder().alterTable('users', (t) {
        t.dropColumns(['a', 'b']);
      }).toSQL();
      expect(sql.map((q) => q['sql']).toList(), [
        'alter table "users" drop column "a", drop column "b"',
      ]);
    });

    test('MySQL', () {
      final mysql = MockClient(driverName: 'mysql');
      final sql = mysql.schemaBuilder().alterTable('users', (t) {
        t.dropColumns(['a', 'b']);
      }).toSQL();
      expect(sql.map((q) => q['sql']).toList(), [
        'alter table `users` drop `a`, drop `b`',
      ]);
    });
  });

  group('.references() dotted-shorthand table.column parsing', () {
    test('sets both referenced table and column from one call', () {
      final pg = MockClient(driverName: 'pg');
      final sql = pg.schemaBuilder().createTable('orders', (t) {
        t.integer('user_id').references('users.id');
      }).toSQL();
      expect(sql.map((q) => q['sql']).toList(), [
        'create table "orders" ("user_id" integer)',
        'alter table "orders" add constraint "orders_user_id_foreign" foreign key ("user_id") references "users" ("id")',
      ]);
    });

    test('a following .inTable() still overrides the parsed table', () {
      final pg = MockClient(driverName: 'pg');
      final sql = pg.schemaBuilder().createTable('orders', (t) {
        t.integer('user_id').references('users.id').inTable('accounts');
      }).toSQL();
      expect(sql.last['sql'], contains('references "accounts" ("id")'));
    });
  });

  group('Redshift enum() has no native ENUM or CHECK support', () {
    test('emits a bare varchar(255)', () {
      final redshift = MockClient(driverName: 'redshift');
      final sql = redshift.schemaBuilder().createTable('t', (tb) {
        tb.enu('status', ['active', 'idle']);
      }).toSQL();
      expect(sql.single['sql'], 'create table "t" ("status" varchar(255))');
    });
  });

  group('dialect-aware doublePrecision()/decimal() type mapping', () {
    test('MySQL doublePrecision -> double', () {
      final mysql = MockClient(driverName: 'mysql');
      final sql = mysql.schemaBuilder().createTable('t', (tb) {
        tb.doublePrecision('x');
      }).toSQL();
      expect(sql.single['sql'], 'create table `t` (`x` double)');
    });

    test('SQLite doublePrecision -> float', () {
      final sqlite = MockClient(driverName: 'sqlite');
      final sql = sqlite.schemaBuilder().createTable('t', (tb) {
        tb.doublePrecision('x');
      }).toSQL();
      expect(sql.single['sql'], 'create table "t" ("x" float)');
    });

    test('SQLite decimal drops precision/scale -> float', () {
      final sqlite = MockClient(driverName: 'sqlite');
      final sql = sqlite.schemaBuilder().createTable('t', (tb) {
        tb.decimal('x', 5, 2);
      }).toSQL();
      expect(sql.single['sql'], 'create table "t" ("x" float)');
    });

    test('Postgres decimal keeps precision/scale', () {
      final pg = MockClient(driverName: 'pg');
      final sql = pg.schemaBuilder().createTable('t', (tb) {
        tb.decimal('x', 5, 2);
      }).toSQL();
      expect(sql.single['sql'], 'create table "t" ("x" decimal(5, 2))');
    });
  });
}
