import 'package:knex_dart/src/query/query_builder.dart';
import '../mocks/mock_client.dart';

void main() {
  final client = MockClient();

  print('=== Dart UPDATE Queries Comparison ===\n');

  // Test 1: Basic update with WHERE
  print('Test 1: Basic update with WHERE');
  var builder = QueryBuilder(
    client,
  ).table('users').where('id', 1).update({'name': 'John Updated'});
  var sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 2: Update multiple columns
  print('Test 2: Update multiple columns');
  builder = QueryBuilder(client).table('users').where('id', 1).update({
    'name': 'Jane Doe',
    'email': 'jane@example.com',
    'age': 30,
  });
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 3: Update with multiple WHERE conditions
  print('Test 3: Update with multiple WHERE conditions');
  builder = QueryBuilder(client)
      .table('users')
      .where('status', 'active')
      .where('role', 'user')
      .update({'last_login': '2024-01-15'});
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 4: Update with RETURNING clause
  print('Test 4: Update with RETURNING clause');
  builder = QueryBuilder(client)
      .table('users')
      .where('id', 1)
      .update({'name': 'Updated Name'})
      .returning(['id', 'name', 'updated_at']);
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 5: Update with NULL value
  print('Test 5: Update with NULL value');
  builder = QueryBuilder(
    client,
  ).table('users').where('id', 1).update({'middle_name': null});
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 6: Increment operation
  print('Test 6: Increment operation');
  builder = QueryBuilder(
    client,
  ).table('users').where('id', 1).increment('login_count', 1);
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 7: Decrement operation
  print('Test 7: Decrement operation');
  builder = QueryBuilder(
    client,
  ).table('products').where('id', 100).decrement('stock', 5);
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 8: Increment with additional updates
  print('Test 8: Increment with additional updates');
  builder = QueryBuilder(client)
      .table('users')
      .where('id', 1)
      .increment('login_count', 1)
      .update({'last_login': '2024-01-15'});
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 9: Update with whereIn
  print('Test 9: Update with whereIn');
  builder = QueryBuilder(
    client,
  ).table('users').whereIn('id', [1, 2, 3]).update({'status': 'inactive'});
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 10: Update with complex WHERE and RETURNING
  print('Test 10: Update with complex WHERE and RETURNING');
  builder = QueryBuilder(client)
      .table('orders')
      .where('status', 'pending')
      .where('created_at', '<', '2024-01-01')
      .update({'status': 'cancelled'})
      .returning(['id', 'status']);
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');
}
