import 'package:knex_dart/src/query/query_builder.dart';
import '../mocks/mock_client.dart';

void main() {
  final client = MockClient();

  print('=== Dart Raw Queries Comparison ===\n');

  // Test 1: Array bindings with ? placeholders
  print('Test 1: Array bindings with ? placeholders');
  var raw = client.raw('select * from users where id = ?', [1]);
  var sql = raw.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 2: Multiple array bindings
  print('Test 2: Multiple array bindings');
  raw = client.raw('select * from users where id = ? and age > ?', [1, 18]);
  sql = raw.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 3: Identifier wrapping with ??
  print('Test 3: Identifier wrapping with ??');
  raw = client.raw('select ?? from ??', ['id', 'users']);
  sql = raw.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 4: Named bindings
  print('Test 4: Named bindings');
  raw = client.raw('select * from users where id = :id', {'id': 1});
  sql = raw.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 5: Named identifier bindings
  print('Test 5: Named identifier bindings');
  raw = client.raw('select :column: from :table:', {
    'column': 'name',
    'table': 'users',
  });
  sql = raw.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 6: Raw in WHERE clause
  print('Test 6: Raw in WHERE clause');
  var builder = QueryBuilder(
    client,
  ).table('users').where(client.raw('age > 18'));
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 7: Raw in SELECT
  print('Test 7: Raw in SELECT');
  builder = QueryBuilder(
    client,
  ).table('users').select(client.raw('count(*) as total'));
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');

  // Test 8: Raw with bindings in WHERE
  print('Test 8: Raw with bindings in WHERE');
  builder = QueryBuilder(
    client,
  ).table('users').where(client.raw('age > ?', [21]));
  sql = builder.toSQL();
  print('SQL: ${sql.sql}');
  print('Bindings: ${sql.bindings}');
  print('');
}
