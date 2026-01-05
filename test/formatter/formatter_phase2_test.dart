import 'package:test/test.dart';
import 'package:knex_dart/src/formatter/formatter.dart';
import '../mocks/mock_client.dart';

void main() {
  late MockClient client;
  late Formatter formatter;

  setUp(() {
    client = MockClient();
    formatter = Formatter(client, null);
  });

  group('Formatter Phase 2 - Advanced Features', () {
    group('Object-based Column Aliasing', () {
      test('Simple object aliasing', () {
        // { 'user_name': 'name' } → "name" AS "user_name"
        final result = formatter.columnize({'user_name': 'name'});
        expect(result, '"name" AS "user_name"');
      });

      test('Multiple object aliases', () {
        // { 'a': 'col1', 'b': 'col2' } → "col1" AS "a", "col2" AS "b"
        final result = formatter.columnize({'a': 'col1', 'b': 'col2'});

        // Order may vary in Map, so check both parts are present
        expect(result.contains('"col1" AS "a"'), true);
        expect(result.contains('"col2" AS "b"'), true);
        expect(result.contains(', '), true);
      });

      test('Object with dotted column name', () {
        // { 'user_name': 'users.name' } → "users"."name" AS "user_name"
        final result = formatter.columnize({'user_name': 'users.name'});
        expect(result, '"users"."name" AS "user_name"');
      });
    });

    group('Array-based Mixed Aliasing', () {
      test('Array with simple columns', () {
        // ['id', 'name'] → "id", "name"
        final result = formatter.columnize(['id', 'name']);
        expect(result, '"id", "name"');
      });

      test('Array with mixed string and object', () {
        // ['id', { 'user_name': 'name' }] → "id", "name" AS "user_name"
        final result = formatter.columnize([
          'id',
          {'user_name': 'name'},
        ]);
        expect(result, '"id", "name" AS "user_name"');
      });

      test('Array with multiple objects', () {
        // [{ 'a': 'col1' }, { 'b': 'col2' }] → "col1" AS "a", "col2" AS "b"
        final result = formatter.columnize([
          {'a': 'col1'},
          {'b': 'col2'},
        ]);
        expect(result, '"col1" AS "a", "col2" AS "b"');
      });

      test('Complex mixed array', () {
        // ['id', { 'total': 'amount' }, 'created_at']
        final result = formatter.columnize([
          'id',
          {'total': 'amount'},
          'created_at',
        ]);
        expect(result, '"id", "amount" AS "total", "created_at"');
      });
    });

    group('Parameter Formatting', () {
      test('Parameter with value', () {
        final result = formatter.parameter('test');
        expect(result, '\$1');
        expect(formatter.bindings, ['test']);
      });

      test('Parameter with NULL (default)', () {
        final result = formatter.parameter(null);
        expect(result, '\$1');
        expect(formatter.bindings, [null]);
      });

      test('Parameter with NULL and fallback', () {
        final result = formatter.parameter(null, 'DEFAULT');
        expect(result, 'DEFAULT');
        expect(formatter.bindings, []);
      });

      test('Parameter with number', () {
        final result = formatter.parameter(42);
        expect(result, '\$1');
        expect(formatter.bindings, [42]);
      });
    });

    group('Values List Formatting', () {
      test('Simple value list', () {
        // [1, 2, 3] → (\$1, \$2, \$3)
        final result = formatter.values([1, 2, 3]);
        expect(result, '(\$1, \$2, \$3)');
        expect(formatter.bindings, [1, 2, 3]);
      });

      test('String value list', () {
        // ['a', 'b', 'c'] → (\$1, \$2, \$3)
        final result = formatter.values(['active', 'pending']);
        expect(result, '(\$1, \$2)');
        expect(formatter.bindings, ['active', 'pending']);
      });

      test('Nested array (single)', () {
        // [[1, 2, 3]] → (\$1, \$2, \$3)
        final result = formatter.values([
          [1, 2, 3],
        ]);
        expect(result, '(\$1, \$2, \$3)');
        expect(formatter.bindings, [1, 2, 3]);
      });

      test('Single value (not a list)', () {
        // 42 → \$1
        final result = formatter.values(42);
        expect(result, '\$1');
        expect(formatter.bindings, [42]);
      });

      test('Empty list', () {
        // [] → ()
        final result = formatter.values([]);
        expect(result, '()');
        expect(formatter.bindings, []);
      });
    });

    group('Edge Cases', () {
      test('Empty object', () {
        // {} → ''
        final result = formatter.columnize({});
        expect(result, '');
      });

      test('Empty array', () {
        // [] → ''
        final result = formatter.columnize([]);
        expect(result, '');
      });

      test('Wildcard in object alias', () {
        // { 'all': '*' } → * AS "all"
        final result = formatter.columnize({'all': '*'});
        expect(result, '* AS "all"');
      });

      test('Schema.table.column in object', () {
        // { 'val': 'db.schema.col' } → "db"."schema"."col" AS "val"
        final result = formatter.columnize({'val': 'db.schema.col'});
        expect(result, '"db"."schema"."col" AS "val"');
      });
    });
  });
}
