/// Dialect-agnostic schema DDL corpus for the differential parity harness.
///
/// Sibling to parity_cases.dart (query builder). Split out because schema
/// DDL's `.toSQL()` returns a LIST of statements (not one) on both sides —
/// see schema_parity_test.dart for the comparison shape.
///
/// Each entry mirrors — by the SAME id — a builder in
/// `tool/parity/run_js_schema.mjs`. To add coverage, add a case here AND
/// there under the same id, then regenerate the fixture.
library;

import 'package:knex_dart/knex_dart.dart';

SchemaBuilder _sb(String dialect) => KnexQuery.forClient(dialect).schemaBuilder();

typedef SchemaParityCase = List<Map<String, dynamic>> Function(String dialect);

final Map<String, SchemaParityCase> schemaParityCases = {
  'schema/create-table-basic': (d) => _sb(d).createTable('users', (t) {
        t.increments('id');
        t.string('email');
        t.integer('age');
      }).toSQL(),

  'schema/create-table-primary-composite': (d) => _sb(d).createTable('memberships', (t) {
        t.integer('user_id');
        t.integer('org_id');
        t.primary(['user_id', 'org_id']);
      }).toSQL(),

  'schema/create-table-primary-named': (d) => _sb(d).createTable('memberships', (t) {
        t.integer('user_id');
        t.integer('org_id');
        t.primary(['user_id', 'org_id'], 'membership_pk');
      }).toSQL(),

  'schema/create-table-unique-column': (d) => _sb(d).createTable('users', (t) {
        t.increments('id');
        t.string('email').unique();
      }).toSQL(),

  'schema/create-table-unique-named': (d) => _sb(d).createTable('users', (t) {
        t.increments('id');
        t.string('email');
        t.unique(['email'], 'uq_users_email');
      }).toSQL(),

  'schema/create-table-foreign-column': (d) => _sb(d).createTable('orders', (t) {
        t.increments('id');
        t.integer('user_id').references('id').inTable('users');
      }).toSQL(),

  'schema/create-table-foreign-fluent-cascade': (d) => _sb(d).createTable('orders', (t) {
        t.increments('id');
        t.integer('user_id');
        t.foreign('user_id').references('id').inTable('users').onDelete('cascade');
      }).toSQL(),

  'schema/create-table-foreign-onupdate': (d) => _sb(d).createTable('orders', (t) {
        t.increments('id');
        t.integer('user_id');
        t.foreign('user_id').references('id').inTable('users').onUpdate('cascade');
      }).toSQL(),

  'schema/alter-table-add-column': (d) => _sb(d).alterTable('users', (t) {
        t.string('nickname');
      }).toSQL(),

  'schema/alter-table-drop-column': (d) => _sb(d).alterTable('users', (t) {
        t.dropColumn('nickname');
      }).toSQL(),

  'schema/alter-table-rename-column': (d) => _sb(d).alterTable('users', (t) {
        t.renameColumn('nickname', 'nick');
      }).toSQL(),

  'schema/alter-table-add-unique': (d) => _sb(d).alterTable('users', (t) {
        t.unique(['email']);
      }).toSQL(),

  'schema/alter-table-add-unique-named': (d) => _sb(d).alterTable('users', (t) {
        t.unique(['email'], 'uq_users_email');
      }).toSQL(),

  'schema/alter-table-add-index': (d) => _sb(d).alterTable('users', (t) {
        t.index(['email']);
      }).toSQL(),

  'schema/alter-table-add-index-named': (d) => _sb(d).alterTable('users', (t) {
        t.index(['email'], 'idx_users_email');
      }).toSQL(),

  'schema/alter-table-drop-unique': (d) => _sb(d).alterTable('users', (t) {
        t.dropUnique(['email']);
      }).toSQL(),

  'schema/alter-table-drop-unique-named': (d) => _sb(d).alterTable('users', (t) {
        t.dropUnique(['email'], 'uq_users_email');
      }).toSQL(),

  'schema/alter-table-drop-index': (d) => _sb(d).alterTable('users', (t) {
        t.dropIndex(['email']);
      }).toSQL(),

  'schema/alter-table-drop-index-named': (d) => _sb(d).alterTable('users', (t) {
        t.dropIndex(['email'], 'idx_users_email');
      }).toSQL(),

  'schema/alter-table-drop-primary': (d) => _sb(d).alterTable('memberships', (t) {
        t.dropPrimary();
      }).toSQL(),

  'schema/alter-table-drop-foreign': (d) => _sb(d).alterTable('orders', (t) {
        t.dropForeign(['user_id']);
      }).toSQL(),

  'schema/alter-table-primary': (d) => _sb(d).alterTable('memberships', (t) {
        t.primary(['user_id', 'org_id']);
      }).toSQL(),

  'schema/alter-table-foreign': (d) => _sb(d).alterTable('orders', (t) {
        t.foreign('user_id').references('id').inTable('users');
      }).toSQL(),

  'schema/alter-table-set-nullable': (d) => _sb(d).alterTable('users', (t) {
        t.setNullable('email');
      }).toSQL(),

  'schema/alter-table-drop-nullable': (d) => _sb(d).alterTable('users', (t) {
        t.dropNullable('email');
      }).toSQL(),

  'schema/drop-table': (d) => _sb(d).dropTable('users').toSQL(),
  'schema/drop-table-if-exists': (d) => _sb(d).dropTableIfExists('users').toSQL(),
  'schema/rename-table': (d) => _sb(d).renameTable('users', 'accounts').toSQL(),
};
