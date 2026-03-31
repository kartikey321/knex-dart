import 'package:test/test.dart';
import 'package:knex_dart/src/raw.dart';
import 'mocks/mock_client.dart';

void main() {
  late MockClient client;

  setUp(() {
    client = MockClient();
  });

  group('Raw - wrap() method', () {
    test('wrap() stores values without modifying SQL immediately', () {
      final raw = Raw(client).set('SELECT 1');

      expect(raw.sql, 'SELECT 1');

      raw.wrap('(', ')');

      // SQL should NOT be modified yet (JS behavior)
      expect(raw.sql, 'SELECT 1');
    });

    test('wrap() returns this for chaining', () {
      final raw = Raw(client).set('SELECT 1');
      final result = raw.wrap('(', ')');

      expect(identical(raw, result), true);
    });

    test('wrap() can be called multiple times (last wins)', () {
      final raw = Raw(
        client,
      ).set('SELECT 1').wrap('(', ')').wrap('[', ']'); // Overwrites previous

      expect(raw.sql, 'SELECT 1'); // Still unchanged
      // When toSQL() is implemented, it should produce '[SELECT 1]'
    });

    test('wrap() handles empty strings', () {
      final raw = Raw(client).set('SELECT 1').wrap('', '');

      expect(raw.sql, 'SELECT 1');
    });
  });

  group('Raw - set() method', () {
    test('set() with null bindings creates empty array', () {
      final raw = Raw(client).set('SELECT 1', null);

      expect(raw.sql, 'SELECT 1');
      expect(raw.bindings, []);
    });

    test('set() with List bindings stores as-is', () {
      final raw = Raw(client).set('SELECT * FROM users WHERE id = ?', [1]);

      expect(raw.sql, 'SELECT * FROM users WHERE id = ?');
      expect(raw.bindings, [1]);
    });

    test('set() with Map bindings preserves Map', () {
      final raw = Raw(client).set('SELECT * FROM :table:', {'table': 'users'});

      expect(raw.bindings, isA<Map>());
      expect(raw.bindings['table'], 'users');
    });

    test('set() with single value wraps in array', () {
      final raw = Raw(client).set('SELECT ?', 'test');

      expect(raw.bindings, ['test']);
    });

    test('set() returns this for chaining', () {
      final raw = Raw(client);
      final result = raw.set('SELECT 1');

      expect(identical(raw, result), true);
    });
  });
}
