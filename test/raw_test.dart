/// Consolidated Raw query tests with JS parity
///
/// JS Baseline: knex-js/test/js_comparison/querycompiler_step13_raw.js
/// Run: dart test test/raw_test.dart
import 'package:test/test.dart';
import 'mocks/mock_client.dart';

void main() {
  late MockClient client;

  setUp(() {
    client = MockClient();
  });

  group('Raw - Core', () {
    test('simple SQL without bindings', () {
      final raw = client.raw('SELECT 1');
      final sql = raw.toSQL();
      expect(sql.sql, 'SELECT 1');
      expect(sql.bindings, []);
    });

    test('SQL with positional bindings', () {
      final raw = client.raw('SELECT * FROM users WHERE id = ?', [42]);
      final sql = raw.toSQL();
      expect(sql.sql, 'SELECT * FROM users WHERE id = \$1');
      expect(sql.bindings, [42]);
    });

    test('SQL with multiple bindings', () {
      final raw = client.raw(
        'SELECT * FROM users WHERE age > ? AND status = ?',
        [18, 'active'],
      );
      final sql = raw.toSQL();
      expect(sql.sql, 'SELECT * FROM users WHERE age > \$1 AND status = \$2');
      expect(sql.bindings, [18, 'active']);
    });

    test('SQL with identifier wrapping (??)', () {
      final raw = client.raw('SELECT * FROM ??', ['users']);
      final sql = raw.toSQL();
      expect(sql.sql, 'SELECT * FROM "users"');
      expect(sql.bindings, []);
    });

    test('wrap() adds prefix and suffix', () {
      final raw = client.raw('SELECT 1').wrap('(', ')');
      final sql = raw.toSQL();
      expect(sql.sql, '(SELECT 1)');
    });
  });

  group('Raw - QueryBuilder Integration', () {
    test('where with raw SQL condition', () {
      final sql = client
          .queryBuilder()
          .table('users')
          .where(client.raw('age > ? AND status = ?', [18, 'active']))
          .toSQL();
      expect(sql.sql, 'select * from "users" where age > \$1 AND status = \$2');
      expect(sql.bindings, [18, 'active']);
    });

    test('select with raw column', () {
      final sql = client.queryBuilder().table('users').select([
        client.raw('count(*) as total'),
      ]).toSQL();
      expect(sql.sql, 'select count(*) as total from "users"');
    });

    test('raw in where with operator', () {
      final sql = client
          .queryBuilder()
          .table('orders')
          .where('total', '>', client.raw('?', [100]))
          .toSQL();
      // When Raw is used as a value, the value clause should handle it
      expect(sql.sql, contains('"total"'));
      expect(sql.sql, contains('from "orders"'));
    });
  });
}
