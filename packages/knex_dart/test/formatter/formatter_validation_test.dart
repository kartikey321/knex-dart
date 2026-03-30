import 'package:test/test.dart';
import 'package:knex_dart/src/formatter/formatter.dart';
import 'package:knex_dart/src/raw.dart';
import '../mocks/mock_client.dart';

void main() {
  late MockClient client;
  late Formatter formatter;

  setUp(() {
    client = MockClient();
    formatter = Formatter(client, {});
  });

  group('Formatter Step 2 - Validation (JS Comparison)', () {
    test('Test 1: operator - Equals', () {
      // JS: =
      expect(formatter.operator('='), '=');
    });

    test('Test 2: operator - Not equals', () {
      // JS: !=
      expect(formatter.operator('!='), '!=');
    });

    test('Test 3: operator - LIKE (case insensitive)', () {
      // JS: like
      expect(formatter.operator('LIKE'), 'like');
    });

    test('Test 4: operator - Between', () {
      // JS: between
      expect(formatter.operator('between'), 'between');
    });

    test('Test 5: operator - Greater than', () {
      // JS: >
      expect(formatter.operator('>'), '>');
    });

    test('Test 6: operator - PostgreSQL ? (escaped)', () {
      // JS: \?
      expect(formatter.operator('?'), r'\?');
    });

    test('Test 7: operator - PostgreSQL @> (contains)', () {
      // JS: @>
      expect(formatter.operator('@>'), '@>');
    });

    test('Test 8: operator - Raw value', () {
      // JS: CUSTOM_OP
      final raw = Raw(client).set('CUSTOM_OP', []);
      expect(formatter.operator(raw), 'CUSTOM_OP');
    });

    test('Test 9: operator - Invalid (should throw)', () {
      // JS: Threw: The operator "INVALID_OP" is not permitted
      expect(
        () => formatter.operator('INVALID_OP'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('The operator "INVALID_OP" is not permitted'),
          ),
        ),
      );
    });

    test('Test 10: direction - ASC', () {
      // JS: ASC
      expect(formatter.direction('ASC'), 'ASC');
    });

    test('Test 11: direction - DESC', () {
      // JS: DESC
      expect(formatter.direction('DESC'), 'DESC');
    });

    test('Test 12: direction - asc (lowercase)', () {
      // JS: asc
      expect(formatter.direction('asc'), 'asc');
    });

    test('Test 13: direction - Invalid (defaults to asc)', () {
      // JS: asc
      expect(formatter.direction('INVALID'), 'asc');
    });

    test('Test 14: direction - Empty (defaults to asc)', () {
      // JS: asc
      expect(formatter.direction(''), 'asc');
    });

    test('Test 15: direction - Raw value', () {
      // JS: CUSTOM_DIR
      final raw = Raw(client).set('CUSTOM_DIR', []);
      expect(formatter.direction(raw), 'CUSTOM_DIR');
    });
  });
}
