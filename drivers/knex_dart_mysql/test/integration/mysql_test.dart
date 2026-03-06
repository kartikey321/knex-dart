@Tags(['mysql'])
library;

import 'dart:io';

import 'package:knex_dart_mysql/knex_dart_mysql.dart';
import 'package:knex_dart/src/query/aggregate_options.dart';
import 'package:test/test.dart';

import '../mocks/mysql_mock_client.dart';

void main() {
  group('MySQL Integration Tests', () {
    MySQLClient? client;
    final mockClient = MySQLMockClient();

    final host = Platform.environment['MYSQL_HOST'] ?? 'localhost';
    final port = int.parse(Platform.environment['MYSQL_PORT'] ?? '3306');
    final user = Platform.environment['MYSQL_USER'] ?? 'test';
    final password = Platform.environment['MYSQL_PASSWORD'] ?? 'test';
    final database = Platform.environment['MYSQL_DATABASE'] ?? 'knex_test';

    MySQLClient? globalClient;

    setUpAll(() async {
      try {
        globalClient = await MySQLClient.connect(
          host: host,
          port: port,
          user: user,
          password: password,
          database: database,
        );
        // Purge any stale rows left by previous test runs
        await globalClient!.raw(
          "DELETE FROM users WHERE email LIKE '%write@example.com' "
          "OR email LIKE '%trx%@example.com' "
          "OR email LIKE '%update@example.com' "
          "OR email LIKE '%delete@example.com' "
          "OR email LIKE '%json_test%@example.com' "
          "OR email LIKE '%_sp@example.com'",
        );
      } catch (e) {
        print('Warning: could not purge stale test data: $e');
      }
    });

    tearDownAll(() async {
      if (globalClient != null && !globalClient!.isClosed) {
        await globalClient!.close();
      }
    });

    setUp(() async {
      try {
        client = await MySQLClient.connect(
          host: host,
          port: port,
          user: user,
          password: password,
          database: database,
        );
      } catch (e) {
        print(
          'Skipping MySQL tests: Could not connect to database at $host:$port. Error: $e',
        );
        rethrow;
      }
    });

    tearDown(() async {
      if (client != null && !client!.isClosed) {
        await client!.close();
      }
    });

    test('should connect to database', () async {
      expect(client!.isClosed, isFalse);
    });

    test('should select all users', () async {
      final query = mockClient.queryBuilder().table('users');
      final result = await client!.select(query);
      expect(result.length, 3);
    });

    test('should filter users with where clause', () async {
      final query = mockClient
          .queryBuilder()
          .table('users')
          .where('first_name', 'John');
      final result = await client!.select(query);
      expect(result.length, 1);
      expect(result.first['first_name'], 'John');
    });

    test('should perform inner join', () async {
      final query = mockClient
          .queryBuilder()
          .select(['users.first_name', 'accounts.balance'])
          .from('users')
          .join('accounts', 'users.id', 'accounts.user_id');

      final result = await client!.select(query);
      expect(result.length, 3);
      expect(result.first.containsKey('first_name'), isTrue);
      expect(result.first.containsKey('balance'), isTrue);
    });

    test('should perform left join', () async {
      final query = mockClient
          .queryBuilder()
          .select(['users.first_name', 'accounts.balance'])
          .from('users')
          .leftJoin('accounts', 'users.id', 'accounts.user_id');

      final result = await client!.select(query);
      expect(result.length, 3);
    });

    test('should use raw queries', () async {
      final result = await client!.raw('select 1 + 1 as result');
      expect(result.first['result'], 2);
    });

    test('should limit results', () async {
      final query = mockClient.queryBuilder().table('users').limit(2);
      final result = await client!.select(query);
      expect(result.length, 2);
    });

    test('should order results', () async {
      final query = mockClient
          .queryBuilder()
          .table('users')
          .orderBy('first_name', 'desc');
      final result = await client!.select(query);
      expect(result.first['first_name'], 'John');
    });

    // Aggregate tests
    test('should count records', () async {
      final query = mockClient
          .queryBuilder()
          .table('users')
          .count('id', const AggregateOptions(as: 'total'));
      final result = await client!.select(query);

      final total = result.first['total'];
      expect(total, 3);
    });

    test('should sum values', () async {
      final query = mockClient
          .queryBuilder()
          .table('accounts')
          .sum('logins', const AggregateOptions(as: 'total'));
      final results = await client!.select(query);

      final total = results.first['total'];
      expect(num.parse(total.toString()), 30);
    });

    test('should handle question marks in string literals', () async {
      final result = await client!.raw("select 'Question?' as q, ? as v", [
        'Answer',
      ]);
      expect(result.first['q'], 'Question?');
      expect(result.first['v'], 'Answer');
    });

    // ─── Write Operation Tests ────────────────────────────────────────────────

    test('should insert a user and verify via SELECT', () async {
      final query = mockClient.queryBuilder().table('users').insert({
        'first_name': 'New',
        'last_name': 'User',
        'email': 'new_user_write@example.com',
      });
      await client!.insert(query);

      final rows = await client!.select(
        mockClient
            .queryBuilder()
            .table('users')
            .where('email', 'new_user_write@example.com'),
      );
      expect(rows.length, 1);
      expect(rows.first['first_name'], 'New');

      await client!.delete(
        mockClient
            .queryBuilder()
            .table('users')
            .where('email', 'new_user_write@example.com'),
      );
    });

    test('should update a user and verify change', () async {
      final insertQ = mockClient.queryBuilder().table('users').insert({
        'first_name': 'Before',
        'last_name': 'Update',
        'email': 'before_update_write@example.com',
      });
      await client!.insert(insertQ);

      final updateQ = mockClient
          .queryBuilder()
          .table('users')
          .where('email', 'before_update_write@example.com')
          .update({'first_name': 'After'});
      await client!.update(updateQ);

      final rows = await client!.select(
        mockClient
            .queryBuilder()
            .table('users')
            .where('email', 'before_update_write@example.com'),
      );
      expect(rows.first['first_name'], 'After');

      await client!.delete(
        mockClient
            .queryBuilder()
            .table('users')
            .where('email', 'before_update_write@example.com'),
      );
    });

    test('should delete a user and confirm removal', () async {
      final insertQ = mockClient.queryBuilder().table('users').insert({
        'first_name': 'Temp',
        'last_name': 'Delete',
        'email': 'temp_delete_write@example.com',
      });
      await client!.insert(insertQ);

      final deleteQ = mockClient
          .queryBuilder()
          .table('users')
          .where('email', 'temp_delete_write@example.com')
          .delete();
      await client!.delete(deleteQ);

      final rows = await client!.select(
        mockClient
            .queryBuilder()
            .table('users')
            .where('email', 'temp_delete_write@example.com'),
      );
      expect(rows.isEmpty, true);
    });

    // ─── Transaction Tests ────────────────────────────────────────────────────

    test('trx: COMMIT on success — changes are persisted', () async {
      await client!.trx((trx) async {
        await trx.insert(
          mockClient.queryBuilder().table('users').insert({
            'first_name': 'Trx',
            'last_name': 'Commit',
            'email': 'trx_commit_mysql@example.com',
          }),
        );
      });

      final rows = await client!.select(
        mockClient
            .queryBuilder()
            .table('users')
            .where('email', 'trx_commit_mysql@example.com'),
      );
      expect(rows.length, 1);
      expect(rows.first['first_name'], 'Trx');

      await client!.delete(
        mockClient
            .queryBuilder()
            .table('users')
            .where('email', 'trx_commit_mysql@example.com'),
      );
    });

    test('trx: ROLLBACK on error — changes are reverted', () async {
      try {
        await client!.trx((trx) async {
          await trx.insert(
            mockClient.queryBuilder().table('users').insert({
              'first_name': 'Trx',
              'last_name': 'Rollback',
              'email': 'trx_rollback_mysql@example.com',
            }),
          );
          throw Exception('Forced rollback');
        });
      } catch (_) {
        // Expected
      }

      final rows = await client!.select(
        mockClient
            .queryBuilder()
            .table('users')
            .where('email', 'trx_rollback_mysql@example.com'),
      );
      expect(rows.isEmpty, true);
    });

    // ─── Nested Transaction (Savepoint) Tests ───────────────────────────────
    group('Nested Transactions (Savepoints)', () {
      test('nested trx: both succeed — both changes visible', () async {
        await client!.trx((outer) async {
          await outer.insert(
            mockClient.queryBuilder().table('users').insert({
              'first_name': 'Outer',
              'last_name': 'SP',
              'email': 'outer_sp@example.com',
            }),
          );

          await outer.trx((inner) async {
            await inner.insert(
              mockClient.queryBuilder().table('users').insert({
                'first_name': 'Inner',
                'last_name': 'SP',
                'email': 'inner_sp@example.com',
              }),
            );
          });
        });

        final outerRows = await client!.select(
          mockClient
              .queryBuilder()
              .table('users')
              .where('email', 'outer_sp@example.com'),
        );
        final innerRows = await client!.select(
          mockClient
              .queryBuilder()
              .table('users')
              .where('email', 'inner_sp@example.com'),
        );
        expect(outerRows.length, 1);
        expect(innerRows.length, 1);

        await client!.delete(
          mockClient
              .queryBuilder()
              .table('users')
              .whereIn('email', ['outer_sp@example.com', 'inner_sp@example.com']),
        );
      });

      test('nested trx: inner rollback, outer continues', () async {
        await client!.trx((outer) async {
          await outer.insert(
            mockClient.queryBuilder().table('users').insert({
              'first_name': 'Outer After',
              'last_name': 'SP',
              'email': 'outer_after_sp@example.com',
            }),
          );

          try {
            await outer.trx((inner) async {
              await inner.insert(
                mockClient.queryBuilder().table('users').insert({
                  'first_name': 'Inner Fail',
                  'last_name': 'SP',
                  'email': 'inner_fail_sp@example.com',
                }),
              );
              throw Exception('force inner rollback');
            });
          } catch (_) {
            // Caught — outer continues
          }
        });

        final outerRows = await client!.select(
          mockClient
              .queryBuilder()
              .table('users')
              .where('email', 'outer_after_sp@example.com'),
        );
        final innerRows = await client!.select(
          mockClient
              .queryBuilder()
              .table('users')
              .where('email', 'inner_fail_sp@example.com'),
        );
        expect(outerRows.length, 1); // outer committed
        expect(innerRows.isEmpty, true); // inner rolled back

        await client!.delete(
          mockClient
              .queryBuilder()
              .table('users')
              .where('email', 'outer_after_sp@example.com'),
        );
      });

      test('nested trx: inner error bubbles — outer rolled back too', () async {
        try {
          await client!.trx((outer) async {
            await outer.insert(
              mockClient.queryBuilder().table('users').insert({
                'first_name': 'Outer',
                'last_name': 'Bubble',
                'email': 'outer_bubble_sp@example.com',
              }),
            );
            await outer.trx((inner) async {
              await inner.insert(
                mockClient.queryBuilder().table('users').insert({
                  'first_name': 'Inner',
                  'last_name': 'Bubble',
                  'email': 'inner_bubble_sp@example.com',
                }),
              );
              throw Exception('bubble up');
            });
          });
        } catch (_) {}

        final outerRows = await client!.select(
          mockClient
              .queryBuilder()
              .table('users')
              .where('email', 'outer_bubble_sp@example.com'),
        );
        final innerRows = await client!.select(
          mockClient
              .queryBuilder()
              .table('users')
              .where('email', 'inner_bubble_sp@example.com'),
        );
        expect(outerRows.isEmpty, true);
        expect(innerRows.isEmpty, true);
      });
    });

    group('Advanced Query APIs', () {
      test('Full-Text Search whereFullText', () async {
        final insertQuery = mockClient.queryBuilder().table('users').insert({
          'first_name': 'Johnathan',
          'last_name': 'Doe',
          'email': 'json_test1_mysql@example.com',
        });
        await client!.insert(insertQuery);

        try {
          await client!.raw('ALTER TABLE users ADD FULLTEXT(first_name)');
        } catch (_) {
          // Ignore if already exists
        }

        final query = mockClient
            .queryBuilder()
            .table('users')
            .whereFullText('first_name', 'Johnathan')
            .orderBy('id');
        final results = await client!.select(query);
        expect(results, isNotEmpty);
        expect(results.first['first_name'], contains('Johnathan'));
      });

      test('JSON Operators: superset and subset', () async {
        try {
          await client!.raw('ALTER TABLE users ADD COLUMN metadata JSON NULL');
        } catch (_) {
          // Ignore if exists
        }

        final insertQuery = mockClient.queryBuilder().table('users').insert({
          'first_name': 'JSON Tester',
          'last_name': 'Tester',
          'email': 'json_test2_mysql@example.com',
          'metadata': '{"language": "en", "theme": "dark"}',
        });
        await client!.insert(insertQuery);

        final query = mockClient
            .queryBuilder()
            .table('users')
            .select(['id', 'first_name', 'email'])
            .where(
              mockClient.raw("JSON_CONTAINS(metadata, ?)", [
                '{"language": "en"}',
              ]),
            );

        final results = await client!.select(query);

        expect(results, isNotEmpty);
      });

      test('Advanced HAVING clauses: havingRaw', () async {
        try {
          await client!.raw(
            'CREATE TABLE IF NOT EXISTS orders (id INT AUTO_INCREMENT PRIMARY KEY, user_id INT, amount DECIMAL(10,2))',
          );
          final insertQ = mockClient.queryBuilder().table('orders').insert([
            {'user_id': 1, 'amount': 100},
            {'user_id': 1, 'amount': 200},
            {'user_id': 2, 'amount': 300},
          ]);
          await client!.insert(insertQ);
        } catch (_) {}

        final query = mockClient
            .queryBuilder()
            .table('orders')
            .select(['user_id', mockClient.raw('COUNT(id) as total')])
            .groupBy('user_id')
            .havingRaw('COUNT(id) > ?', [1])
            .orderBy('total', 'desc');

        final results = await client!.select(query);

        expect(results, isNotEmpty);
        expect(results.first['total'], greaterThan(1));

        try {
          await client!.raw('DROP TABLE orders');
        } catch (_) {}
      });
    });
  });
}
