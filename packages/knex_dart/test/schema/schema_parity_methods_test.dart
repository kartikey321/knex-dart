library;

import 'package:test/test.dart';
import '../mocks/mock_client.dart';

void main() {
  group('SchemaBuilder parity methods', () {
    test('Postgres schema and extension methods compile', () {
      final client = MockClient(driverName: 'pg');
      final sqls = client
          .schemaBuilder()
          .createSchema('analytics')
          .createSchemaIfNotExists('audit')
          .dropSchema('old_schema', true)
          .dropSchemaIfExists('temp_schema', false)
          .createExtension('pg_trgm')
          .createExtensionIfNotExists('uuid-ossp')
          .dropExtension('old_ext')
          .dropExtensionIfExists('legacy_ext')
          .toSQL();

      expect(sqls.map((s) => s['sql']), [
        'create schema "analytics"',
        'create schema if not exists "audit"',
        'drop schema "old_schema" cascade',
        'drop schema if exists "temp_schema"',
        'create extension "pg_trgm"',
        'create extension if not exists "uuid-ossp"',
        'drop extension "old_ext"',
        'drop extension if exists "legacy_ext"',
      ]);
    });

    test('createSchema throws on non-Postgres dialect', () {
      final client = MockClient(driverName: 'sqlite3');
      expect(
        () => client.schemaBuilder().createSchema('x').toSQL(),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('createTableLike compiles for Postgres', () {
      final client = MockClient(driverName: 'pg');
      final sqls = client
          .schemaBuilder()
          .createTableLike('users_copy', 'users')
          .toSQL();

      expect(
        sqls.first['sql'],
        'create table "users_copy" (like "users" including all)',
      );
    });

    test('createTableLike compiles for MySQL', () {
      final client = MockClient(driverName: 'mysql');
      final sqls = client
          .schemaBuilder()
          .createTableLike('users_copy', 'users')
          .toSQL();

      expect(sqls.first['sql'], 'create table `users_copy` like `users`');
    });

    test('createTableLike compiles for SQLite', () {
      final client = MockClient(driverName: 'sqlite3');
      final sqls = client
          .schemaBuilder()
          .createTableLike('users_copy', 'users')
          .toSQL();

      expect(
        sqls.first['sql'],
        'create table "users_copy" as select * from "users" where 0=1',
      );
    });

    test('createTableLike compiles for MSSQL', () {
      final client = MockClient(driverName: 'mssql');
      final sqls = client
          .schemaBuilder()
          .createTableLike('users_copy', 'users')
          .toSQL();

      expect(
        sqls.first['sql'],
        'SELECT * INTO "users_copy" FROM "users" WHERE 0=1',
      );
    });

    test('createTableLike compiles for DuckDB', () {
      final client = MockClient(driverName: 'duckdb');
      final sqls = client
          .schemaBuilder()
          .createTableLike('users_copy', 'users')
          .toSQL();

      expect(
        sqls.first['sql'],
        'create table "users_copy" as select * from "users" where 0=1',
      );
    });

    test('createTableLike supports callback columns for Postgres', () {
      final client = MockClient(driverName: 'pg');
      final sqls = client.schemaBuilder().createTableLike(
        'users_copy',
        'users',
        (t) {
          t.string('nickname');
        },
      ).toSQL();

      expect(
        sqls.first['sql'],
        'create table "users_copy" (like "users" including all, "nickname" varchar(255))',
      );
    });

    test('createTableLike supports callback columns for MySQL', () {
      final client = MockClient(driverName: 'mysql');
      final sqls = client.schemaBuilder().createTableLike(
        'users_copy',
        'users',
        (t) {
          t.string('nickname');
        },
      ).toSQL();

      expect(sqls.map((s) => s['sql']), [
        'create table `users_copy` like `users`',
        'alter table `users_copy` add column `nickname` varchar(255)',
      ]);
    });

    test('view methods compile with String definition', () {
      final client = MockClient(driverName: 'pg');
      final sqls = client
          .schemaBuilder()
          .createView('v_users', 'select * from users')
          .createViewOrReplace(
            'v_active',
            'select * from users where active = true',
          )
          .alterView('v_users', 'select id, email from users')
          .dropView('v_old')
          .dropViewIfExists('v_old_if_exists')
          .renameView('v_users', 'v_people')
          .toSQL();

      expect(sqls.map((s) => s['sql']), [
        'create view "v_users" as select * from users',
        'create or replace view "v_active" as select * from users where active = true',
        'create or replace view "v_users" as select id, email from users',
        'drop view "v_old"',
        'drop view if exists "v_old_if_exists"',
        'alter view "v_users" rename to "v_people"',
      ]);
    });

    test('view methods accept Raw and preserve bindings', () {
      final client = MockClient(driverName: 'pg');
      final definition = client.raw('select * from users where id = ?', [42]);
      final sqls = client
          .schemaBuilder()
          .createView('v_user_42', definition)
          .toSQL();

      expect(
        sqls.first['sql'],
        'create view "v_user_42" as select * from users where id = \$1',
      );
      expect(sqls.first['bindings'], [42]);
    });

    test('materialized view methods compile for Postgres', () {
      final client = MockClient(driverName: 'pg');
      final sqls = client
          .schemaBuilder()
          .createMaterializedView('mv_users', 'select * from users')
          .refreshMaterializedView('mv_users', true)
          .dropMaterializedView('mv_users')
          .dropMaterializedViewIfExists('mv_users_old')
          .toSQL();

      expect(sqls.map((s) => s['sql']), [
        'create materialized view "mv_users" as select * from users',
        'refresh materialized view concurrently "mv_users"',
        'drop materialized view "mv_users"',
        'drop materialized view if exists "mv_users_old"',
      ]);
    });

    test('createViewOrReplace on SQLite compiles as drop + create', () {
      final client = MockClient(driverName: 'sqlite3');
      final sqls = client
          .schemaBuilder()
          .createViewOrReplace('v_users', 'select * from users')
          .toSQL();

      expect(sqls.map((s) => s['sql']), [
        'drop view if exists "v_users"',
        'create view "v_users" as select * from users',
      ]);
    });

    test('renameView compiles for MSSQL using sp_rename', () {
      final client = MockClient(driverName: 'mssql');
      final sqls = client
          .schemaBuilder()
          .withSchema('dbo')
          .renameView('old_view', 'new_view')
          .toSQL();

      expect(sqls.first['sql'], 'exec sp_rename ?, ?');
      expect(sqls.first['bindings'], ['dbo.old_view', 'new_view']);
    });

    test('renameTable compiles for MySQL using rename table', () {
      final client = MockClient(driverName: 'mysql');
      final sqls = client
          .schemaBuilder()
          .renameTable('users', 'people')
          .toSQL();

      expect(sqls.first['sql'], 'rename table `users` to `people`');
    });

    test('renameTable compiles for MSSQL using sp_rename', () {
      final client = MockClient(driverName: 'mssql');
      final sqls = client
          .schemaBuilder()
          .withSchema('dbo')
          .renameTable('users', 'people')
          .toSQL();

      expect(sqls.first['sql'], 'exec sp_rename ?, ?');
      expect(sqls.first['bindings'], ['dbo.users', 'people']);
    });

    test('renameColumn compiles for MSSQL using sp_rename with bindings', () {
      final client = MockClient(driverName: 'mssql');
      final sqls = client
          .schemaBuilder()
          .withSchema('myschema')
          .alterTable('users', (t) => t.renameColumn('name', 'full_name'))
          .toSQL();

      expect(sqls.first['sql'], 'exec sp_rename ?, ?, ?');
      expect(sqls.first['bindings'], ['myschema.users.name', 'full_name', 'COLUMN']);
    });

    test('renameColumn compiles for MSSQL without schema uses table.column', () {
      final client = MockClient(driverName: 'mssql');
      final sqls = client
          .schemaBuilder()
          .alterTable('users', (t) => t.renameColumn('name', 'full_name'))
          .toSQL();

      expect(sqls.first['sql'], 'exec sp_rename ?, ?, ?');
      expect(sqls.first['bindings'], ['users.name', 'full_name', 'COLUMN']);
    });

    test('drop-if-exists compiles with MSSQL object_id guards', () {
      final client = MockClient(driverName: 'mssql');
      final sqls = client
          .schemaBuilder()
          .withSchema('dbo')
          .dropTableIfExists('users')
          .dropViewIfExists('v_users')
          .toSQL();

      expect(sqls.map((s) => s['sql']), [
        'if object_id(\'"dbo"."users"\', \'U\') is not null DROP TABLE "dbo"."users"',
        'if object_id(\'"dbo"."v_users"\', \'V\') is not null DROP VIEW "dbo"."v_users"',
      ]);
    });

    test('raw appends literal SQL + bindings in sequence', () {
      final client = MockClient(driverName: 'pg');
      final sqls = client
          .schemaBuilder()
          .raw('create index idx_users_email on users (email)')
          .raw('vacuum ?', ['users'])
          .toSQL();

      expect(sqls[0]['sql'], 'create index idx_users_email on users (email)');
      expect(sqls[0]['bindings'], isEmpty);
      expect(sqls[1]['sql'], 'vacuum ?');
      expect(sqls[1]['bindings'], ['users']);
    });
  });
}
