import 'package:knex_dart/src/query/query_builder.dart';
import '../mocks/mock_client.dart';

void main() {
  final client = MockClient();

  print('=== Dart DELETE Queries Comparison ===\n');

  // Test 1: Basic DELETE with WHERE
  print('Test 1: Basic DELETE with WHERE');
  var builder = QueryBuilder(client).table('users').where('id', 1).delete();
  var sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 2: DELETE with multiple WHERE conditions
  print('Test 2: DELETE with multiple WHERE conditions');
  builder = QueryBuilder(client)
      .table('users')
      .where('status', 'inactive')
      .where('created_at', '<', '2020-01-01')
      .delete();
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 3: DELETE with RETURNING
  print('Test 3: DELETE with RETURNING');
  builder = QueryBuilder(
    client,
  ).table('users').where('id', 1).delete(['id', 'name']);
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 4: DELETE with WHERE IN
  print('Test 4: DELETE with WHERE IN');
  builder = QueryBuilder(
    client,
  ).table('users').whereIn('id', [1, 2, 3, 4, 5]).delete();
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 5: DELETE with WHERE NULL
  print('Test 5: DELETE with WHERE NULL');
  builder = QueryBuilder(
    client,
  ).table('users').whereNull('deleted_at').delete();
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 6: DELETE with OR WHERE
  print('Test 6: DELETE with OR WHERE');
  builder = QueryBuilder(client)
      .table('users')
      .where('status', 'banned')
      .orWhere('verified', false)
      .delete();
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 7: DELETE with complex WHERE and RETURNING
  print('Test 7: DELETE with complex WHERE and RETURNING');
  builder = QueryBuilder(client)
      .table('orders')
      .where('status', 'cancelled')
      .where('created_at', '<', '2023-01-01')
      .delete(['id', 'status', 'total']);
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 8: DELETE with schema qualification
  print('Test 8: DELETE with schema qualification');
  builder = QueryBuilder(
    client,
  ).table('public.users').where('id', 100).delete();
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');
}
