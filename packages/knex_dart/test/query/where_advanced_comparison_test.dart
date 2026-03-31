import 'package:knex_dart/src/query/query_builder.dart';
import '../mocks/mock_client.dart';

/// Comparison test for advanced WHERE clauses
/// Outputs Dart results for comparison with JS test
void main() {
  final client = MockClient();

  print('=== Dart Advanced WHERE Tests ===\n');

  // Test 1: Basic orWhere
  print('Test 1: Basic orWhere');
  var builder = QueryBuilder(
    client,
  ).table('users').where('status', 'active').orWhere('role', 'admin');
  var sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 2: Multiple orWhere
  print('Test 2: Multiple orWhere');
  builder = QueryBuilder(client)
      .table('users')
      .where('age', '>', 18)
      .orWhere('verified', true)
      .orWhere('role', 'admin');
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 3: whereNull
  print('Test 3: whereNull');
  builder = QueryBuilder(client).table('users').whereNull('deleted_at');
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 4: whereNotNull
  print('Test 4: whereNotNull');
  builder = QueryBuilder(client).table('users').whereNotNull('email');
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 5: whereNull with AND
  print('Test 5: whereNull with AND');
  builder = QueryBuilder(
    client,
  ).table('users').where('status', 'active').whereNull('banned_at');
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 6: whereIn with strings
  print('Test 6: whereIn with strings');
  builder = QueryBuilder(
    client,
  ).table('users').whereIn('status', ['active', 'pending']);
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 7: whereIn with numbers
  print('Test 7: whereIn with numbers');
  builder = QueryBuilder(client).table('users').whereIn('id', [1, 2, 3, 4, 5]);
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 8: whereNotIn
  print('Test 8: whereNotIn');
  builder = QueryBuilder(
    client,
  ).table('users').whereNotIn('role', ['guest', 'banned']);
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 9: Combined WHERE + OR + NULL
  print('Test 9: Combined WHERE + OR + NULL');
  builder = QueryBuilder(
    client,
  ).table('users').where('status', 'active').orWhereNull('premium_until');
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 10: Combined WHERE + IN + ORDER BY + LIMIT
  print('Test 10: Combined WHERE + IN + ORDER BY + LIMIT');
  builder = QueryBuilder(
    client,
  ).table('users').whereIn('id', [10, 20, 30]).orderBy('name').limit(5);
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  print('=== All Dart advanced WHERE tests complete ===');
}
