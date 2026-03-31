import 'package:knex_dart/src/query/query_builder.dart';
import '../mocks/mock_client.dart';

/// Comparison test for DISTINCT
/// Outputs Dart results for comparison with JS test
void main() {
  final client = MockClient();

  print('=== Dart DISTINCT Tests ===\n');

  // Test 1: Basic DISTINCT
  print('Test 1: Basic DISTINCT');
  var builder = QueryBuilder(client).table('users').distinct();
  var sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 2: DISTINCT with WHERE
  print('Test 2: DISTINCT with WHERE');
  builder = QueryBuilder(
    client,
  ).table('users').distinct().where('active', true);
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 3: DISTINCT with specific columns
  print('Test 3: DISTINCT with specific columns');
  builder = QueryBuilder(client).table('users').distinct(['role']);
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 4: DISTINCT with ORDER BY
  print('Test 4: DISTINCT with ORDER BY');
  builder = QueryBuilder(client).table('users').distinct().orderBy('name');
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 5: DISTINCT with WHERE + ORDER BY + LIMIT
  print('Test 5: DISTINCT with WHERE + ORDER BY + LIMIT');
  builder = QueryBuilder(client)
      .table('users')
      .distinct()
      .where('status', 'active')
      .orderBy('created_at', 'desc')
      .limit(10);
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  print('=== All Dart DISTINCT tests complete ===');
}
