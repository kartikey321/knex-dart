import 'dart:io';

import 'package:knex_dart/knex_dart.dart';
import 'package:test/test.dart';

void main() {
  group('Knex Facade Tests', () {
    test('Can initialize Knex with SQLite via config', () {
      final knex = Knex(
        KnexConfig(client: 'sqlite', connection: {'filename': ':memory:'}),
      );

      expect(knex.client.driverName, equals('sqlite3'));

      // Test QueryBuilder spawning
      final builder1 = knex();
      expect(builder1.toSQL().sql, equals('select *'));

      final builder2 = knex('users');
      expect(builder2.toSQL().sql, equals('select * from "users"'));
    });

    test('Throws UnimplementedError for PG via KnexConfig', () {
      expect(
        () => Knex(
          KnexConfig(
            client: 'pg',
            connection: {'host': 'localhost', 'database': 'test'},
          ),
        ),
        throwsUnimplementedError,
      );
    });

    test('Throws UnimplementedError for MySQL via KnexConfig', () {
      expect(
        () => Knex(
          KnexConfig(
            client: 'mysql',
            connection: {'host': 'localhost', 'database': 'test'},
          ),
        ),
        throwsUnimplementedError,
      );
    });

    test('Throws UnimplementedError for transaction', () async {
      final knex = Knex(
        KnexConfig(client: 'sqlite', connection: {'filename': ':memory:'}),
      );

      expect(
        () async => await knex.transaction((trx) async {}),
        throwsUnimplementedError,
      );
    });

    test(
      'Knex.postgres() factory initiates connection (throws if no db)',
      () async {
        try {
          await Knex.postgres(
            host: '127.0.0.1',
            port: 1, // Invalid port
            database: 'test',
            username: 'test',
          );
          fail('Should not connect');
        } catch (e) {
          expect(e is SocketException || e is KnexException, isTrue);
        }
      },
    );

    test(
      'Knex.mysql() factory initiates connection (throws if no db)',
      () async {
        try {
          await Knex.mysql(
            host: '127.0.0.1',
            port: 1, // Invalid port
            database: 'test',
            user: 'test',
          );
          fail('Should not connect');
        } catch (e) {
          expect(e is SocketException || e is KnexException, isTrue);
        }
      },
    );

    // We skip actual connection tests since they are covered in integration,
    // but we can test the Unimplemented throws in the Knex facade where applicable.
  });
}
