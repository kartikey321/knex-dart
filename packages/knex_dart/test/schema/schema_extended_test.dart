/// Dart parity tests for Extended Schema Builder
///
/// JS Baseline: knex-js/test/js_comparison/querycompiler_step21b_schema_extended.js
/// Run: dart test test/schema/schema_extended_test.dart
library;

import 'package:test/test.dart';
import '../mocks/mock_client.dart';

void main() {
  late MockClient client;

  setUp(() {
    client = MockClient();
  });

  group('JS Parity: Extended Schema (Step 21b)', () {
    // Test 1: createTableIfNotExists
    test('Test 1: createTableIfNotExists', () {
      final schema = client.schemaBuilder();
      schema.createTableIfNotExists('sessions', (table) {
        table.string('id').primary();
        table.json('data');
        table.timestamps();
      });
      final sqls = schema.toSQL();
      // JS: create table if not exists "sessions" (...)
      expect(sqls.length, 1);
      expect(sqls[0]['sql'], contains('create table if not exists "sessions"'));
      expect(sqls[0]['sql'], contains('"id" varchar(255)'));
      expect(sqls[0]['sql'], contains('"data" json'));
    });

    // Test 2: bigIncrements
    test('Test 2: bigIncrements', () {
      final schema = client.schemaBuilder();
      schema.createTable('events', (table) {
        table.bigIncrements('id');
        table.string('name');
      });
      final sqls = schema.toSQL();
      // JS: create table "events" ("id" bigserial primary key, "name" varchar(255))
      expect(sqls.length, 1);
      expect(
        sqls[0]['sql'],
        'create table "events" ("id" bigserial primary key, "name" varchar(255))',
      );
    });

    // Test 3: foreign() fluent builder
    test('Test 3: foreign() fluent builder', () {
      final schema = client.schemaBuilder();
      schema.createTable('orders', (table) {
        table.increments('id');
        table.integer('user_id');
        table.integer('product_id');
        table
            .foreign('user_id')
            .references('id')
            .inTable('users')
            .onDelete('CASCADE');
        table.foreign('product_id').references('id').inTable('products');
      });
      final sqls = schema.toSQL();
      // JS: 3 statements
      expect(sqls.length, 3);
      expect(
        sqls[0]['sql'],
        'create table "orders" ("id" serial primary key, "user_id" integer, "product_id" integer)',
      );
      expect(
        sqls[1]['sql'],
        'alter table "orders" add constraint "orders_user_id_foreign" foreign key ("user_id") references "users" ("id") on delete CASCADE',
      );
      expect(
        sqls[2]['sql'],
        'alter table "orders" add constraint "orders_product_id_foreign" foreign key ("product_id") references "products" ("id")',
      );
    });

    // Test 4: composite unique
    test('Test 4: composite unique', () {
      final schema = client.schemaBuilder();
      schema.alterTable('orders', (table) {
        table.unique(['user_id', 'product_id']);
      });
      final sqls = schema.toSQL();
      // JS: alter table "orders" add constraint "orders_user_id_product_id_unique" unique ("user_id", "product_id")
      expect(sqls.length, 1);
      expect(
        sqls[0]['sql'],
        'alter table "orders" add constraint "orders_user_id_product_id_unique" unique ("user_id", "product_id")',
      );
    });

    // Test 5: drop multiple columns
    test('Test 5: drop multiple columns', () {
      final schema = client.schemaBuilder();
      schema.alterTable('users', (table) {
        table.dropColumn('phone');
        table.dropColumn('fax');
      });
      final sqls = schema.toSQL();
      // JS: 2 separate drop column statements
      expect(sqls.length, 2);
      expect(sqls[0]['sql'], 'alter table "users" drop column "phone"');
      expect(sqls[1]['sql'], 'alter table "users" drop column "fax"');
    });

    // Test 6: renameColumn
    test('Test 6: renameColumn', () {
      final schema = client.schemaBuilder();
      schema.alterTable('users', (table) {
        table.renameColumn('name', 'full_name');
      });
      final sqls = schema.toSQL();
      // JS: alter table "users" rename "name" to "full_name"
      expect(sqls.length, 1);
      expect(
        sqls[0]['sql'],
        'alter table "users" rename "name" to "full_name"',
      );
    });

    // Test 7: dropForeign
    test('Test 7: dropForeign', () {
      final schema = client.schemaBuilder();
      schema.alterTable('orders', (table) {
        table.dropForeign('user_id');
      });
      final sqls = schema.toSQL();
      // JS: alter table "orders" drop constraint "orders_user_id_foreign"
      expect(sqls.length, 1);
      expect(
        sqls[0]['sql'],
        'alter table "orders" drop constraint "orders_user_id_foreign"',
      );
    });

    // Test 8: create index
    test('Test 8: create index', () {
      final schema = client.schemaBuilder();
      schema.alterTable('users', (table) {
        table.index(['email']);
      });
      final sqls = schema.toSQL();
      // JS: create index "users_email_index" on "users" ("email")
      expect(sqls.length, 1);
      expect(
        sqls[0]['sql'],
        'create index "users_email_index" on "users" ("email")',
      );
    });

    // Test 9: dropTimestamps
    test('Test 9: dropTimestamps', () {
      final schema = client.schemaBuilder();
      schema.alterTable('users', (table) {
        table.dropTimestamps();
      });
      final sqls = schema.toSQL();
      // JS: alter table "users" drop column "created_at", drop column "updated_at"
      expect(sqls.length, 1);
      expect(
        sqls[0]['sql'],
        'alter table "users" drop column "created_at", drop column "updated_at"',
      );
    });

    // Test 10: setNullable
    test('Test 10: setNullable', () {
      final schema = client.schemaBuilder();
      schema.alterTable('users', (table) {
        table.setNullable('name');
      });
      final sqls = schema.toSQL();
      // JS: alter table "users" alter column "name" drop not null
      expect(sqls.length, 1);
      expect(
        sqls[0]['sql'],
        'alter table "users" alter column "name" drop not null',
      );
    });

    // Test 11: dropNullable
    test('Test 11: dropNullable', () {
      final schema = client.schemaBuilder();
      schema.alterTable('users', (table) {
        table.dropNullable('name');
      });
      final sqls = schema.toSQL();
      // JS: alter table "users" alter column "name" set not null
      expect(sqls.length, 1);
      expect(
        sqls[0]['sql'],
        'alter table "users" alter column "name" set not null',
      );
    });

    // Test 12: withSchema
    test('Test 12: withSchema', () {
      final schema = client.schemaBuilder();
      schema.withSchema('public').createTable('logs', (table) {
        table.increments('id');
        table.text('message');
      });
      final sqls = schema.toSQL();
      // JS: create table "public"."logs" ("id" serial primary key, "message" text)
      expect(sqls.length, 1);
      expect(
        sqls[0]['sql'],
        'create table "public"."logs" ("id" serial primary key, "message" text)',
      );
    });
  });
}
