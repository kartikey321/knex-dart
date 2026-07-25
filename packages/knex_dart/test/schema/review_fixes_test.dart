/// Regression tests for schema-compiler correctness fixes surfaced by the
/// adversarial knex.js/knex-dart comparison review.
///
/// Focus is on constraints/indexes that were previously *silently dropped* or
/// had user-supplied names *ignored* when declared inside `createTable`.
library;

import 'package:knex_dart/knex_dart.dart';
import 'package:test/test.dart';
import '../mocks/mock_client.dart';
import '../mocks/mysql_mock_client.dart';
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

  group('primary() inside alterTable on SQLite', () {
    // SQLite cannot ADD a primary key to an existing table (no ALTER TABLE
    // ADD CONSTRAINT support). Emitting that SQL would fail at execution
    // time, so this must refuse the same way setNullable/dropNullable do.
    test('throws UnsupportedError instead of emitting invalid SQL', () {
      final schema = SqliteMockClient().schemaBuilder();
      schema.alterTable('memberships', (table) {
        table.primary(['user_id', 'org_id']);
      });
      expect(() => schema.toSQL(), throwsA(isA<UnsupportedError>()));
    });

    test('non-SQLite dialects still emit the ALTER TABLE ADD CONSTRAINT', () {
      final schema = client.schemaBuilder();
      schema.alterTable('memberships', (table) {
        table.primary(['user_id', 'org_id']);
      });
      final pk = stmtContaining(schema.toSQL(), 'primary key');
      expect(pk, contains('add constraint'));
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

  group('dropUnique() SQL per dialect', () {
    // A prior test only asserted that dropUnique() got *recorded* on the
    // TableBuilder, never what SQL the compiler emits for it — a mutation
    // testing pass (dart_mutant) flipped the SQLite branch condition to
    // `false` and nothing failed, which would have shipped `alter table
    // ... drop constraint ...` (unsupported on SQLite; it only supports
    // `drop index`).
    test('SQLite emits DROP INDEX, not ALTER TABLE DROP CONSTRAINT', () {
      final schema = SqliteMockClient().schemaBuilder();
      schema.alterTable('users', (table) {
        table.dropUnique(['email']);
      });
      final sql = schema.toSQL().first['sql'] as String;
      expect(sql, 'drop index "users_email_unique"');
      expect(sql, isNot(contains('alter table')));
    });

    test('MySQL emits ALTER TABLE DROP INDEX', () {
      final schema = MySQLMockClient().schemaBuilder();
      schema.alterTable('users', (table) {
        table.dropUnique(['email']);
      });
      final sql = schema.toSQL().first['sql'] as String;
      expect(sql, contains('alter table `users` drop index `users_email_unique`'));
    });

    test('Postgres emits ALTER TABLE DROP CONSTRAINT', () {
      final schema = client.schemaBuilder();
      schema.alterTable('users', (table) {
        table.dropUnique(['email']);
      });
      final sql = schema.toSQL().first['sql'] as String;
      expect(
        sql,
        contains('alter table "users" drop constraint "users_email_unique"'),
      );
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

  group('turso/d1 are treated as sqlite-family (not Postgres-shaped default)', () {
    // Found by the schema-DDL parity harness: every sqlite-specific branch
    // in schema_compiler.dart and table_builder.dart checked
    // `driverName == 'sqlite' || 'sqlite3'` directly, never the
    // family-aware `_isSqliteLike()` helper that already existed. turso and
    // d1 (both wire-compatible with SQLite) silently fell through to the
    // Postgres-shaped `default` branch everywhere — e.g. dropUnique would
    // have emitted `alter table ... drop constraint ...`, which neither
    // engine supports.
    for (final dialect in ['turso', 'd1']) {
      test('$dialect: dropUnique emits DROP INDEX, not ALTER TABLE DROP CONSTRAINT', () {
        final schema = KnexQuery.forClient(dialect).schemaBuilder();
        schema.alterTable('users', (table) {
          table.dropUnique(['email']);
        });
        final sql = schema.toSQL().first['sql'] as String;
        expect(sql, contains('drop index'));
        expect(sql, isNot(contains('alter table')));
      });

      test('$dialect: increments() uses autoincrement, not serial', () {
        final schema = KnexQuery.forClient(dialect).schemaBuilder();
        schema.createTable('users', (table) {
          table.increments('id');
        });
        final sql = schema.toSQL().first['sql'] as String;
        expect(sql, contains('autoincrement'));
        expect(sql, isNot(contains('serial')));
      });

      test('$dialect: alterTable().primary() refuses instead of emitting invalid SQL', () {
        final schema = KnexQuery.forClient(dialect).schemaBuilder();
        schema.alterTable('memberships', (table) {
          table.primary(['user_id', 'org_id']);
        });
        expect(() => schema.toSQL(), throwsA(isA<UnsupportedError>()));
      });
    }
  });

  group('foreign keys declared inside createTable on SQLite-family', () {
    // Found by the schema-DDL parity harness: SQLite (and turso/d1) cannot
    // ALTER TABLE ADD CONSTRAINT for foreign keys, so the deferred-ALTER
    // path silently dropped them (`continue;` with no replacement) instead
    // of folding them into the CREATE TABLE statement the way knex.js does.
    // The FK was declared but never appeared anywhere in the compiled SQL —
    // silent data loss, same bug family as the primary()-on-createTable fix.
    test('column-level .references().inTable() is folded inline, not dropped', () {
      final schema = SqliteMockClient().schemaBuilder();
      schema.createTable('orders', (table) {
        table.increments('id');
        table.integer('user_id').references('id').inTable('users');
      });
      final sql = schema.toSQL().first['sql'] as String;
      expect(sql, contains('foreign key'));
      expect(sql, contains('references "users" ("id")'));
      expect(schema.toSQL().length, 1, reason: 'no separate ALTER statement');
    });

    test('fluent table.foreign().references().inTable() is folded inline', () {
      final schema = SqliteMockClient().schemaBuilder();
      schema.createTable('orders', (table) {
        table.increments('id');
        table.integer('user_id');
        table.foreign('user_id').references('id').inTable('users').onDelete('cascade');
      });
      final sql = schema.toSQL().first['sql'] as String;
      expect(sql, contains('foreign key'));
      expect(sql, contains('references "users" ("id")'));
      expect(sql, contains('on delete CASCADE'));
      expect(schema.toSQL().length, 1, reason: 'no separate ALTER statement');
    });

    test('non-SQLite dialects still emit a separate ALTER TABLE for the FK', () {
      final schema = client.schemaBuilder(); // Postgres
      schema.createTable('orders', (table) {
        table.increments('id');
        table.integer('user_id').references('id').inTable('users');
      });
      final sqls = schema.toSQL();
      expect(sqls.length, 2);
      expect(sqls[1]['sql'], contains('alter table "orders" add constraint'));
    });
  });

  group('dropPrimary()/dropForeign() on an existing SQLite table', () {
    // Same class of bug as alterTable().primary(): SQLite cannot ALTER
    // TABLE DROP CONSTRAINT either. Previously these fell through to the
    // Postgres-shaped branch and emitted invalid SQL instead of refusing.
    test('dropPrimary throws UnsupportedError', () {
      final schema = SqliteMockClient().schemaBuilder();
      schema.alterTable('memberships', (table) {
        table.dropPrimary();
      });
      expect(() => schema.toSQL(), throwsA(isA<UnsupportedError>()));
    });

    test('dropForeign throws UnsupportedError', () {
      final schema = SqliteMockClient().schemaBuilder();
      schema.alterTable('orders', (table) {
        table.dropForeign(['user_id']);
      });
      expect(() => schema.toSQL(), throwsA(isA<UnsupportedError>()));
    });

    test('alterTable().foreign() throws UnsupportedError', () {
      final schema = SqliteMockClient().schemaBuilder();
      schema.alterTable('orders', (table) {
        table.foreign('user_id').references('id').inTable('users');
      });
      expect(() => schema.toSQL(), throwsA(isA<UnsupportedError>()));
    });
  });

  group('Redshift increments()/bigIncrements() use IDENTITY, not SERIAL', () {
    // Redshift has no SERIAL type (it's a Postgres-only convenience type
    // backed by a sequence, which Redshift doesn't support the same way).
    // Falling through to the shared Postgres/default branch would have
    // emitted SERIAL, which Redshift rejects.
    test('increments() emits IDENTITY(1,1)', () {
      final schema = KnexQuery.forClient('redshift').schemaBuilder();
      schema.createTable('users', (table) {
        table.increments('id');
      });
      final sql = schema.toSQL().first['sql'] as String;
      expect(sql, contains('identity(1,1)'));
      expect(sql, isNot(contains('serial')));
    });

    test('bigIncrements() emits bigint IDENTITY(1,1)', () {
      final schema = KnexQuery.forClient('redshift').schemaBuilder();
      schema.createTable('events', (table) {
        table.bigIncrements('id');
      });
      final sql = schema.toSQL().first['sql'] as String;
      expect(sql, contains('bigint identity(1,1)'));
      expect(sql, isNot(contains('bigserial')));
    });

    test('cockroachdb is unaffected — still emits serial', () {
      final schema = KnexQuery.forClient('cockroachdb').schemaBuilder();
      schema.createTable('users', (table) {
        table.increments('id');
      });
      final sql = schema.toSQL().first['sql'] as String;
      expect(sql, contains('serial'));
    });
  });
}
