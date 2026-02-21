import 'package:knex_dart/src/query/query_builder.dart';
import 'package:test/test.dart';

import '../mocks/mock_client.dart';

void main() {
  final client = MockClient(); // Postgres/SQLite dialect

  group('INTERSECT', () {
    test('intersect() with a single QueryBuilder', () {
      final base = QueryBuilder(
        client,
      ).table('users').select(['name']).where('role', 'admin');
      final other = QueryBuilder(
        client,
      ).table('users').select(['name']).where('active', true);

      final sql = base.intersect([other]).toSQL();

      expect(
        sql.sql,
        r'select "name" from "users" where "role" = $1 '
        r'intersect select "name" from "users" where "active" = $2',
      );
      expect(sql.bindings, ['admin', true]);
    });

    test('intersect() binding offsets are renumbered correctly', () {
      final base = QueryBuilder(client).table('a').select(['id']).where('x', 1);
      final q2 = QueryBuilder(client).table('b').select(['id']).where('y', 2);
      final q3 = QueryBuilder(client).table('c').select(['id']).where('z', 3);

      final sql = base.intersect([q2, q3]).toSQL();

      expect(sql.bindings, [1, 2, 3]);
      expect(sql.sql, contains(r'intersect select "id" from "b"'));
      expect(sql.sql, contains(r'intersect select "id" from "c"'));
    });

    test('intersectAll() preserves duplicates keyword', () {
      final base = QueryBuilder(client).table('users').select(['name']);
      final other = QueryBuilder(client).table('admins').select(['name']);

      final sql = base.intersectAll([other]).toSQL();

      expect(sql.sql, contains('intersect all'));
    });

    test('intersect() with wrap: true wraps subquery in parens', () {
      final base = QueryBuilder(client).table('a').select(['id']);
      final other = QueryBuilder(client).table('b').select(['id']);

      final sql = base.intersect([other], wrap: true).toSQL();

      expect(sql.sql, contains('intersect ('));
    });
  });

  group('EXCEPT', () {
    test('except() with a single QueryBuilder', () {
      final base = QueryBuilder(
        client,
      ).table('users').select(['name']).where('role', 'admin');
      final other = QueryBuilder(
        client,
      ).table('users').select(['name']).where('active', false);

      final sql = base.except([other]).toSQL();

      expect(
        sql.sql,
        r'select "name" from "users" where "role" = $1 '
        r'except select "name" from "users" where "active" = $2',
      );
      expect(sql.bindings, ['admin', false]);
    });

    test('exceptAll() preserves duplicates keyword', () {
      final base = QueryBuilder(client).table('users').select(['name']);
      final other = QueryBuilder(client).table('banned').select(['name']);

      final sql = base.exceptAll([other]).toSQL();

      expect(sql.sql, contains('except all'));
    });

    test('except() with wrap: true wraps subquery in parens', () {
      final base = QueryBuilder(client).table('a').select(['id']);
      final other = QueryBuilder(client).table('b').select(['id']);

      final sql = base.except([other], wrap: true).toSQL();

      expect(sql.sql, contains('except ('));
    });
  });

  group('Chained set operations', () {
    test('UNION then INTERSECT chains correctly', () {
      final base = QueryBuilder(client).table('a').select(['id']);
      final q2 = QueryBuilder(client).table('b').select(['id']);
      final q3 = QueryBuilder(client).table('c').select(['id']);

      final sql = base.union([q2]).intersect([q3]).toSQL();

      expect(sql.sql, contains('union'));
      expect(sql.sql, contains('intersect'));
    });

    test('EXCEPT then UNION ALL chains correctly', () {
      final base = QueryBuilder(client).table('a').select(['id']);
      final q2 = QueryBuilder(client).table('b').select(['id']);
      final q3 = QueryBuilder(client).table('c').select(['id']);

      final sql = base.except([q2]).unionAll([q3]).toSQL();

      expect(sql.sql, contains('except'));
      expect(sql.sql, contains('union all'));
    });
  });
}
