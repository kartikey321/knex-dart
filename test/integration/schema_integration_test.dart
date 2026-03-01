import 'package:knex_dart/knex_dart.dart';
import 'package:test/test.dart';

void main() {
  group('Schema Integration Tests', () {
    KnexSQLite? sqliteClient;
    KnexPostgres? pgClient;
    KnexMySQL? mysqlClient;

    setUpAll(() async {
      // Setup SQLite (In-Memory)
      sqliteClient = await Knex.sqlite(filename: ':memory:');

      // Setup Postgres (Docker)
      try {
        pgClient = await Knex.postgres(
          host: 'localhost',
          database: 'knex_test',
          username: 'test',
          password: 'test',
        );
      } catch (e) {
        print('Warning: Postgres could not connect. Is Docker running? $e');
      }

      // Setup MySQL (Docker)
      try {
        mysqlClient = await Knex.mysql(
          host: 'localhost',
          database: 'knex_test',
          user: 'test',
          password: 'test',
        );
      } catch (e) {
        print('Warning: MySQL could not connect. Is Docker running? $e');
      }
    });

    tearDownAll(() async {
      await sqliteClient?.close();
      await pgClient?.close();
      await mysqlClient?.close();
    });

    void runTestForDialect(String dialectName, dynamic Function() getClient) {
      test(
        '[$dialectName] executes schema lifecycle (create, alter, drop)',
        () async {
          final client = getClient();
          if (client == null) {
            markTestSkipped('$dialectName client not available');
            return;
          }

          // 1. Drop table if exists
          await client.executeSchema((schema) {
            schema.dropTableIfExists('integration_users');
          });

          // 2. Create table
          await client.executeSchema((schema) {
            schema.createTable('integration_users', (table) {
              table.increments('id');
              table.string('name', 50).notNullable();
              table.string('email').unique();
              table.boolean('is_active').defaultTo(true);
              table.timestamps(false, true); // default to now
            });
          });

          // 3. Insert and select to verify table structure
          await client.insert(
            client.queryBuilder().table('integration_users').insert({
              'name': 'John Doe',
              'email': 'john@example.com',
            }),
          );

          var users = await client.select(
            client.queryBuilder().table('integration_users'),
          );
          expect(users, hasLength(1));
          expect(users[0]['name'], 'John Doe');

          // 4. Alter table (Add a column and insert)
          await client.executeSchema((schema) {
            schema.alterTable('integration_users', (table) {
              table.integer('age').defaultTo(30);
            });
          });

          // Update the user's age
          await client.update(
            client
                .queryBuilder()
                .table('integration_users')
                .where('id', 1)
                .update({'age': 35}),
          );

          users = await client.select(
            client.queryBuilder().table('integration_users'),
          );
          expect(users[0]['age'], 35);

          // 5. Drop the table
          await client.executeSchema((schema) {
            schema.dropTable('integration_users');
          });

          // Verify table was dropped (Select should fail)
          try {
            await client.select(
              client.queryBuilder().table('integration_users'),
            );
            fail('Should have thrown an error since table was dropped');
          } catch (e) {
            // Expected an error
            expect(e, isNotNull);
          }
        },
      );
    }

    runTestForDialect('SQLite', () => sqliteClient);
    runTestForDialect('PostgreSQL', () => pgClient);
    runTestForDialect('MySQL', () => mysqlClient);
  });
}
