import 'package:knex_dart/src/query/query_builder.dart';
import '../mocks/mock_client.dart';

/// Comparison test for GROUP BY and HAVING
/// Outputs Dart results for comparison with JS test
void main() {
  final client = MockClient();

  print('=== Dart GROUP BY & HAVING Tests ===\n');

  // Test 1: Basic GROUP BY single column
  print('Test 1: Basic GROUP BY single column');
  var builder = QueryBuilder(client).table('orders').groupBy('customer_id');
  var sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 2: GROUP BY multiple columns
  print('Test 2: GROUP BY multiple columns');
  builder = QueryBuilder(
    client,
  ).table('orders').groupBy('customer_id').groupBy('status');
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 3: GROUP BY with WHERE
  print('Test 3: GROUP BY with WHERE');
  builder = QueryBuilder(
    client,
  ).table('orders').where('status', 'completed').groupBy('customer_id');
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 4: Basic HAVING
  print('Test 4: Basic HAVING');
  builder = QueryBuilder(
    client,
  ).table('orders').groupBy('customer_id').having('total', '>', 100);
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 5: HAVING with multiple conditions
  print('Test 5: HAVING with multiple conditions');
  builder = QueryBuilder(client)
      .table('orders')
      .groupBy('customer_id')
      .having('total', '>', 100)
      .having('count', '>=', 5);
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 6: GROUP BY + HAVING combined
  print('Test 6: GROUP BY + HAVING combined');
  builder = QueryBuilder(client)
      .table('orders')
      .groupBy('customer_id')
      .groupBy('status')
      .having('amount', '>=', 1000);
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 7: WHERE + GROUP BY + HAVING + ORDER BY
  print('Test 7: WHERE + GROUP BY + HAVING + ORDER BY');
  builder = QueryBuilder(client)
      .table('orders')
      .where('status', 'active')
      .groupBy('customer_id')
      .having('total', '>', 500)
      .orderBy('total', 'desc');
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 8: Complete query
  print(
    'Test 8: Complete query (WHERE + GROUP BY + HAVING + ORDER BY + LIMIT)',
  );
  builder = QueryBuilder(client)
      .table('orders')
      .where('year', 2024)
      .groupBy('customer_id')
      .having('revenue', '>=', 10000)
      .orderBy('revenue', 'desc')
      .limit(10);
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  print('=== All Dart GROUP BY & HAVING tests complete ===');
}
