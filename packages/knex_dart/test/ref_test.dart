import 'package:test/test.dart';
import 'package:knex_dart/src/ref.dart';
import 'package:knex_dart/src/raw.dart';
import 'package:knex_dart/src/query/sql_string.dart';
import 'mocks/mock_client.dart';

void main() {
  late MockClient client;

  setUp(() {
    client = MockClient();
  });

  group('Ref - JS Comparison Tests', () {
    test('Test 1: Simple ref', () {
      // JS: {"sql": "\"user_id\"", "bindings": [], "method": "raw"}
      final ref = Ref(client, 'user_id');
      final sql = ref.toSQL();

      expect(sql.sql, '"user_id"');
      expect(sql.bindings, []);
      expect(sql.method, 'raw');
      expect(sql.uid, isNotNull); // Has UID
    });

    test('Test 2: Ref with alias', () {
      // JS: {"sql": "\"user_id\" AS \"uid\"", ...}
      final ref = Ref(client, 'user_id').as('uid');
      final sql = ref.toSQL();

      expect(sql.sql, '"user_id" AS "uid"');
      expect(sql.bindings, []);
      expect(sql.method, 'raw');
    });

    test('Test 3: Ref with schema', () {
      // JS: {"sql": "\"accounts\".\"balance\"", ...}
      final ref = Ref(client, 'balance').withSchema('accounts');
      final sql = ref.toSQL();

      expect(sql.sql, '"accounts"."balance"');
      expect(sql.bindings, []);
      expect(sql.method, 'raw');
    });

    test('Test 4: Ref with schema and alias', () {
      // JS: {"sql": "\"accounts\".\"balance\" AS \"account_balance\"", ...}
      final ref = Ref(
        client,
        'balance',
      ).withSchema('accounts').as('account_balance');
      final sql = ref.toSQL();

      expect(sql.sql, '"accounts"."balance" AS "account_balance"');
      expect(sql.bindings, []);
      expect(sql.method, 'raw');
    });

    test('Test 5: Dotted ref (table.column)', () {
      // JS: {"sql": "\"users\".\"email\"", ...}
      final ref = Ref(client, 'users.email');
      final sql = ref.toSQL();

      expect(sql.sql, '"users"."email"');
      expect(sql.bindings, []);
    });

    test('Test 6: Dotted ref with alias', () {
      // JS: {"sql": "\"users\".\"email\" AS \"user_email\"", ...}
      final ref = Ref(client, 'users.email').as('user_email');
      final sql = ref.toSQL();

      expect(sql.sql, '"users"."email" AS "user_email"');
      expect(sql.bindings, []);
    });

    test('Test 7: Chaining returns this', () {
      // JS: Same instance: true
      final ref = Ref(client, 'id');
      final chained = ref.withSchema('public').as('user_id');

      expect(identical(ref, chained), true);

      final sql = ref.toSQL();
      expect(sql.sql, '"public"."id" AS "user_id"');
    });

    test('Test 8: Ref can use .wrap() (inherited from Raw)', () {
      // JS: {"sql": "(\"count\")", ...}
      final ref = Ref(client, 'count').wrap('(', ')');
      final sql = ref.toSQL();

      expect(sql.sql, '("count")');
      expect(sql.bindings, []);
    });

    test('Test 9: Multiple schema parts', () {
      // JS: {"sql": "\"schema\".\"table\".\"column\"", ...}
      final ref = Ref(client, 'column').withSchema('schema.table');
      final sql = ref.toSQL();

      expect(sql.sql, '"schema"."table"."column"');
      expect(sql.bindings, []);
    });
  });

  group('Ref - Inheritance from Raw', () {
    test('Ref extends Raw', () {
      final ref = Ref(client, 'id');
      expect(ref, isA<Raw>());
    });

    test('Can call Raw methods on Ref', () {
      final ref = Ref(client, 'id');

      // Should have Raw methods
      expect(() => ref.set('test', []), returnsNormally);
      expect(() => ref.wrap('(', ')'), returnsNormally);
    });

    test('toSQL returns SqlString (from Raw)', () {
      final ref = Ref(client, 'id');
      final result = ref.toSQL();

      expect(result, isA<SqlString>());
      expect(result.method, 'raw');
      expect(result.uid, isNotNull);
    });
  });
}
