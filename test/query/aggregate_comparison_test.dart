import 'package:test/test.dart';
import 'package:knex_dart/src/query/query_builder.dart';
import 'package:knex_dart/src/query/query_compiler.dart';
import 'package:knex_dart/src/query/aggregate_options.dart';
import '../mocks/mock_client.dart';

void main() {
  group('Aggregate Functions - JS Comparison', () {
    late MockClient client;

    setUp(() {
      client = MockClient();
    });

    test('Test 1: Basic count', () {
      final qb = QueryBuilder(client);
      qb.table('users').count('*');
      final compiler = QueryCompiler(client, qb);
      final result = compiler.toSQL();

      print('Test 1: ${result.sql}');
      expect(result.sql, equals('select count(*) from "users"'));
      expect(result.bindings, isEmpty);
    });

    test('Test 2: Count with explicit alias', () {
      final qb = QueryBuilder(client);
      qb.table('users').count('*', AggregateOptions(as: 'total'));
      final compiler = QueryCompiler(client, qb);
      final result = compiler.toSQL();

      print('Test 2: ${result.sql}');
      expect(result.sql, equals('select count(*) as "total" from "users"'));
      expect(result.bindings, isEmpty);
    });

    test('Test 3: Sum with column', () {
      final qb = QueryBuilder(client);
      qb.table('orders').sum('amount');
      final compiler = QueryCompiler(client, qb);
      final result = compiler.toSQL();

      print('Test 3: ${result.sql}');
      expect(result.sql, equals('select sum("amount") from "orders"'));
      expect(result.bindings, isEmpty);
    });

    test('Test 4: Avg with alias', () {
      final qb = QueryBuilder(client);
      qb.table('products').avg('price', AggregateOptions(as: 'average_price'));
      final compiler = QueryCompiler(client, qb);
      final result = compiler.toSQL();

      print('Test 4: ${result.sql}');
      expect(
        result.sql,
        equals('select avg("price") as "average_price" from "products"'),
      );
      expect(result.bindings, isEmpty);
    });

    test('Test 5: Min and max', () {
      final qb = QueryBuilder(client);
      qb.table('transactions').min('created_at').max('updated_at');
      final compiler = QueryCompiler(client, qb);
      final result = compiler.toSQL();

      print('Test 5: ${result.sql}');
      expect(
        result.sql,
        equals(
          'select min("created_at"), max("updated_at") from "transactions"',
        ),
      );
      expect(result.bindings, isEmpty);
    });

    test('Test 6: Count distinct', () {
      final qb = QueryBuilder(client);
      qb.table('orders').countDistinct('user_id');
      final compiler = QueryCompiler(client, qb);
      final result = compiler.toSQL();

      print('Test 6: ${result.sql}');
      expect(
        result.sql,
        equals('select count(distinct "user_id") from "orders"'),
      );
      expect(result.bindings, isEmpty);
    });

    test('Test 7: Sum distinct with alias', () {
      final qb = QueryBuilder(client);
      qb
          .table('payments')
          .sumDistinct('amount', AggregateOptions(as: 'unique_total'));
      final compiler = QueryCompiler(client, qb);
      final result = compiler.toSQL();

      print('Test 7: ${result.sql}');
      expect(
        result.sql,
        equals(
          'select sum(distinct "amount") as "unique_total" from "payments"',
        ),
      );
      expect(result.bindings, isEmpty);
    });

    test('Test 8: Avg distinct', () {
      final qb = QueryBuilder(client);
      qb.table('scores').avgDistinct('points');
      final compiler = QueryCompiler(client, qb);
      final result = compiler.toSQL();

      print('Test 8: ${result.sql}');
      expect(result.sql, equals('select avg(distinct "points") from "scores"'));
      expect(result.bindings, isEmpty);
    });

    test('Test 9: Count with inline alias', () {
      final qb = QueryBuilder(client);
      qb.table('users').count('id as user_count');
      final compiler = QueryCompiler(client, qb);
      final result = compiler.toSQL();

      print('Test 9: ${result.sql}');
      expect(
        result.sql,
        equals('select count("id") as "user_count" from "users"'),
      );
      expect(result.bindings, isEmpty);
    });

    test('Test 10: Aggregate with WHERE clause', () {
      final qb = QueryBuilder(client);
      qb
          .table('orders')
          .count('*', AggregateOptions(as: 'total'))
          .where('status', '=', 'completed');
      final compiler = QueryCompiler(client, qb);
      final result = compiler.toSQL();

      print('Test 10: ${result.sql}');
      expect(
        result.sql,
        equals('select count(*) as "total" from "orders" where "status" = \$1'),
      );
      expect(result.bindings, equals(['completed']));
    });

    test('Test 11: Multiple aggregates', () {
      final qb = QueryBuilder(client);
      qb
          .table('sales')
          .count('*', AggregateOptions(as: 'total_sales'))
          .sum('amount', AggregateOptions(as: 'total_amount'))
          .avg('amount', AggregateOptions(as: 'average_amount'));
      final compiler = QueryCompiler(client, qb);
      final result = compiler.toSQL();

      print('Test 11: ${result.sql}');
      expect(
        result.sql,
        equals(
          'select count(*) as "total_sales", sum("amount") as "total_amount", avg("amount") as "average_amount" from "sales"',
        ),
      );
      expect(result.bindings, isEmpty);
    });

    test('Test 12: Count distinct with multiple columns', () {
      final qb = QueryBuilder(client);
      qb.table('events').countDistinct(['user_id', 'event_type']);
      final compiler = QueryCompiler(client, qb);
      final result = compiler.toSQL();

      print('Test 12: ${result.sql}');
      expect(
        result.sql,
        equals('select count(distinct "user_id", "event_type") from "events"'),
      );
      expect(result.bindings, isEmpty);
    });
  });
}
