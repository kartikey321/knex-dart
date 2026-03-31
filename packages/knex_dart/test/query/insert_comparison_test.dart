import 'package:knex_dart/src/query/query_builder.dart';
import '../mocks/mock_client.dart';

/// INSERT Queries Comparison Test
/// Outputs Dart results for comparison with JS test
void main() {
  final client = MockClient();

  print('=== Dart INSERT Queries Comparison ===\n');

  // Test 1: Single row insert
  print('Test 1: Single row insert');
  var builder = QueryBuilder(
    client,
  ).table('users').insert({'name': 'John', 'email': 'john@example.com'});
  var sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 2: Multiple rows insert
  print('Test 2: Multiple rows insert');
  builder = QueryBuilder(client).table('users').insert([
    {'name': 'John', 'email': 'john@example.com'},
    {'name': 'Jane', 'email': 'jane@example.com'},
  ]);
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 3: Insert with RETURNING - single column
  print('Test 3: Insert with RETURNING - single column');
  builder = QueryBuilder(client)
      .table('users')
      .insert({'name': 'John', 'email': 'john@example.com'})
      .returning(['id']);
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 4: Insert with RETURNING - multiple columns
  print('Test 4: Insert with RETURNING - multiple columns');
  builder = QueryBuilder(client)
      .table('users')
      .insert({'name': 'John', 'email': 'john@example.com'})
      .returning(['id', 'name', 'created_at']);
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 5: Insert with NULL values
  print('Test 5: Insert with NULL values');
  builder = QueryBuilder(
    client,
  ).table('users').insert({'name': 'John', 'email': null, 'phone': null});
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 6: Insert with different data types
  print('Test 6: Insert with different data types');
  builder = QueryBuilder(client).table('products').insert({
    'name': 'Widget',
    'price': 19.99,
    'quantity': 100,
    'active': true,
  });
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 7: Multiple rows with RETURNING
  print('Test 7: Multiple rows with RETURNING');
  builder = QueryBuilder(client)
      .table('users')
      .insert([
        {'name': 'John', 'age': 30},
        {'name': 'Jane', 'age': 25},
      ])
      .returning(['id', 'name']);
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 8: Insert with schema qualification
  print('Test 8: Insert with schema qualification');
  builder = QueryBuilder(
    client,
  ).table('public.users').insert({'name': 'John', 'email': 'john@example.com'});
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  print('=== All Dart INSERT tests complete ===');
}
