import 'package:knex_dart/src/query/query_builder.dart';
import '../mocks/mock_client.dart';

/// Manual verification script for WHERE clause functionality
/// Run: dart run test/query/where_manual_test.dart
void main() {
  final client = MockClient();

  print('=== WHERE Clause Manual Verification ===\n');

  // Test 1: Basic WHERE
  print('Test 1: Basic WHERE');
  final q1 = QueryBuilder(client).table('users').where('status', 'active');
  final sql1 = q1.toSQL();
  print('SQL: ${sql1.sql}');
  print('Bindings: ${sql1.bindings}');
  print('Expected: select * from "users" where "status" = \$1');
  print('Match: ${sql1.sql == 'select * from "users" where "status" = \$1'}');
  print('');

  // Test 2: Multiple WHERE with different operators
  print('Test 2: Multiple WHERE with operators');
  final q2 = QueryBuilder(client)
      .table('users')
      .select(['id', 'name', 'email'])
      .where('age', '>=', 18)
      .where('status', '!=', 'banned')
      .where('email', 'like', '%@gmail.com');
  final sql2 = q2.toSQL();
  print('SQL: ${sql2.sql}');
  print('Bindings: ${sql2.bindings}');
  print(
    'Bindings match: ${sql2.bindings.toString() == "[18, banned, %@gmail.com]"}',
  );
  print('');

  // Test 3: Dotted column names
  print('Test 3: Dotted column names');
  final q3 = QueryBuilder(
    client,
  ).table('orders').where('orders.status', 'shipped');
  final sql3 = q3.toSQL();
  print('SQL: ${sql3.sql}');
  print('Expected: select * from "orders" where "orders"."status" = \$1');
  print(
    'Match: ${sql3.sql == 'select * from "orders" where "orders"."status" = \$1'}',
  );
  print('');

  print('=== All Manual Tests Complete ===');
}
