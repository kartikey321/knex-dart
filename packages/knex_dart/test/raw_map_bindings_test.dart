import 'package:test/test.dart';
import 'package:knex_dart/src/raw.dart';
import 'mocks/mock_client.dart';

void main() {
  late MockClient client;

  setUp(() {
    client = MockClient();
  });

  group('Raw - Map bindings preservation', () {
    test('set() preserves Map bindings (not wrapped in array)', () {
      final raw = Raw(client).set('SELECT :id', {'id': 1});

      // Should be a Map, not an array wrapping a Map
      expect(raw.bindings, isA<Map>());
      expect(raw.bindings['id'], 1);
    });

    test('set() preserves multiple named bindings', () {
      final raw = Raw(client).set(
        'SELECT * FROM :table: WHERE :column: = :value',
        {'table': 'users', 'column': 'id', 'value': 123},
      );

      expect(raw.bindings, isA<Map>());
      expect(raw.bindings['table'], 'users');
      expect(raw.bindings['column'], 'id');
      expect(raw.bindings['value'], 123);
    });

    test('set() still handles List bindings correctly', () {
      final raw = Raw(client).set('SELECT ?, ?', [1, 2]);

      expect(raw.bindings, isA<List>());
      expect(raw.bindings, [1, 2]);
    });
  });
}
