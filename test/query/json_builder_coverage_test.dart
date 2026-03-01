import 'package:test/test.dart';
import 'package:knex_dart/src/query/json_builder.dart';
import '../mocks/mock_client.dart';

/// Covers the three `or*` variants not tested in json_operators_test.dart.
void main() {
  late MockClient pg;

  setUp(() => pg = MockClient(driverName: 'pg'));

  group('JsonQueryBuilder - or* variants', () {
    test('orWhereJsonPath appends OR condition', () {
      final sql = pg
          .queryBuilder()
          .from('users')
          .whereJsonPath('settings', r'$.theme', '=', 'dark')
          .orWhereJsonPath('settings', r'$.role', '=', 'admin')
          .toSQL();

      expect(sql.sql, contains('or jsonb_path_query_first'));
      expect(sql.bindings, containsAll([r'$.theme', 'dark', r'$.role', 'admin']));
    });

    test('orWhereJsonSupersetOf appends OR @> condition', () {
      final sql = pg
          .queryBuilder()
          .from('users')
          .whereJsonSupersetOf('tags', {'a': 1})
          .orWhereJsonSupersetOf('tags', {'b': 2})
          .toSQL();

      expect(sql.sql, contains('or "tags" @>'));
      expect(sql.bindings, contains('{"b":2}'));
    });

    test('orWhereJsonSupersetOf with pre-encoded string value', () {
      final sql = pg
          .queryBuilder()
          .from('users')
          .orWhereJsonSupersetOf('meta', '{"x":1}')
          .toSQL();

      // Already a string — must not be double-encoded
      expect(sql.bindings, contains('{"x":1}'));
    });

    test('orWhereJsonSubsetOf appends OR <@ condition', () {
      final sql = pg
          .queryBuilder()
          .from('users')
          .whereJsonSubsetOf('tags', {'a': 1})
          .orWhereJsonSubsetOf('tags', {'b': 2})
          .toSQL();

      expect(sql.sql, contains('or "tags" <@'));
      expect(sql.bindings, contains('{"b":2}'));
    });

    test('orWhereJsonSubsetOf with pre-encoded string value', () {
      final sql = pg
          .queryBuilder()
          .from('users')
          .orWhereJsonSubsetOf('meta', '{"y":9}')
          .toSQL();

      expect(sql.bindings, contains('{"y":9}'));
    });
  });
}
