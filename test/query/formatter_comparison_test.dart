import 'package:knex_dart/src/query/query_builder.dart';
import '../mocks/mock_client.dart';

/// Formatter Features Comparison Test
/// Outputs Dart results for comparison with JS test
void main() {
  final client = MockClient();

  print('=== Dart Formatter Features Comparison ===\n');

  // Test 1: Object-based column aliasing (single)
  print('Test 1: Object aliasing - single column');
  var builder = QueryBuilder(client).table('users').select([
    {'user_name': 'name'},
  ]);
  var sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 2: Object-based column aliasing (multiple)
  print('Test 2: Object aliasing - multiple columns');
  builder = QueryBuilder(client).table('users').select([
    {'user_id': 'id', 'user_name': 'name'},
  ]);
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 3: Object with dotted column name
  print('Test 3: Object aliasing - dotted column');
  builder = QueryBuilder(client).table('orders').select([
    {'customer_name': 'users.name'},
  ]);
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 4: Array with simple columns
  print('Test 4: Array - simple columns');
  builder = QueryBuilder(client).table('users').select(['id', 'name', 'email']);
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 5: Array with mixed string and object
  print('Test 5: Array - mixed with object alias');
  builder = QueryBuilder(client).table('users').select([
    'id',
    {'user_name': 'name'},
  ]);
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 6: Array with multiple objects
  print('Test 6: Array - multiple object aliases');
  builder = QueryBuilder(client).table('users').select([
    {'user_id': 'id'},
    {'user_name': 'name'},
  ]);
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 7: Complex mixed array
  print('Test 7: Array - complex mix');
  builder = QueryBuilder(client).table('users').select([
    'id',
    {'total_amount': 'amount'},
    'created_at',
  ]);
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 8: whereIn with values list
  print('Test 8: whereIn - values list');
  builder = QueryBuilder(
    client,
  ).table('users').whereIn('status', ['active', 'pending', 'review']);
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 9: Combined - object aliasing with WHERE
  print('Test 9: Combined - object alias + WHERE');
  builder = QueryBuilder(client)
      .table('users')
      .select([
        {'user_name': 'name', 'user_email': 'email'},
      ])
      .where('active', true);
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 10: Combined - mixed array with JOIN
  print('Test 10: Combined - mixed array + JOIN');
  builder = QueryBuilder(client)
      .table('users')
      .select([
        'users.id',
        {'order_total': 'orders.total'},
      ])
      .join('orders', 'users.id', 'orders.user_id');
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  print('=== All Dart formatter tests complete ===');
}
