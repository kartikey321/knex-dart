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

  group('Redshift refuses index creation/deletion instead of emitting invalid SQL', () {
    // Found by a Codex adversarial review of the schema parity harness: the
    // allowlist had claimed knex-dart "emits standard SQL, which Redshift
    // can be configured to accept" — that was wrong. Redshift genuinely has
    // no CREATE INDEX/DROP INDEX (confirmed against AWS docs and knex.js's
    // own Redshift compiler, which silently no-ops with a console warning
    // rather than compiling this SQL). knex-dart was emitting
    // `create index .../drop index ...` that Redshift would reject at
    // execution time.
    test('alterTable().index() throws UnsupportedError', () {
      final schema = KnexQuery.forClient('redshift').schemaBuilder();
      schema.alterTable('users', (table) {
        table.index(['email']);
      });
      expect(() => schema.toSQL(), throwsA(isA<UnsupportedError>()));
    });

    test('alterTable().dropIndex() throws UnsupportedError', () {
      final schema = KnexQuery.forClient('redshift').schemaBuilder();
      schema.alterTable('users', (table) {
        table.dropIndex(['email']);
      });
      expect(() => schema.toSQL(), throwsA(isA<UnsupportedError>()));
    });

    test('index() declared inside createTable() also throws', () {
      final schema = KnexQuery.forClient('redshift').schemaBuilder();
      schema.createTable('users', (table) {
        table.string('email');
        table.index(['email']);
      });
      expect(() => schema.toSQL(), throwsA(isA<UnsupportedError>()));
    });

    test('postgres is unaffected — still creates the index', () {
      final schema = client.schemaBuilder();
      schema.alterTable('users', (table) {
        table.index(['email']);
      });
      final sql = schema.toSQL().first['sql'] as String;
      expect(sql, contains('create index'));
    });
  });

  group('multiple foreign keys inside createTable on SQLite (Codex review)', () {
    // A Codex adversarial review of the FK-inline-fold fix asked for direct
    // coverage of the shapes it couldn't fully verify: more than one FK on
    // a table, a composite primary key alongside a foreign key, and a
    // column declaring a FK both via the column-level shorthand and the
    // fluent table.foreign() builder. Verified against local knex.js first
    // (all three inline every FK with no dropping); these lock down that
    // knex-dart's independently-fixed inline-fold does the same.
    test('two fluent foreign keys are both folded inline', () {
      final schema = SqliteMockClient().schemaBuilder();
      schema.createTable('t', (table) {
        table.increments('id');
        table.integer('a_id');
        table.integer('b_id');
        table.foreign('a_id').references('id').inTable('a');
        table.foreign('b_id').references('id').inTable('b');
      });
      final sql = schema.toSQL().first['sql'] as String;
      expect(sql, contains('references "a" ("id")'));
      expect(sql, contains('references "b" ("id")'));
      expect('foreign key'.allMatches(sql).length, 2);
      expect(schema.toSQL().length, 1);
    });

    test('composite primary key alongside a foreign key are both folded inline', () {
      final schema = SqliteMockClient().schemaBuilder();
      schema.createTable('t2', (table) {
        table.integer('a_id');
        table.integer('b_id');
        table.integer('c_id');
        table.primary(['a_id', 'b_id']);
        table.foreign('c_id').references('id').inTable('c');
      });
      final sql = schema.toSQL().first['sql'] as String;
      expect(sql, contains('primary key ("a_id", "b_id")'));
      expect(sql, contains('foreign key ("c_id") references "c" ("id")'));
      expect(schema.toSQL().length, 1);
    });

    test('column-level and fluent FK on the same column are both kept (not deduped)', () {
      final schema = SqliteMockClient().schemaBuilder();
      schema.createTable('t3', (table) {
        table.increments('id');
        table.integer('a_id').references('id').inTable('a');
        table.foreign('a_id').references('id').inTable('a2');
      });
      final sql = schema.toSQL().first['sql'] as String;
      expect(sql, contains('references "a" ("id")'));
      expect(sql, contains('references "a2" ("id")'));
      expect('foreign key'.allMatches(sql).length, 2);
    });
  });

  group('alterTable().foreign().onUpdate() (mutation-testing gap)', () {
    // Re-running mutation testing on the fixed schema_compiler.dart found
    // the `alterTable().foreign()` path's onUpdate handling was untested —
    // the parity corpus only ever exercises onDelete for the genuine ALTER
    // TABLE (not inline-fold) foreign() case. Behavior was already correct;
    // this closes the assertion gap.
    test('emits ON UPDATE clause for an existing table', () {
      final schema = client.schemaBuilder();
      schema.alterTable('orders', (table) {
        table.foreign('user_id').references('id').inTable('users').onUpdate('cascade');
      });
      final sql = schema.toSQL().first['sql'] as String;
      expect(sql, contains('on update CASCADE'));
      expect(sql, isNot(contains('on delete')));
    });

    test('emits both ON DELETE and ON UPDATE when both are set', () {
      final schema = client.schemaBuilder();
      schema.alterTable('orders', (table) {
        table.foreign('user_id')
            .references('id')
            .inTable('users')
            .onDelete('cascade')
            .onUpdate('restrict');
      });
      final sql = schema.toSQL().first['sql'] as String;
      expect(sql, contains('on delete CASCADE'));
      expect(sql, contains('on update RESTRICT'));
    });
  });
}
