import 'package:knex_dart/knex_dart.dart';
import 'package:test/test.dart';

import '../mocks/mock_client.dart';

void main() {
  group('Knex Facade Tests', () {
    test('Can initialize Knex with a Client', () {
      final knex = Knex(MockClient());

      expect(knex.client.driverName, equals('pg'));

      // Test QueryBuilder spawning
      final builder1 = knex();
      expect(builder1.toSQL().sql, equals('select *'));

      final builder2 = knex('users');
      expect(builder2.toSQL().sql, equals('select * from "users"'));
    });

    test('call() with table name sets the FROM clause', () {
      final knex = Knex(MockClient());
      final qb = knex('orders');
      expect(qb.toSQL().sql, contains('"orders"'));
    });

    test('schema getter returns a SchemaBuilder', () {
      final knex = Knex(MockClient());
      expect(knex.schema, isNotNull);
    });

    test('migrate getter returns a Migrator', () {
      final knex = Knex(MockClient());
      expect(knex.migrate, isNotNull);
    });

    test('client getter returns the underlying Client', () {
      final mockClient = MockClient();
      final knex = Knex(mockClient);
      expect(knex.client, same(mockClient));
    });

    test('Throws UnimplementedError for transaction', () async {
      final knex = Knex(MockClient());

      expect(
        () async => await knex.transaction((trx) async {}),
        throwsUnimplementedError,
      );
    });

    test('raw() returns a Raw object', () {
      final knex = Knex(MockClient());
      final r = knex.raw('select ?', [1]);
      expect(r, isNotNull);
    });

    test('ref() returns a Ref', () {
      final knex = Knex(MockClient());
      final r = knex.ref('users.id');
      expect(r.toSQL().sql, contains('users'));
    });
  });
}
