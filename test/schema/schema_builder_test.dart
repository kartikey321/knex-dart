/// Dart parity tests for Schema Builder
///
/// JS Baseline: knex-js/test/js_comparison/querycompiler_step21_schema.js
/// Run baseline: cd knex-js && node test/js_comparison/querycompiler_step21_schema.js
/// Run this test: cd knex-dart && dart test test/schema/schema_builder_test.dart
library;

import 'package:test/test.dart';
import '../mocks/mock_client.dart';

void main() {
  late MockClient client;

  setUp(() {
    client = MockClient();
  });

  group('JS Parity: Schema Builder (Step 21)', () {
    // Test 1: createTable with integer, string, timestamps
    test('Test 1: createTable basic', () {
      final schema = client.schemaBuilder();
      schema.createTable('users', (table) {
        table.increments('id');
        table.string('name');
        table.string('email', 255);
        table.integer('age');
        table.timestamps(true, true);
      });
      final sqls = schema.toSQL();

      // JS: create table "users" ("id" serial primary key, "name" varchar(255),
      //     "email" varchar(255), "age" integer,
      //     "created_at" timestamptz not null default CURRENT_TIMESTAMP,
      //     "updated_at" timestamptz not null default CURRENT_TIMESTAMP)
      expect(sqls.length, 1);
      expect(
        sqls[0]['sql'],
        'create table "users" ("id" serial primary key, "name" varchar(255), '
        '"email" varchar(255), "age" integer, '
        '"created_at" timestamptz not null default CURRENT_TIMESTAMP, '
        '"updated_at" timestamptz not null default CURRENT_TIMESTAMP)',
      );
      expect(sqls[0]['bindings'], []);
    });

    // Test 2: createTable with constraints
    test('Test 2: createTable with constraints', () {
      final schema = client.schemaBuilder();
      schema.createTable('posts', (table) {
        table.increments('id').primary();
        table.string('title').notNullable();
        table.text('body');
        table.boolean('published').defaultTo(false);
        table.integer('author_id').unsigned().references('id').inTable('users');
      });
      final sqls = schema.toSQL();

      // JS produces 2 SQL statements:
      // [0] create table "posts" (...)
      // [1] alter table "posts" add constraint "posts_author_id_foreign" ...
      expect(sqls.length, 2);
      expect(
        sqls[0]['sql'],
        'create table "posts" ("id" serial primary key, "title" varchar(255) not null, '
        '"body" text, "published" boolean default \'0\', "author_id" integer)',
      );
      expect(
        sqls[1]['sql'],
        'alter table "posts" add constraint "posts_author_id_foreign" '
        'foreign key ("author_id") references "users" ("id")',
      );
    });

    // Test 3: dropTable
    test('Test 3: dropTable', () {
      final sqls = client.schemaBuilder().dropTable('users').toSQL();
      // JS: drop table "users"
      expect(sqls.length, 1);
      expect(sqls[0]['sql'], 'drop table "users"');
    });

    // Test 4: dropTableIfExists
    test('Test 4: dropTableIfExists', () {
      final sqls = client.schemaBuilder().dropTableIfExists('users').toSQL();
      // JS: drop table if exists "users"
      expect(sqls.length, 1);
      expect(sqls[0]['sql'], 'drop table if exists "users"');
    });

    // Test 5: renameTable
    test('Test 5: renameTable', () {
      final sqls = client
          .schemaBuilder()
          .renameTable('users', 'people')
          .toSQL();
      // JS: alter table "users" rename to "people"
      expect(sqls.length, 1);
      expect(sqls[0]['sql'], 'alter table "users" rename to "people"');
    });

    // Test 6: alterTable add column
    test('Test 6: alterTable add column', () {
      final schema = client.schemaBuilder();
      schema.alterTable('users', (table) {
        table.string('phone');
      });
      final sqls = schema.toSQL();
      // JS: alter table "users" add column "phone" varchar(255)
      expect(sqls.length, 1);
      expect(
        sqls[0]['sql'],
        'alter table "users" add column "phone" varchar(255)',
      );
    });

    // Test 7: alterTable drop column
    test('Test 7: alterTable drop column', () {
      final schema = client.schemaBuilder();
      schema.alterTable('users', (table) {
        table.dropColumn('phone');
      });
      final sqls = schema.toSQL();
      // JS: alter table "users" drop column "phone"
      expect(sqls.length, 1);
      expect(sqls[0]['sql'], 'alter table "users" drop column "phone"');
    });

    // Test 8: createTable with many column types
    test('Test 8: createTable with many column types', () {
      final schema = client.schemaBuilder();
      schema.createTable('all_types', (table) {
        table.boolean('is_active');
        table.text('description');
        table.json('metadata');
        table.jsonb('data');
        table.uuid('tracking_id');
        table.float('score');
        table.decimal('price', 8, 2);
        table.date('birth_date');
        table.datetime('login_at');
        table.timestamp('created_at');
        table.binary('file_data');
        table.enu('status', ['active', 'inactive', 'banned']);
      });
      final sqls = schema.toSQL();

      // JS: create table "all_types" ("is_active" boolean, "description" text,
      //     "metadata" json, "data" jsonb, "tracking_id" uuid, "score" real,
      //     "price" decimal(8, 2), "birth_date" date, "login_at" timestamptz,
      //     "created_at" timestamptz, "file_data" bytea,
      //     "status" text check ("status" in ('active', 'inactive', 'banned')))
      expect(sqls.length, 1);
      expect(
        sqls[0]['sql'],
        'create table "all_types" ("is_active" boolean, "description" text, '
        '"metadata" json, "data" jsonb, "tracking_id" uuid, "score" real, '
        '"price" decimal(8, 2), "birth_date" date, "login_at" timestamptz, '
        '"created_at" timestamptz, "file_data" bytea, '
        '"status" text check ("status" in (\'active\', \'inactive\', \'banned\')))',
      );
    });

    // Test 9: createTable with unique constraint
    test('Test 9: createTable with unique', () {
      final schema = client.schemaBuilder();
      schema.createTable('accounts', (table) {
        table.increments('id');
        table.string('email').unique();
        table.string('username').unique();
      });
      final sqls = schema.toSQL();

      // JS: 3 statements - CREATE + 2x ALTER TABLE ADD UNIQUE
      expect(sqls.length, 3);
      expect(
        sqls[0]['sql'],
        'create table "accounts" ("id" serial primary key, '
        '"email" varchar(255), "username" varchar(255))',
      );
      expect(
        sqls[1]['sql'],
        'alter table "accounts" add constraint "accounts_email_unique" unique ("email")',
      );
      expect(
        sqls[2]['sql'],
        'alter table "accounts" add constraint "accounts_username_unique" unique ("username")',
      );
    });

    // Test 9b: timestamp without timezone on PostgreSQL
    test('Test 9b: timestamp without timezone', () {
      final schema = client.schemaBuilder();
      schema.createTable('events', (table) {
        table.increments('id');
        table.timestamp('created_at', false);
      });
      final sqls = schema.toSQL();

      expect(sqls.length, 1);
      expect(
        sqls[0]['sql'],
        'create table "events" ("id" serial primary key, "created_at" timestamp)',
      );
    });

    // Test 10: createTable with foreign key + onDelete
    test('Test 10: createTable with foreign key', () {
      final schema = client.schemaBuilder();
      schema.createTable('comments', (table) {
        table.increments('id');
        table
            .integer('post_id')
            .references('id')
            .inTable('posts')
            .onDelete('CASCADE');
        table.text('body');
      });
      final sqls = schema.toSQL();

      // JS: 2 statements - CREATE + ALTER TABLE ADD FOREIGN KEY
      expect(sqls.length, 2);
      expect(
        sqls[0]['sql'],
        'create table "comments" ("id" serial primary key, '
        '"post_id" integer, "body" text)',
      );
      expect(
        sqls[1]['sql'],
        'alter table "comments" add constraint "comments_post_id_foreign" '
        'foreign key ("post_id") references "posts" ("id") on delete CASCADE',
      );
    });
  });
}
