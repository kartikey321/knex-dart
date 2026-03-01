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

      // Seed data
      await client!
          .raw('CREATE TABLE users (id INTEGER PRIMARY KEY, first_name TEXT)')
          .execute();
      await client!
          .raw(
            'CREATE TABLE accounts (id INTEGER PRIMARY KEY, user_id INTEGER, balance REAL, logins INTEGER)',
          )
          .execute();

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
  });
}
