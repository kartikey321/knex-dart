import 'dart:io';

import 'package:knex_dart/knex_dart.dart';
import 'package:knex_dart/src/client/postgres_client.dart';
import 'package:test/test.dart';

import '../mocks/mock_client.dart';

void main() {
  late PostgresClient pgClient;
  final mockClient = MockClient();
  const testEmails = <String>[
    'test_insert@example.com',
    'on_conflict_test@example.com',
    'before_update@example.com',
    'to_delete@example.com',
    'trx_commit@example.com',
    'pre_rollback@example.com',
    'trx_rollback@example.com',
    'json_test@example.com',
    'json_test1@example.com',
    'json_test2@example.com',
  ];

  Future<void> cleanupTestUsers() async {
    final deleteQuery = mockClient
        .queryBuilder()
        .table('users')
        .whereIn('email', testEmails)
        .delete();
    await pgClient.delete(deleteQuery);
  }

  // Initialize connection before tests
  setUpAll(() async {
    final host = Platform.environment['PG_HOST'] ?? 'localhost';
    final port = int.parse(Platform.environment['PG_PORT'] ?? '5432');
    final database = Platform.environment['PG_DATABASE'] ?? 'knex_test';
    final username = Platform.environment['PG_USER'] ?? 'test';
    final password = Platform.environment['PG_PASSWORD'] ?? 'test';

    pgClient = await PostgresClient.connect(
      host: host,
      port: port,
      database: database,
      username: username,
      password: password,
    );
    await cleanupTestUsers();
    print('PostgreSQL Connection connects successfully');
  });

  // Close connection after tests
  tearDownAll(() async {
    await cleanupTestUsers();
    await pgClient.close();
  });

  group('Basic SELECT', () {
    test('SELECT *', () async {
      final query = mockClient.queryBuilder().table('users');

      final results = await pgClient.select(query);

      expect(results.length, greaterThan(0));
      expect(results.first.containsKey('id'), true);
      expect(results.first.containsKey('name'), true);
      expect(results.first.containsKey('email'), true);
    });

    test('SELECT specific columns', () async {
      final query = mockClient.queryBuilder().table('users').select([
        'id',
        'name',
        'email',
      ]);

      final results = await pgClient.select(query);

      expect(results.first.keys.length, 3);
      expect(results.first.containsKey('password'), false);
    });
  });

  group('WHERE Clauses', () {
    test('WHERE with single condition', () async {
      final query = mockClient
          .queryBuilder()
          .table('users')
          .where('active', '=', true);

      final results = await pgClient.select(query);

      expect(results.isNotEmpty, true);
      expect(results.first['active'], true); // Postgres bool is bool in Dart
    });

    test('WHERE with multiple conditions', () async {
      final query = mockClient
          .queryBuilder()
          .table('users')
          .where('active', '=', true)
          .where('role', '=', 'admin');

      final results = await pgClient.select(query);

      expect(results.isNotEmpty, true);
      expect(results.first['role'], 'admin');
    });

    test('WHERE IN', () async {
      final query = mockClient.queryBuilder().table('users').whereIn('role', [
        'admin',
        'moderator',
      ]);

      final results = await pgClient.select(query);

      expect(results.length, greaterThan(0));
      for (final row in results) {
        expect(['admin', 'moderator'], contains(row['role']));
      }
    });

    test('WHERE NULL', () async {
      // Assuming we have some users with inactive status or nullable field
      // For this seed, let's use a known condition
      final query = mockClient
          .queryBuilder()
          .table('users')
          .where('active', false);

      final results = await pgClient.select(query);
      for (final row in results) {
        expect(row['active'], false);
      }
    });
  });

  group('JOINs', () {
    test('INNER JOIN', () async {
      final query = mockClient
          .queryBuilder()
          .table('orders')
          .join(
            'users',
            'users.id',
            'orders.user_id',
          ) // Corrected: join instead of innerJoin
          .select(['users.name', 'orders.amount', 'orders.status']);

      final results = await pgClient.select(query);

      expect(results.isNotEmpty, true);
      expect(results.first.containsKey('name'), true);
      expect(results.first.containsKey('amount'), true);
    });

    test('LEFT JOIN', () async {
      final query = mockClient
          .queryBuilder()
          .table('users')
          .leftJoin('orders', 'users.id', 'orders.user_id')
          .select(['users.name', 'orders.amount']);

      final results = await pgClient.select(query);

      expect(results.isNotEmpty, true);
    });
  });

  group('Aggregates', () {
    test('COUNT', () async {
      final query = mockClient
          .queryBuilder()
          .table('users')
          .count('* as total');

      final results = await pgClient.select(query);

      expect(results.first['total'], 5);
    });

    test('SUM', () async {
      final query = mockClient
          .queryBuilder()
          .table('orders')
          .sum('amount as total')
          .where('status', '=', 'completed');

      final results = await pgClient.select(query);

      // PostgreSQL returns DECIMAL as string to preserve precision
      // This is industry standard (TypeORM, Sequelize do the same)
      expect(results.first['total'], isA<String>());
      expect(num.parse(results.first['total']), greaterThan(0));
    });

    test('GROUP BY with HAVING (using havingRaw)', () async {
      // PostgreSQL requires HAVING clauses (and Group By) to refer to
      // non-grouped columns via aggregate functions directly or by position,
      // but not by alias in the same level.
      final query = mockClient
          .queryBuilder()
          .table('orders')
          .select(['user_id'])
          .count('* as order_count')
          .groupBy('user_id')
          .havingRaw('count(*) > ?', [1]);

      final results = await pgClient.select(query);

      expect(results.isNotEmpty, true);
      for (final row in results) {
        expect(row['order_count'], greaterThan(1));
      }
    });
  });

  group('ORDER BY and LIMIT', () {
    test('ORDER BY', () async {
      final query = mockClient
          .queryBuilder()
          .table('users')
          .select(['name'])
          .orderBy('name', 'asc');

      final results = await pgClient.select(query);

      final names = results.map((r) => r['name'] as String).toList();
      final sorted = List.of(names)..sort();
      expect(names, sorted);
    });

    test('LIMIT and OFFSET', () async {
      final query = mockClient.queryBuilder().table('users').limit(2).offset(1);

      final results = await pgClient.select(query);

      expect(results.length, 2);
    });
  });

  group('Subqueries', () {
    test('Subquery in WHERE', () async {
      final subquery = mockClient
          .queryBuilder()
          .table('orders')
          .select(['user_id'])
          .where('status', '=', 'completed');

      final query = mockClient
          .queryBuilder()
          .table('users')
          .select(['name'])
          .whereIn('id', subquery);

      final results = await pgClient.select(query);

      expect(results.isNotEmpty, true);
    });
  });

  group('UNION', () {
    test('UNION two queries', () async {
      final query1 = mockClient
          .queryBuilder()
          .table('users')
          .select(['name'])
          .where('role', 'admin');

      final query2 = mockClient
          .queryBuilder()
          .table('users')
          .select(['name'])
          .where('role', 'moderator');

      final query = query1.union([query2]); // Corrected: wrapped in List

      final results = await pgClient.select(query);

      expect(results.length, greaterThan(0));
      // Should handle both queries results
      expect(results.any((r) => r['name'] == 'Alice Johnson'), true); // Admin
      expect(
        results.any((r) => r['name'] == 'Diana Prince'),
        true,
      ); // Moderator
    });
  });

  group('Advanced Query APIs', () {
    test('Full-Text Search whereFullText', () async {
      final insertQuery = mockClient.queryBuilder().table('users').insert({
        'name': 'Johnathan Doe',
        'email': 'json_test1@example.com',
      });
      await pgClient.insert(insertQuery);

      final query = mockClient
          .queryBuilder()
          .table('users')
          .whereFullText('name', 'Johnathan')
          .orderBy('id');
      final results = await pgClient.select(query);
      expect(results, isNotEmpty);
      expect(results.first['name'], contains('Johnathan'));
    });

    test('JSON Operators: superset and subset', () async {
      // Create a column manually and insert data for test
      await pgClient.rawSql(
        'ALTER TABLE "users" ADD COLUMN IF NOT EXISTS "metadata" jsonb DEFAULT \'{}\';',
      );

      final insertQuery = mockClient.queryBuilder().table('users').insert({
        'name': 'JSON Tester',
        'email': 'json_test2@example.com',
        // In PostgreSQL, passing a Dart string for JSONB usually works,
        // or a map if the underlying driver supports it.
        'metadata': '{"language": "en", "theme": "dark"}',
      });
      await pgClient.insert(insertQuery);

      final query = mockClient
          .queryBuilder()
          .table('users')
          .whereJsonSupersetOf('metadata', {'language': 'en'});
      final results = await pgClient.select(query);

      expect(results, isNotEmpty);
    });

    test('Advanced HAVING clauses: havingRaw', () async {
      final query = mockClient
          .queryBuilder()
          .table('orders')
          .select(['user_id', mockClient.raw('COUNT(id) as total')])
          .groupBy('user_id')
          .havingRaw('COUNT(id) > ?', [1])
          .orderBy('total', 'desc');

      final results = await pgClient.select(query);

      expect(results, isNotEmpty);
      expect(results.first['total'], greaterThan(1));
    });
  });

  group('CTEs (WITH)', () {
    test('Basic CTE', () async {
      final cte = mockClient
          .queryBuilder()
          .table('orders')
          .select(['user_id'])
          .sum('amount as total')
          .groupBy('user_id');

      final query = mockClient
          .queryBuilder()
          .withQuery(
            'user_totals',
            cte,
          ) // Corrected: withQuery instead of withCTE
          .table('user_totals')
          .where('total', '>', 500);

      final results = await pgClient.select(query);

      expect(results.isNotEmpty, true);
    });
  });

  // ─── Write Operation Tests ──────────────────────────────────────────────────
  group('Write Operations', () {
    // Each test inserts its own row and cleans it up to stay independent.

    test('INSERT a row and verify with SELECT', () async {
      // Insert a test user
      final insertQ = mockClient
          .queryBuilder()
          .table('users')
          .insert({
            'name': 'Test Insert',

            'email': 'test_insert@example.com',
            'role': 'guest',
            'active': true,
          })
          .returning(['id', 'name']);
      final inserted = await pgClient.insert(insertQ);

      expect(inserted.length, 1);
      expect(inserted.first['name'], 'Test Insert');
      final id = inserted.first['id'];

      // Verify row exists
      final selectQ = mockClient.queryBuilder().table('users').where('id', id);
      final rows = await pgClient.select(selectQ);
      expect(rows.length, 1);

      // Cleanup
      await pgClient.delete(
        mockClient.queryBuilder().table('users').where('id', id),
      );
    });

    test('should perform an upsert with onConflict.merge()', () async {
      final email = 'on_conflict_test@example.com';
      // Initial insert
      final query1 = mockClient.queryBuilder().table('users').insert({
        'name': 'Original Name',
        'email': email,
        'role': 'guest',
      });
      await pgClient.insert(query1);

      // Upsert
      final query2 = mockClient
          .queryBuilder()
          .table('users')
          .insert({'name': 'Updated Name', 'email': email})
          .onConflict('email')
          .merge(['name']);

      await pgClient.insert(query2);

      final rows = await pgClient.select(
        mockClient.queryBuilder().table('users').where('email', email),
      );

      expect(rows.length, 1);
      expect(rows.first['name'], 'Updated Name');

      // Cleanup
      final deleteQuery = mockClient
          .queryBuilder()
          .table('users')
          .where('email', email)
          .delete();
      await pgClient.delete(deleteQuery);
    });

    test('UPDATE a row and verify', () async {
      // Insert a row to update
      final insertQ = mockClient
          .queryBuilder()
          .table('users')
          .insert({
            'name': 'Before Update',
            'email': 'before_update@example.com',
            'role': 'guest',
            'active': true,
          })
          .returning(['id']);
      final inserted = await pgClient.insert(insertQ);
      final id = inserted.first['id'];

      // Update it
      final updateQ = mockClient
          .queryBuilder()
          .table('users')
          .where('id', id)
          .update({'name': 'After Update'})
          .returning(['id', 'name']);
      final updated = await pgClient.update(updateQ);

      expect(updated.length, 1);
      expect(updated.first['name'], 'After Update');

      // Cleanup
      await pgClient.delete(
        mockClient.queryBuilder().table('users').where('id', id),
      );
    });

    test('DELETE a row and verify it is gone', () async {
      // Insert a row to delete
      final insertQ = mockClient
          .queryBuilder()
          .table('users')
          .insert({
            'name': 'To Delete',
            'email': 'to_delete@example.com',
            'role': 'guest',
            'active': false,
          })
          .returning(['id']);
      final inserted = await pgClient.insert(insertQ);
      final id = inserted.first['id'];

      // Delete it
      final deleteQ = mockClient
          .queryBuilder()
          .table('users')
          .where('id', id)
          .delete()
          .returning(['id']);
      final deleted = await pgClient.delete(deleteQ);
      expect(deleted.length, 1);
      expect(deleted.first['id'], id);

      // Verify it's gone
      final rows = await pgClient.select(
        mockClient.queryBuilder().table('users').where('id', id),
      );
      expect(rows.isEmpty, true);
    });
  });

  // ─── Transaction Tests ────────────────────────────────────────────────────
  group('Transactions', () {
    test('trx: COMMIT on success — changes are persisted', () async {
      // Use trx to insert a user
      final inserted = await pgClient.trx((trx) async {
        return trx.insert(
          mockClient
              .queryBuilder()
              .table('users')
              .insert({
                'name': 'Trx Commit Test',
                'email': 'trx_commit@example.com',
                'role': 'guest',
                'active': true,
              })
              .returning(['id', 'name']),
        );
      });

      expect(inserted.length, 1);
      expect(inserted.first['name'], 'Trx Commit Test');
      final id = inserted.first['id'];

      // Confirm visible after transaction committed
      final rows = await pgClient.select(
        mockClient.queryBuilder().table('users').where('id', id),
      );
      expect(rows.length, 1);

      // Cleanup
      await pgClient.delete(
        mockClient.queryBuilder().table('users').where('id', id),
      );
    });

    test('trx: ROLLBACK on error — changes are reverted', () async {
      // First insert a user outside the transaction so we know the base count
      final preInsert = await pgClient.insert(
        mockClient
            .queryBuilder()
            .table('users')
            .insert({
              'name': 'Pre Rollback',
              'email': 'pre_rollback@example.com',
              'role': 'guest',
              'active': true,
            })
            .returning(['id']),
      );
      final preId = preInsert.first['id'];

      // Try a transaction that should fail and rollback
      try {
        await pgClient.trx((trx) async {
          // This insert is valid
          await trx.insert(
            mockClient.queryBuilder().table('users').insert({
              'name': 'Trx Rollback Test',
              'email': 'trx_rollback@example.com',
              'role': 'guest',
              'active': true,
            }),
          );
          // This throws, causing rollback
          throw Exception('Forced rollback');
        });
      } catch (_) {
        // Expected
      }

      // The user from inside the failed trx should NOT exist
      final rows = await pgClient.select(
        mockClient
            .queryBuilder()
            .table('users')
            .where('email', 'trx_rollback@example.com'),
      );
      expect(rows.isEmpty, true);

      // Cleanup pre-insert
      await pgClient.delete(
        mockClient.queryBuilder().table('users').where('id', preId),
      );
    });
  });
}
