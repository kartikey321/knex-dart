/// Regression tests for schema-compiler correctness fixes surfaced by the
/// adversarial knex.js/knex-dart comparison review.
///
/// Focus is on constraints/indexes that were previously *silently dropped* or
/// had user-supplied names *ignored* when declared inside `createTable`.
library;

import 'package:test/test.dart';
import '../mocks/mock_client.dart';
import '../mocks/sqlite_mock_client.dart';

void main() {
  late MockClient client; // Postgres dialect

  setUp(() {
    client = MockClient();
  });

  String? stmtContaining(List<Map<String, dynamic>> sqls, String needle) {
    for (final s in sqls) {
      final sql = s['sql'] as String;
      if (sql.contains(needle)) return sql;
    }
    return null;
  }

  group('primary() inside createTable', () {
    // Previously this emitted no SQL at all — the primary key was lost. Same
    // bug family as table.index()/table.unique() inside createTable.
    test('folds the PRIMARY KEY inline into CREATE TABLE (single statement)', () {
      final schema = client.schemaBuilder();
      schema.createTable('memberships', (table) {
        table.integer('user_id');
        table.integer('org_id');
        table.primary(['user_id', 'org_id']);
      });
      final sqls = schema.toSQL();

      // Inline (not a separate ALTER) — SQLite cannot ADD a PK after creation.
      expect(sqls.length, 1, reason: 'primary() must not be a silent no-op');
      expect(
        sqls.first['sql'],
        'create table "memberships" ("user_id" integer, "org_id" integer, '
        'constraint "memberships_pkey" primary key ("user_id", "org_id"))',
      );
    });

    test('SQLite gets the key inline, never ALTER TABLE ADD CONSTRAINT', () {
      // SQLite cannot add a primary key after table creation, so a deferred
      // ALTER would make the whole migration fail.
      final schema = SqliteMockClient().schemaBuilder();
      schema.createTable('memberships', (table) {
        table.integer('user_id');
        table.integer('org_id');
        table.primary(['user_id', 'org_id'], 'membership_pk');
      });
      final sqls = schema.toSQL();

      expect(sqls.length, 1);
      final sql = sqls.first['sql'] as String;
      expect(sql, contains('primary key ('));
      expect(sql, isNot(contains('alter table')));
      expect(sql, isNot(contains('add constraint')));
    });

    test('honours an explicit constraint name', () {
      final schema = client.schemaBuilder();
      schema.createTable('memberships', (table) {
        table.integer('user_id');
        table.integer('org_id');
        table.primary(['user_id', 'org_id'], 'membership_pk');
      });
      final pk = stmtContaining(schema.toSQL(), 'primary key');
      expect(pk, contains('constraint "membership_pk"'));
    });
  });

  group('unique() honours a custom constraint name', () {
    // Previously args[1] (the name) was ignored and a name was always derived.
    test('inside createTable', () {
      final schema = client.schemaBuilder();
      schema.createTable('users', (table) {
        table.string('email');
        table.unique(['email'], 'uq_users_email');
      });
      final uq = stmtContaining(schema.toSQL(), 'unique');
      expect(uq, contains('constraint "uq_users_email"'));
    });

    test('inside alterTable', () {
      final schema = client.schemaBuilder();
      schema.alterTable('users', (table) {
        table.unique(['email'], 'uq_users_email');
      });
      final uq = stmtContaining(schema.toSQL(), 'unique');
      expect(uq, contains('constraint "uq_users_email"'));
    });
  });

  group('dropIndex without an explicit name', () {
    // Previously a no-op (nothing emitted). Now derives the same name that
    // index creation would produce.
    test('derives the conventional index name from the columns', () {
      final schema = client.schemaBuilder();
      schema.alterTable('users', (table) {
        table.dropIndex(['email']);
      });
      final sqls = schema.toSQL();
      expect(sqls, isNotEmpty, reason: 'dropIndex must not be a silent no-op');
      expect(sqls.first['sql'], 'drop index "users_email_index"');
    });

    test('still respects an explicit index name', () {
      final schema = client.schemaBuilder();
      schema.alterTable('users', (table) {
        table.dropIndex(['email'], 'custom_idx');
      });
      expect(schema.toSQL().first['sql'], 'drop index "custom_idx"');
    });
  });

  group('enum values are escaped', () {
    // Single quotes in enum values previously broke the SQL (injection risk).
    test("a value containing an apostrophe is doubled", () {
      final schema = client.schemaBuilder();
      schema.createTable('people', (table) {
        table.enu('surname_kind', ["O'Brien", 'Smith']);
      });
      final create = schema.toSQL().first['sql'] as String;
      expect(create, contains("'O''Brien'"));
      expect(create, contains("'Smith'"));
    });
  });
}
