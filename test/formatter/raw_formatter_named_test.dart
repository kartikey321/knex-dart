import 'package:test/test.dart';
import 'package:knex_dart/src/formatter/raw_formatter.dart';
import '../../test/mocks/mock_client.dart';

void main() {
  late MockClient client;

  setUp(() {
    client = MockClient();
  });

  group('RawFormatter - Named Bindings (JS Comparison)', () {
    test('Test 1: Single :key binding', () {
      // JS: {"sql": "SELECT * FROM users WHERE id = $1", "bindings": [123]}
      final result = RawFormatter.replaceNamedBindings(
        'SELECT * FROM users WHERE id = :id',
        {'id': 123},
        client,
      );

      expect(result.sql, 'SELECT * FROM users WHERE id = \$1');
      expect(result.bindings, [123]);
    });

    test('Test 2: Multiple :key bindings', () {
      // JS: {"sql": "SELECT * FROM users WHERE id = $1 AND status = $2", "bindings": [123, "active"]}
      final result = RawFormatter.replaceNamedBindings(
        'SELECT * FROM users WHERE id = :id AND status = :status',
        {'id': 123, 'status': 'active'},
        client,
      );

      expect(result.sql, 'SELECT * FROM users WHERE id = \$1 AND status = \$2');
      expect(result.bindings, [123, 'active']);
    });

    test('Test 3: :key: identifier binding', () {
      // JS: {"sql": "SELECT * FROM \"users\"", "bindings": []}
      final result = RawFormatter.replaceNamedBindings(
        'SELECT * FROM :table:',
        {'table': 'users'},
        client,
      );

      expect(result.sql, 'SELECT * FROM "users"');
      expect(result.bindings, []);
    });

    test('Test 4: Mixed :key and :key:', () {
      // JS: {"sql": "SELECT \"name\" FROM \"users\" WHERE id = $1", "bindings": [123]}
      final result = RawFormatter.replaceNamedBindings(
        'SELECT :column: FROM :table: WHERE id = :id',
        {'column': 'name', 'table': 'users', 'id': 123},
        client,
      );

      expect(result.sql, 'SELECT "name" FROM "users" WHERE id = \$1');
      expect(result.bindings, [123]);
    });

    test('Test 5: Escaped \\:key becomes literal :key', () {
      // JS: {"sql": "SELECT * FROM users WHERE email = :email", "bindings": []}
      final result = RawFormatter.replaceNamedBindings(
        r'SELECT * FROM users WHERE email = \:email',
        {},
        client,
      );

      expect(result.sql, 'SELECT * FROM users WHERE email = :email');
      expect(result.bindings, []);
    });

    test('Test 6: :key: before ::cast (value binding)', () {
      // JS: {"sql": "SELECT $1::jsonb FROM users", "bindings": ["data"]}
      final result = RawFormatter.replaceNamedBindings(
        'SELECT :ns::jsonb FROM users',
        {'ns': 'data'},
        client,
      );

      expect(result.sql, 'SELECT \$1::jsonb FROM users');
      expect(result.bindings, ['data']);
    });

    test('Test 7: Complex mixed', () {
      // JS: {"sql": "INSERT INTO \"users\" (\"name\", \"email\") VALUES ($1, $2)", "bindings": ["John", "john@example.com"]}
      final result = RawFormatter.replaceNamedBindings(
        'INSERT INTO :table: (:col1:, :col2:) VALUES (:val1, :val2)',
        {
          'table': 'users',
          'col1': 'name',
          'col2': 'email',
          'val1': 'John',
          'val2': 'john@example.com',
        },
        client,
      );

      expect(
        result.sql,
        'INSERT INTO "users" ("name", "email") VALUES (\$1, \$2)',
      );
      expect(result.bindings, ['John', 'john@example.com']);
    });

    test('Test 8: Undefined value keeps placeholder', () {
      // JS: {"sql": "SELECT * FROM users WHERE id = :id", "bindings": []}
      final result = RawFormatter.replaceNamedBindings(
        'SELECT * FROM users WHERE id = :id',
        {'name': 'test'}, // id is missing
        client,
      );

      expect(result.sql, 'SELECT * FROM users WHERE id = :id');
      expect(result.bindings, []);
    });
  });
}
