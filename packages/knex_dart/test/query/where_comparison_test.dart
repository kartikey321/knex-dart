import 'package:knex_dart/src/query/query_builder.dart';
import '../mocks/mock_client.dart';

/// Side-by-side comparison test for WHERE clause
/// Outputs Dart results for comparison with JS test
void main() {
  final client = MockClient();

  print('=== Dart WHERE Clause Tests ===\n');

  // Test 1: WHERE with string value
  print('Test 1: WHERE column = string');
  var builder = QueryBuilder(client).table('users').where('status', 'active');
  var sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 2: WHERE with number value
  print('Test 2: WHERE column = number');
  builder = QueryBuilder(client).table('users').where('age', 25);
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 3: WHERE with explicit operator
  print('Test 3: WHERE column > value');
  builder = QueryBuilder(client).table('users').where('age', '>', 18);
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 4: SELECT columns with WHERE
  print('Test 4: SELECT columns WHERE');
  builder = QueryBuilder(
    client,
  ).table('users').select(['id', 'name']).where('status', 'active');
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 5: Multiple WHERE clauses (AND)
  print('Test 5: Multiple WHERE (AND)');
  builder = QueryBuilder(
    client,
  ).table('users').where('status', 'active').where('age', '>=', 18);
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 6: WHERE with dotted column name
  print('Test 6: WHERE with dotted column');
  builder = QueryBuilder(client).table('users').where('users.status', 'active');
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 7: WHERE with != operator
  print('Test 8: WHERE with != operator');
  builder = QueryBuilder(client).table('users').where('status', '!=', 'banned');
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 8: WHERE with < operator
  print('Test 9: WHERE with < operator');
  builder = QueryBuilder(client).table('posts').where('views', '<', 1000);
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 9: WHERE with LIKE operator
  print('Test 10: WHERE with LIKE operator');
  builder = QueryBuilder(
    client,
  ).table('users').where('email', 'like', '%@gmail.com');
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  print('=== All Dart WHERE tests complete ===');
}
