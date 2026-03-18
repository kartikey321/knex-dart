import 'dart:io';

import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';
import 'package:knex_dart/src/query/aggregate_options.dart';
import 'package:test/test.dart';

void main() {
  group('SQLite Integration Tests', () {
    SQLiteClient? client;

    // Use in-memory database for tests
    final filename = Platform.environment['SQLITE_DB'] ?? ':memory:';

    setUp(() async {
      // Connect to SQLite
      client = await SQLiteClient.connect(filename: filename);

      // Create tables via SchemaBuilder (no raw DDL)
      await client!.schemaBuilder().createTable('users', (t) {
        t.increments('id');
        t.string('first_name').nullable();
      }).execute();

      await client!.schemaBuilder().createTable('accounts', (t) {
        t.increments('id');
        t.integer('user_id').nullable();
        t.doublePrecision('balance').nullable();
        t.integer('logins').nullable();
      }).execute();

      final insertUsersQ = client!.queryBuilder().table('users').insert([
        {'first_name': 'John'},
        {'first_name': 'Alice'},
        {'first_name': 'Bob'},
      ]);
      await client!.insert(insertUsersQ);

      final insertAccountsQ = client!.queryBuilder().table('accounts').insert([
        {'user_id': 1, 'balance': 100.50, 'logins': 10},
        {'user_id': 2, 'balance': 200.00, 'logins': 5},
        {'user_id': 3, 'balance': 300.00, 'logins': 15},
      ]);
      await client!.insert(insertAccountsQ);
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
      final query = client!.queryBuilder().table('users');
      final result = await client!.select(query);
      expect(result.length, 3);
    });

    test('should filter users with where clause', () async {
      final query = client!
          .queryBuilder()
          .table('users')
          .where('first_name', 'John');
      final result = await client!.select(query);
      expect(result.length, 1);
      expect(result.first['first_name'], 'John');
    });

    test('should perform inner join', () async {
      final query = client!
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
      final query = client!
          .queryBuilder()
          .select(['users.first_name', 'accounts.balance'])
          .from('users')
          .leftJoin('accounts', 'users.id', 'accounts.user_id');

      final result = await client!.select(query);
      expect(result.length, 3);
    });

    test('should use raw queries', () async {
      final result = await client!.raw('select 1 + 1 as result').execute();
      expect(result.first['result'], 2);
    });

    test('should limit results', () async {
      final query = client!.queryBuilder().table('users').limit(2);
      final result = await client!.select(query);
      expect(result.length, 2);
    });

    test('should order results', () async {
      final query = client!
          .queryBuilder()
          .table('users')
          .orderBy('first_name', 'desc');
      final result = await client!.select(query);
      expect(result.first['first_name'], 'John');
    });

    // Aggregate tests
    test('should count records', () async {
      final query = client!
          .queryBuilder()
          .table('users')
          .count('id', const AggregateOptions(as: 'total'));
      final result = await client!.select(query);

      final total = result.first['total'];
      expect(total, 3);
    });

    test('should sum values', () async {
      final query = client!
          .queryBuilder()
          .table('accounts')
          .sum('logins', const AggregateOptions(as: 'total'));
      final results = await client!.select(query);

      final total = results.first['total'];
      expect(total, 30);
    });

    test('should handle question marks in string literals', () async {
      final result = await client!.raw("select 'Question?' as q, ? as v", [
        'Answer',
      ]).execute();
      expect(result.first['q'], 'Question?');
      expect(result.first['v'], 'Answer');
    });

    // ─── Write Operation Tests ──────────────────────────────────────────────

    test('should insert a row via QueryBuilder', () async {
      final query = client!.queryBuilder().table('users').insert({
        'first_name': 'Charlie',
      });
      await client!.execute(query);

      final rows = await client!.select(client!.queryBuilder().table('users'));
      expect(rows.length, 4);
      expect(rows.any((r) => r['first_name'] == 'Charlie'), isTrue);
    });

    test('should update a row via QueryBuilder', () async {
      final query = client!
          .queryBuilder()
          .table('users')
          .where('first_name', 'John')
          .update({'first_name': 'Johnny'});
      await client!.execute(query);

      final rows = await client!.select(
        client!.queryBuilder().table('users').where('first_name', 'Johnny'),
      );
      expect(rows.length, 1);
      expect(rows.first['first_name'], 'Johnny');
    });

    test('should delete a row via QueryBuilder', () async {
      final query = client!
          .queryBuilder()
          .table('users')
          .where('first_name', 'Bob')
          .delete();
      await client!.execute(query);

      final rows = await client!.select(client!.queryBuilder().table('users'));
      expect(rows.length, 2);
      expect(rows.any((r) => r['first_name'] == 'Bob'), isFalse);
    });

    // ─── Filtering variants ─────────────────────────────────────────────────

    test('whereIn filters by a list of values', () async {
      final query = client!.queryBuilder().table('users').whereIn(
        'first_name',
        ['John', 'Alice'],
      );
      final result = await client!.select(query);
      expect(result.length, 2);
      expect(result.map((r) => r['first_name']).toSet(), {'John', 'Alice'});
    });

    test('whereNull returns only rows where column is NULL', () async {
      // Insert a row with no first_name to create a NULL
      await client!.execute(
        client!.queryBuilder().table('users').insert({'first_name': null}),
      );
      final query = client!
          .queryBuilder()
          .table('users')
          .whereNull('first_name');
      final result = await client!.select(query);
      expect(result.length, 1);
      expect(result.first['first_name'], isNull);
    });

    test('whereNotNull excludes NULL rows', () async {
      await client!.execute(
        client!.queryBuilder().table('users').insert({'first_name': null}),
      );
      final query = client!
          .queryBuilder()
          .table('users')
          .whereNotNull('first_name');
      final result = await client!.select(query);
      expect(result.length, 3); // original 3 non-null rows
    });

    test('orWhere returns rows matching either condition', () async {
      final query = client!
          .queryBuilder()
          .table('users')
          .where('first_name', 'John')
          .orWhere('first_name', 'Alice');
      final result = await client!.select(query);
      expect(result.length, 2);
    });

    test('where with comparison operator (>=)', () async {
      final query = client!
          .queryBuilder()
          .table('accounts')
          .where('balance', '>=', 200.0);
      final result = await client!.select(query);
      expect(result.length, 2); // balance 200 and 300
    });

    test('whereNot excludes matched rows', () async {
      final query = client!
          .queryBuilder()
          .table('users')
          .whereNot('first_name', 'Bob');
      final result = await client!.select(query);
      expect(result.length, 2);
      expect(result.any((r) => r['first_name'] == 'Bob'), isFalse);
    });

    // ─── Pagination ──────────────────────────────────────────────────────────

    test('offset skips rows', () async {
      final query = client!
          .queryBuilder()
          .table('users')
          .orderBy('id')
          .offset(1)
          .limit(10);
      final result = await client!.select(query);
      expect(result.length, 2); // skips first of 3
    });

    test('limit + offset pages correctly', () async {
      // Page 1
      final page1 = await client!.select(
        client!.queryBuilder().table('users').orderBy('id').limit(1).offset(0),
      );
      // Page 2
      final page2 = await client!.select(
        client!.queryBuilder().table('users').orderBy('id').limit(1).offset(1),
      );
      expect(page1.length, 1);
      expect(page2.length, 1);
      expect(page1.first['id'], isNot(page2.first['id']));
    });

    // ─── Bulk INSERT ─────────────────────────────────────────────────────────

    test('bulk insert multiple rows in one call', () async {
      final query = client!.queryBuilder().table('users').insert([
        {'first_name': 'Dave'},
        {'first_name': 'Eve'},
        {'first_name': 'Frank'},
      ]);
      await client!.execute(query);

      final all = await client!.select(client!.queryBuilder().table('users'));
      expect(all.length, 6); // 3 original + 3 new
    });

    // ─── Aggregates ──────────────────────────────────────────────────────────

    test('avg returns average value', () async {
      final query = client!
          .queryBuilder()
          .table('accounts')
          .avg('balance', const AggregateOptions(as: 'avg_balance'));
      final result = await client!.select(query);
      final avg = (result.first['avg_balance'] as num).toDouble();
      expect(avg, closeTo(200.17, 0.1)); // (100.50 + 200 + 300) / 3
    });

    test('min returns minimum value', () async {
      final query = client!
          .queryBuilder()
          .table('accounts')
          .min('balance', const AggregateOptions(as: 'min_balance'));
      final result = await client!.select(query);
      final min = (result.first['min_balance'] as num).toDouble();
      expect(min, closeTo(100.50, 0.01));
    });

    test('max returns maximum value', () async {
      final query = client!
          .queryBuilder()
          .table('accounts')
          .max('logins', const AggregateOptions(as: 'max_logins'));
      final result = await client!.select(query);
      expect(result.first['max_logins'], 15);
    });

    test('GROUP BY with HAVING filters groups', () async {
      final result = await client!
          .raw(
            'SELECT user_id, SUM(logins) as total FROM accounts GROUP BY user_id HAVING total > 10',
          )
          .execute();
      // user_id 1 = 10 logins (not > 10), user_id 2 = 5, user_id 3 = 15
      // Only user_id 3 passes HAVING > 10
      expect(result.length, 1);
      expect((result as List).first['user_id'], 3);
    });

    test('distinct removes duplicate values', () async {
      // Insert a duplicate name
      await client!.execute(
        client!.queryBuilder().table('users').insert({'first_name': 'John'}),
      );
      final result = await client!
          .raw('SELECT DISTINCT first_name FROM users ORDER BY first_name')
          .execute();
      expect(result.length, 3); // John, Alice, Bob deduplicated
    });

    // ─── Multiple column SELECT ───────────────────────────────────────────────

    test('select specific columns excludes others', () async {
      final query = client!
          .queryBuilder()
          .select(['first_name'])
          .from('users')
          .orderBy('first_name');
      final result = await client!.select(query);
      expect(result.first.containsKey('first_name'), isTrue);
      expect(result.first.containsKey('id'), isFalse);
    });

    // ─── Subquery ────────────────────────────────────────────────────────────

    test('raw subquery in WHERE clause', () async {
      final result = await client!.raw(
        'SELECT first_name FROM users WHERE id IN (SELECT user_id FROM accounts WHERE balance > ?)',
        [150.0],
      ).execute();
      expect(result.length, 2); // balance 200 (user 2) and 300 (user 3)
    });

    // ─── Schema builder ──────────────────────────────────────────────────────

    test('schema createTable and dropTable', () async {
      // Create
      await client!.schemaBuilder().createTable('temp_items', (t) {
        t.increments('id');
        t.string('label').notNullable();
      }).execute();

      await client!.raw('INSERT INTO temp_items (label) VALUES (?)', [
        'hello',
      ]).execute();
      final rows =
          await client!.raw('SELECT * FROM temp_items').execute() as List;
      expect(rows, hasLength(1));
      expect(rows.first['label'], 'hello');

      // Drop
      await client!.schemaBuilder().dropTable('temp_items').execute();
      expect(
        () => client!.raw('SELECT * FROM temp_items').execute(),
        throwsA(anything),
      );
    });

    test('schema addColumn adds a new column', () async {
      await client!.schemaBuilder().alterTable('users', (t) {
        t.text('email').nullable();
      }).execute();

      await client!.execute(
        client!
            .queryBuilder()
            .table('users')
            .where('first_name', 'John')
            .update({'email': 'john@example.com'}),
      );

      final rows = await client!.select(
        client!
            .queryBuilder()
            .table('users')
            .where('first_name', 'John')
            .select(['email']),
      );
      expect(rows.first['email'], 'john@example.com');
    });

    // ─── Self-join ───────────────────────────────────────────────────────────

    test('self-join via raw SQL', () async {
      // Add a second account for user 1 to test self-join
      await client!.execute(
        client!.queryBuilder().table('accounts').insert({
          'user_id': 1,
          'balance': 50.0,
          'logins': 2,
        }),
      );
      final result =
          await client!.raw('''
        SELECT a1.user_id, a1.balance as b1, a2.balance as b2
        FROM accounts a1
        JOIN accounts a2 ON a1.user_id = a2.user_id AND a1.id < a2.id
      ''').execute()
              as List;
      expect(result, hasLength(1));
      expect(result.first['user_id'], 1);
    });

    // ─── Error handling ──────────────────────────────────────────────────────

    test('closed client throws on query', () async {
      await client!.close();
      expect(() => client!.raw('SELECT 1').execute(), throwsA(anything));
      client = null; // prevent tearDown from closing again
    });

    group('distinct deduplicates rows via QB', () {
      test('distinct() deduplicates first_name values', () async {
        await client!.execute(
          client!.queryBuilder().table('users').insert({'first_name': 'John'}),
        );

        final rows = await client!.select(
          client!
              .queryBuilder()
              .from('users')
              .distinct(['first_name'])
              .orderBy('first_name'),
        );

        expect(rows, hasLength(3));
        expect(rows.map((r) => r['first_name']).toList(), [
          'Alice',
          'Bob',
          'John',
        ]);
      });
    });

    group('groupBy and having via QueryBuilder', () {
      test('groupBy(role) with havingRaw filters grouped rows', () async {
        const table = 'qb_group_users';

        await client!.schemaBuilder().createTable(table, (t) {
          t.increments('id');
          t.string('first_name').nullable();
        }).execute();
        await client!.schemaBuilder().alterTable(table, (t) {
          t.string('role').nullable();
        }).execute();

        try {
          await client!.execute(
            client!.queryBuilder().table(table).insert([
              {'first_name': 'Alice', 'role': 'admin'},
              {'first_name': 'Bob', 'role': 'user'},
              {'first_name': 'Carol', 'role': 'admin'},
            ]),
          );

          final rows = await client!.select(
            client!
                .queryBuilder()
                .from(table)
                .select(['role'])
                .groupBy('role')
                .havingRaw('count(*) > ?', [1]),
          );

          expect(rows, hasLength(1));
          expect(rows.first['role'], 'admin');
        } finally {
          await client!.schemaBuilder().dropTableIfExists(table).execute();
        }
      });
    });

    group('whereBetween and whereNotIn', () {
      test('whereBetween filters accounts by balance range', () async {
        final rows = await client!.select(
          client!
              .queryBuilder()
              .table('accounts')
              .whereBetween('balance', [150.0, 300.0])
              .orderBy('balance'),
        );

        expect(rows, hasLength(2));
        expect(rows.first['balance'], closeTo(200.0, 0.001));
        expect(rows.last['balance'], closeTo(300.0, 0.001));
      });

      test('whereNotIn excludes selected first_name values', () async {
        final rows = await client!.select(
          client!
              .queryBuilder()
              .table('users')
              .whereNotIn('first_name', ['Alice'])
              .orderBy('id'),
        );

        expect(rows, hasLength(2));
        expect(rows.map((r) => r['first_name']).toList(), ['John', 'Bob']);
      });
    });
  });
}
