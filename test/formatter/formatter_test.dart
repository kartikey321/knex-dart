import 'package:test/test.dart';
import 'package:knex_dart/src/formatter/formatter.dart';
import 'package:knex_dart/src/raw.dart';
import '../mocks/mock_client.dart';

void main() {
  late MockClient client;
  late Formatter formatter;

  setUp(() {
    client = MockClient();
    formatter = Formatter(client, {}); // Minimal builder
  });

  group('Formatter Step 1 - Core Wrapping (JS Comparison)', () {
    test('Test 1: wrapString - Simple identifier', () {
      // JS: "users"
      final result = formatter.wrapString('users');
      expect(result, '"users"');
    });

    test('Test 2: wrapString - Dotted (schema.table)', () {
      // JS: "public"."users"
      final result = formatter.wrapString('public.users');
      expect(result, '"public"."users"');
    });

    test('Test 3: wrapString - Three parts (schema.table.column)', () {
      // JS: "public"."users"."id"
      final result = formatter.wrapString('public.users.id');
      expect(result, '"public"."users"."id"');
    });

    test('Test 4: wrapString - With AS alias', () {
      // JS: "name" AS "user_name"
      final result = formatter.wrapString('name AS user_name');
      expect(result, '"name" AS "user_name"');
    });

    test('Test 5: wrapString - Dotted with AS', () {
      // JS: "users"."email" AS "contact"
      final result = formatter.wrapString('users.email AS contact');
      expect(result, '"users"."email" AS "contact"');
    });

    test('Test 6: wrapString - Wildcard', () {
      // JS: *
      final result = formatter.wrapString('*');
      expect(result, '*');
    });

    test('Test 7: wrap - String', () {
      // JS: "users", Bindings: []
      final result = formatter.wrap('users');
      expect(result, '"users"');
      expect(formatter.bindings, []);
    });

    test('Test 8: wrap - Number', () {
      // JS: 123, Bindings: []
      formatter.bindings.clear();
      final result = formatter.wrap(123);
      expect(result, 123);
      expect(formatter.bindings, []);
    });

    test('Test 9: wrap - Raw', () {
      // JS: NOW(), Bindings: []
      formatter.bindings.clear();
      final raw = Raw(client).set('NOW()', []);
      final result = formatter.wrap(raw);
      expect(result, 'NOW()');
      expect(formatter.bindings, []);
    });

    test('Test 10: wrap - Raw with bindings', () {
      // JS simple test shows: SELECT ?, Bindings: [123]
      // But our Dart Raw.toSQL() formats bindings, so becomes: SELECT $1
      formatter.bindings.clear();
      final raw = Raw(client).set('SELECT ?', [123]);
      final result = formatter.wrap(raw);
      expect(result, 'SELECT \$1'); // Formatted by Raw.toSQL()
      expect(formatter.bindings, [123]);
    });

    test('Test 11: columnize - Single column', () {
      // JS: "id"
      formatter.bindings.clear();
      final result = formatter.columnize('id');
      expect(result, '"id"');
    });

    test('Test 12: columnize - Multiple columns', () {
      // JS: "id", "name", "email"
      formatter.bindings.clear();
      final result = formatter.columnize(['id', 'name', 'email']);
      expect(result, '"id", "name", "email"');
    });

    test('Test 13: columnize - Dotted columns', () {
      // JS: "users"."id", "users"."name"
      formatter.bindings.clear();
      final result = formatter.columnize(['users.id', 'users.name']);
      expect(result, '"users"."id", "users"."name"');
    });

    test('Test 14: columnize - With wildcard', () {
      // JS: *
      formatter.bindings.clear();
      final result = formatter.columnize('*');
      expect(result, '*');
    });

    test('Test 15: columnize - Mixed: strings and Raw', () {
      // JS: "id", COUNT(*)
      formatter.bindings.clear();
      final raw = Raw(client).set('COUNT(*)', []);
      final result = formatter.columnize(['id', raw]);
      expect(result, '"id", COUNT(*)');
    });

    test('Test 16: columnize - With AS aliases', () {
      // JS: "id", "name" AS "user_name"
      formatter.bindings.clear();
      final result = formatter.columnize(['id', 'name AS user_name']);
      expect(result, '"id", "name" AS "user_name"');
    });
  });
}
