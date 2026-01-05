import 'package:knex_dart/src/query/query_builder.dart';
import '../mocks/mock_client.dart';

/// Comparison test for LIMIT/OFFSET clause
/// Outputs Dart results for comparison with JS test
void main() {
  final client = MockClient();

  print('=== Dart LIMIT & OFFSET Tests ===\n');

  // Test 1: LIMIT only
  print('Test 1: LIMIT only');
  var builder = QueryBuilder(client).table('users').limit(10);
  var sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 2: OFFSET only
  print('Test 2: OFFSET only');
  builder = QueryBuilder(client).table('users').offset(20);
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 3: LIMIT + OFFSET together
  print('Test 3: LIMIT + OFFSET together');
  builder = QueryBuilder(client).table('users').limit(10).offset(20);
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 4: LIMIT with WHERE
  print('Test 4: LIMIT with WHERE');
  builder = QueryBuilder(
    client,
  ).table('users').where('status', 'active').limit(5);
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 5: LIMIT with ORDER BY
  print('Test 5: LIMIT with ORDER BY');
  builder = QueryBuilder(
    client,
  ).table('users').orderBy('created_at', 'desc').limit(3);
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 6: Complete pagination
  print('Test 6: Complete pagination (WHERE + ORDER BY + LIMIT + OFFSET)');
  builder = QueryBuilder(client)
      .table('users')
      .where('status', 'active')
      .orderBy('name')
      .limit(25)
      .offset(50);
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  print('=== All Dart LIMIT & OFFSET tests complete ===');
}
