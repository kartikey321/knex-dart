import 'package:test/test.dart';
import 'package:knex_dart/src/formatter/formatter.dart';
import 'package:knex_dart/src/raw.dart';
import '../mocks/mock_client.dart';

void main() {
  late MockClient client;

  setUp(() {
    client = MockClient();
  });

  group('Formatter - Client Integration', () {
    test('Client can create Formatter instances', () {
      final formatter = client.formatter({});

      expect(formatter, isA<Formatter>());
      expect(formatter.client, same(client));
    });

    test('Formatter from client works correctly', () {
      final formatter = client.formatter({});

      // Test basic wrapping
      expect(formatter.wrapString('users'), '"users"');
      expect(formatter.columnize(['id', 'name']), '"id", "name"');
    });

    test('Multiple formatters can be created', () {
      final formatter1 = client.formatter({});
      final formatter2 = client.formatter({});

      // Different instances
      expect(identical(formatter1, formatter2), false);

      // But same client
      expect(formatter1.client, same(client));
      expect(formatter2.client, same(client));
    });

    test('Formatter accumulates bindings independently', () {
      final formatter1 = client.formatter({});
      final formatter2 = client.formatter({});

      // Add bindings to formatter1
      final raw1 = Raw(client).set('SELECT ?', [123]);
      formatter1.wrap(raw1);

      // Add different bindings to formatter2
      final raw2 = Raw(client).set('SELECT ?', [456]);
      formatter2.wrap(raw2);

      // Each has its own bindings
      expect(formatter1.bindings, [123]);
      expect(formatter2.bindings, [456]);
    });

    test('Formatter can be used for complex operations', () {
      final formatter = client.formatter({});

      // Wrap multiple types
      expect(formatter.wrap('users'), '"users"');
      expect(formatter.wrap(123), 123);

      // Validate operators
      expect(formatter.operator('='), '=');
      expect(formatter.operator('LIKE'), 'like');

      // Validate directions
      expect(formatter.direction('ASC'), 'ASC');
      expect(formatter.direction('invalid'), 'asc');

      // Columnize
      expect(
        formatter.columnize(['users.id', 'users.name AS user_name']),
        '"users"."id", "users"."name" AS "user_name"',
      );
    });
  });
}
