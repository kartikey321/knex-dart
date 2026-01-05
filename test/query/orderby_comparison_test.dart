import 'package:knex_dart/src/query/query_builder.dart';
import '../mocks/mock_client.dart';

/// Comparison test for ORDER BY clause
/// Outputs Dart results for comparison with JS test
void main() {
  final client = MockClient();

  print('=== Dart ORDER BY Tests ===\n');

  // Test 1: ORDER BY single column (default ASC)
  print('Test 1: ORDER BY single column (default ASC)');
  var builder = QueryBuilder(client).table('users').orderBy('name');
  var sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 2: ORDER BY with DESC
  print('Test 2: ORDER BY with DESC');
  builder = QueryBuilder(client).table('users').orderBy('created_at', 'desc');
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 3: Multiple ORDER BY columns
  print('Test 3: Multiple ORDER BY columns');
  builder = QueryBuilder(
    client,
  ).table('users').orderBy('status').orderBy('name', 'desc');
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 4: ORDER BY with WHERE
  print('Test 4: ORDER BY with WHERE');
  builder = QueryBuilder(
    client,
  ).table('users').where('active', true).orderBy('name');
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 5: ORDER BY with dotted column
  print('Test 5: ORDER BY with dotted column');
  builder = QueryBuilder(
    client,
  ).table('users').orderBy('users.created_at', 'desc');
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 6: ORDER BY with SELECT columns
  print('Test 6: ORDER BY with SELECT columns');
  builder = QueryBuilder(
    client,
  ).table('users').select(['id', 'name']).orderBy('name');
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test  7: ORDER BY with WHERE and SELECT
  print('Test 7: ORDER BY with WHERE and SELECT');
  builder = QueryBuilder(client)
      .table('users')
      .select(['id', 'name'])
      .where('status', 'active')
      .orderBy('name', 'desc');
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 8: Three ORDER BY columns
  print('Test 8: Three ORDER BY columns');
  builder = QueryBuilder(client)
      .table('users')
      .orderBy('status')
      .orderBy('created_at', 'desc')
      .orderBy('name');
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  print('=== All Dart ORDER BY tests complete ===');
}
