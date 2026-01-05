import 'package:test/test.dart';
import 'package:knex_dart/src/raw.dart';
import 'package:knex_dart/src/query/sql_string.dart';
import 'package:knex_dart/src/util/knex_exception.dart';
import 'mocks/mock_client.dart';

void main() {
  late MockClient client;

  setUp(() {
    client = MockClient();
  });

  group('Raw - toSQL() method', () {
    test('Test 1: Simple SQL (matches JS output)', () {
      // JS: {"method": "raw", "sql": "SELECT 1", "bindings": []}
      final raw = Raw(client).set('SELECT 1');
      final sql = raw.toSQL();

      expect(sql, isA<SqlString>());
      expect(sql.sql, 'SELECT 1');
      expect(sql.bindings, []);
      expect(sql.method, 'raw');
    });

    test('Test 2: With bindings (matches JS output)', () {
      // JS: {"method": "raw", "sql": "SELECT * FROM users WHERE id = $1", "bindings": [123]}
      // NOW WITH FORMATTER: ? is replaced with $1
      final raw = Raw(client).set('SELECT * FROM users WHERE id = ?', [123]);
      final sql = raw.toSQL();

      expect(sql.sql, 'SELECT * FROM users WHERE id = \$1'); // Formatted!
      expect(sql.bindings, [123]);
      expect(sql.method, 'raw');
    });

    test('Test 3: With wrap (matches JS output)', () {
      // JS: {"method": "raw", "sql": "(SELECT 1)", "bindings": []}
      final raw = Raw(client).set('SELECT 1').wrap('(', ')');
      final sql = raw.toSQL();

      expect(sql.sql, '(SELECT 1)');
      expect(sql.bindings, []);
      expect(sql.method, 'raw');
    });

    test('Test 4: Multiple calls are idempotent (matches JS output)', () {
      // JS: Both calls return same output
      final raw = Raw(client).set('SELECT 1').wrap('(', ')');
      final sql1 = raw.toSQL();
      final sql2 = raw.toSQL();

      expect(sql1.sql, sql2.sql);
      expect(sql1.bindings, sql2.bindings);
      expect(sql1.method, sql2.method);

      // Both should be (SELECT 1)
      expect(sql1.sql, '(SELECT 1)');
      expect(sql2.sql, '(SELECT 1)');
    });

    test('Test 5: Empty wrap does not modify SQL (matches JS output)', () {
      // JS: {"method": "raw", "sql": "SELECT 1", "bindings": []}
      final raw = Raw(client).set('SELECT 1').wrap('', '');
      final sql = raw.toSQL();

      expect(sql.sql, 'SELECT 1');
    });

    test('Test 6: Null in bindings throws exception (JS behavior)', () {
      // JS would detect undefined in bindings and throw
      // Dart: null ≈ JS undefined
      final raw = Raw(client).set('SELECT ?', [null]);

      expect(
        () => raw.toSQL(),
        throwsA(
          isA<KnexException>().having(
            (e) => e.message,
            'message',
            contains('Undefined binding(s)'),
          ),
        ),
      );
    });

    test('Test 6b: Null in nested array throws exception', () {
      final raw = Raw(client).set('SELECT ?, ?', [
        123,
        [null],
      ]);

      expect(() => raw.toSQL(), throwsA(isA<KnexException>()));
    });

    test('Test 6c: Valid bindings pass validation', () {
      final raw = Raw(client).set('SELECT ?, ?, ?', [123, 'test', true]);
      final sql = raw.toSQL();

      expect(sql.bindings, [123, 'test', true]);
    });

    test('Wrap before and after independently', () {
      final raw = Raw(client).set('SELECT 1');

      raw.wrap('BEGIN ', '');
      expect(raw.toSQL().sql, 'BEGIN SELECT 1');

      raw.wrap('', ' END');
      expect(raw.toSQL().sql, 'SELECT 1 END');
    });

    test('Complex wrap with special characters', () {
      final raw = Raw(client).set('SELECT 1').wrap('/* comment */ ', ' -- end');
      final sql = raw.toSQL();

      expect(sql.sql, '/* comment */ SELECT 1 -- end');
    });
  });
}
