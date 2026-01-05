import 'package:test/test.dart';
import 'package:knex_dart/src/formatter/raw_formatter.dart';
import '../../test/mocks/mock_client.dart';

void main() {
  late MockClient client;

  setUp(() {
    client = MockClient();
  });

  group('RawFormatter - Positional Bindings (JS Comparison)', () {
    test('Test 1: Single ? binding', () {
      // JS: {"sql": "SELECT * FROM users WHERE id = $1", "bindings": [123]}
      final result = RawFormatter.replacePositionalBindings(
        'SELECT * FROM users WHERE id = ?',
        [123],
        client,
      );

      expect(result.sql, 'SELECT * FROM users WHERE id = \$1');
      expect(result.bindings, [123]);
    });

    test('Test 2: Multiple ? bindings', () {
      // JS: {"sql": "SELECT * FROM users WHERE id = $1 AND status = $2", "bindings": [123, "active"]}
      final result = RawFormatter.replacePositionalBindings(
        'SELECT * FROM users WHERE id = ? AND status = ?',
        [123, 'active'],
        client,
      );

      expect(result.sql, 'SELECT * FROM users WHERE id = \$1 AND status = \$2');
      expect(result.bindings, [123, 'active']);
    });

    test('Test 3: ?? identifier binding', () {
      // JS: {"sql": "SELECT * FROM \"users\"", "bindings": []}
      final result = RawFormatter.replacePositionalBindings(
        'SELECT * FROM ??',
        ['users'],
        client,
      );

      expect(result.sql, 'SELECT * FROM "users"');
      expect(result.bindings, []);
    });

    test('Test 4: Mixed ? and ??', () {
      // JS: {"sql": "SELECT \"name\" FROM \"users\" WHERE id = $1", "bindings": [123]}
      final result = RawFormatter.replacePositionalBindings(
        'SELECT ?? FROM ?? WHERE id = ?',
        ['name', 'users', 123],
        client,
      );

      expect(result.sql, 'SELECT "name" FROM "users" WHERE id = \$1');
      expect(result.bindings, [123]);
    });

    test('Test 5: Escaped \\? returns literal ?', () {
      // JS: {"sql": "SELECT * FROM users WHERE email LIKE ?", "bindings": []}
      final result = RawFormatter.replacePositionalBindings(
        r'SELECT * FROM users WHERE email LIKE \?',
        [],
        client,
      );

      expect(result.sql, 'SELECT * FROM users WHERE email LIKE ?');
      expect(result.bindings, []);
    });

    test('Test 6: Multiple types (complex)', () {
      // JS: {"sql": "INSERT INTO \"users\" (\"name\", \"email\") VALUES ($1, $2)", "bindings": ["John", "john@example.com"]}
      final result = RawFormatter.replacePositionalBindings(
        'INSERT INTO ?? (??, ??) VALUES (?, ?)',
        ['users', 'name', 'email', 'John', 'john@example.com'],
        client,
      );

      expect(
        result.sql,
        'INSERT INTO "users" ("name", "email") VALUES (\$1, \$2)',
      );
      expect(result.bindings, ['John', 'john@example.com']);
    });

    test('Test 7: Wrong binding count throws error', () {
      // JS: Caught error: Expected 2 bindings, saw 1
      expect(
        () => RawFormatter.replacePositionalBindings(
          'SELECT ? FROM users',
          [1, 2], // Too many bindings
          client,
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Expected 2 bindings, saw 1'),
          ),
        ),
      );
    });
  });
}
