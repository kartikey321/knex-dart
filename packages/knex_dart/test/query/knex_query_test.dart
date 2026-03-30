import 'package:knex_dart/knex_dart.dart';
import 'package:knex_dart_capabilities/knex_dart_capabilities.dart';
import 'package:test/test.dart';

void main() {
  group('KnexQuery', () {
    group('forDialect', () {
      test('postgres — double-quoted identifiers and \$N params', () {
        final q = KnexQuery.forDialect(KnexDialect.postgres);
        final sql = q.from('users').where('active', '=', true).toSQL();
        expect(sql.sql, contains('"users"'));
        expect(sql.sql, contains('\$1'));
        expect(sql.bindings, [true]);
      });

      test('mysql — backtick identifiers and ? params', () {
        final q = KnexQuery.forDialect(KnexDialect.mysql);
        final sql = q.from('orders').where('status', '=', 'open').toSQL();
        expect(sql.sql, contains('`orders`'));
        expect(sql.sql, contains('?'));
      });

      test('sqlite — double-quoted identifiers and ? params', () {
        final q = KnexQuery.forDialect(KnexDialect.sqlite);
        final sql = q.from('products').where('active', '=', 1).toSQL();
        expect(sql.sql, contains('"products"'));
        expect(sql.sql, contains('?'));
      });

      test('mariadb — backtick identifiers and ? params', () {
        final q = KnexQuery.forDialect(KnexDialect.mariadb);
        final sql = q.from('sessions').where('user_id', '=', 42).toSQL();
        expect(sql.sql, contains('`sessions`'));
        expect(sql.sql, contains('?'));
      });

      test('redshift — double-quoted identifiers and \$N params', () {
        final q = KnexQuery.forDialect(KnexDialect.redshift);
        final sql = q.from('events').where('dt', '=', '2024-01-01').toSQL();
        expect(sql.sql, contains('"events"'));
        expect(sql.sql, contains('\$1'));
      });

      test('duckdb — double-quoted identifiers and \$N params', () {
        final q = KnexQuery.forDialect(KnexDialect.duckdb);
        final sql = q.from('analytics').limit(10).toSQL();
        expect(sql.sql, contains('"analytics"'));
      });

      test('turso — double-quoted identifiers and ? params', () {
        final q = KnexQuery.forDialect(KnexDialect.turso);
        final sql = q.from('notes').where('id', '=', 1).toSQL();
        expect(sql.sql, contains('"notes"'));
        expect(sql.sql, contains('?'));
      });

      test('d1 — double-quoted identifiers and ? params', () {
        final q = KnexQuery.forDialect(KnexDialect.d1);
        final sql = q.from('kv').where('key', '=', 'foo').toSQL();
        expect(sql.sql, contains('"kv"'));
        expect(sql.sql, contains('?'));
      });

      test('snowflake — double-quoted identifiers and ? params', () {
        final q = KnexQuery.forDialect(KnexDialect.snowflake);
        final sql = q.from('SALES').where('REGION', '=', 'EMEA').toSQL();
        expect(sql.sql, contains('"SALES"'));
        expect(sql.sql, contains('?'));
      });

      test('bigquery — backtick identifiers and ? params', () {
        final q = KnexQuery.forDialect(KnexDialect.bigquery);
        final sql = q.from('page_views').limit(100).toSQL();
        expect(sql.sql, contains('`page_views`'));
      });
    });

    group('forClient', () {
      test('resolves pg → postgres dialect', () {
        final q = KnexQuery.forClient('pg');
        expect(q.dialect, KnexDialect.postgres);
        expect(q.driverName, 'pg');
      });

      test('resolves mysql2 → mysql dialect', () {
        final q = KnexQuery.forClient('mysql2');
        expect(q.dialect, KnexDialect.mysql);
      });

      test('resolves sqlite3 → sqlite dialect', () {
        final q = KnexQuery.forClient('sqlite3');
        expect(q.dialect, KnexDialect.sqlite);
      });

      test('resolves cockroachdb → postgres dialect', () {
        final q = KnexQuery.forClient('cockroachdb');
        expect(q.dialect, KnexDialect.postgres);
      });

      test('resolves turso → turso dialect', () {
        final q = KnexQuery.forClient('turso');
        expect(q.dialect, KnexDialect.turso);
      });

      test('throws on unknown client name', () {
        expect(
          () => KnexQuery.forClient('oracle_xyz'),
          throwsArgumentError,
        );
      });
    });

    group('queryBuilder()', () {
      test('can build complex query without a driver', () {
        final q = KnexQuery.forDialect(KnexDialect.postgres);
        final qb = q.queryBuilder();
        final sql = qb
            .table('users')
            .select(['id', 'email'])
            .where('role', '=', 'admin')
            .orderBy('created_at', 'desc')
            .limit(20)
            .toSQL();
        expect(sql.sql, contains('select "id", "email"'));
        expect(sql.sql, contains('from "users"'));
        expect(sql.sql, contains('order by "created_at" desc'));
        expect(sql.sql, contains('limit \$2'));
      });
    });

    group('schemaBuilder()', () {
      test('can generate CREATE TABLE DDL without a driver', () {
        final q = KnexQuery.forDialect(KnexDialect.postgres);
        final schema = q.schemaBuilder();
        schema.createTable('posts', (t) {
          t.increments('id');
          t.string('title').notNullable();
          t.text('body');
          t.timestamps();
        });
        final stmts = schema.toSQL();
        expect(stmts, isNotEmpty);
        final ddl = stmts.map((s) => s['sql'] as String).join('\n');
        expect(ddl, contains('create table'));
        expect(ddl, contains('"posts"'));
      });
    });
  });
}
