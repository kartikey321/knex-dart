import 'package:knex_dart/src/query/query_builder.dart';
import '../mocks/mock_client.dart';

/// Advanced JOINs Comparison Test
/// Outputs Dart results for comparison with JS test
void main() {
  final client = MockClient();

  print('=== Dart Advanced JOINs Comparison ===\n');

  // Test 1: Callback-based join - simple ON
  print('Test 1: Callback-based join - simple ON');
  var builder = QueryBuilder(client).table('users').join('orders', (j) {
    j.on('users.id', 'orders.user_id');
  });
  var sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 2: Callback-based join - multiple AND ON
  print('Test 2: Callback-based join - multiple AND ON');
  builder = QueryBuilder(client).table('users').join('orders', (j) {
    j.on('users.id', 'orders.user_id').andOn('users.region', 'orders.region');
  });
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 3: Callback-based join - OR ON
  print('Test 3: Callback-based join - OR ON');
  builder = QueryBuilder(client).table('users').join('orders', (j) {
    j.on('users.id', 'orders.user_id').orOn('users.email', 'orders.email');
  });
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 4: Callback-based join - mixed AND/OR
  print('Test 4: Callback-based join - mixed AND/OR');
  builder = QueryBuilder(client).table('users').join('orders', (j) {
    j
        .on('users.id', 'orders.user_id')
        .andOn('users.active', 'orders.active')
        .orOn('users.status', 'premium');
  });
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 5: Callback-based join - with explicit operators
  print('Test 5: Callback-based join - with explicit operators');
  builder = QueryBuilder(client).table('users').join('orders', (j) {
    j.on('users.id', '=', 'orders.user_id').andOn('orders.total', '>', '1000');
  });
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 6: LEFT JOIN with callback
  print('Test 6: LEFT JOIN with callback');
  builder = QueryBuilder(client).table('users').leftJoin('profiles', (j) {
    j.on('users.id', 'profiles.user_id');
  });
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 7: RIGHT JOIN with callback
  print('Test 7: RIGHT JOIN with callback');
  builder = QueryBuilder(client).table('orders').rightJoin('products', (j) {
    j.on('orders.product_id', 'products.id');
  });
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 8: FULL OUTER JOIN
  print('Test 8: FULL OUTER JOIN');
  builder = QueryBuilder(
    client,
  ).table('users').fullOuterJoin('profiles', 'users.id', 'profiles.user_id');
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 9: CROSS JOIN
  print('Test 9: CROSS JOIN');
  builder = QueryBuilder(client).table('users').crossJoin('categories');
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 10: Mixed simple and callback joins
  print('Test 10: Mixed simple and callback joins');
  builder = QueryBuilder(client)
      .table('users')
      .join('orders', 'users.id', 'orders.user_id')
      .leftJoin('reviews', (j) {
        j.on('orders.id', 'reviews.order_id');
      });
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 11: Callback join with WHERE and ORDER BY
  print('Test 11: Callback join with WHERE and ORDER BY');
  builder = QueryBuilder(client)
      .table('users')
      .join('orders', (j) {
        j.on('users.id', 'orders.user_id').andOn('orders.status', 'completed');
      })
      .where('users.active', true)
      .orderBy('users.created_at', 'desc');
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 12: Complex callback join with all clauses
  print('Test 12: Complex callback join with all clauses');
  builder = QueryBuilder(client)
      .table('users')
      .select(['users.id', 'users.name'])
      .join('orders', (j) {
        j
            .on('users.id', 'orders.user_id')
            .andOn('users.region', 'orders.region');
      })
      .where('orders.status', 'completed')
      .groupBy('users.id')
      .groupBy('users.name')
      .orderBy('users.name')
      .limit(10);
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  print('=== All Dart advanced JOIN tests complete ===');
}
