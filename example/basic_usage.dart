// Example: Generate SQL queries with Knex Dart
//
// This example shows how to use Knex Dart to generate SQL queries.
// Note: This is Phase 1 - query generation only. Database execution
// (Phase 2) is in development.

import 'package:knex_dart/src/client/client.dart';
import 'package:knex_dart/src/client/knex_config.dart';
import 'package:knex_dart/src/formatter/formatter.dart';
import 'package:knex_dart/src/query/aggregate_options.dart';
import 'package:knex_dart/src/query/query_builder.dart';
import 'package:knex_dart/src/query/query_compiler.dart';
import 'package:knex_dart/src/raw.dart';
import 'package:knex_dart/src/schema/schema_builder.dart';
import 'package:knex_dart/src/schema/schema_compiler.dart';
import 'package:knex_dart/src/transaction/transaction.dart';

/// Simple mock client for query generation examples
class ExampleClient extends Client {
  ExampleClient() : super(KnexConfig(client: 'postgres', connection: {}));

  @override
  String get driverName => 'postgres';

  @override
  void initializeDriver() {}

  @override
  void initializePool([poolConfig]) {}

  @override
  QueryBuilder queryBuilder() => QueryBuilder(this);

  @override
  QueryCompiler queryCompiler(QueryBuilder builder) {
    return QueryCompiler(this, builder);
  }

  @override
  Formatter formatter(dynamic builder) {
    return Formatter(this, builder);
  }

  @override
  SchemaBuilder schemaBuilder() => SchemaBuilder(this);

  @override
  SchemaCompiler schemaCompiler(SchemaBuilder builder) =>
      throw UnimplementedError();

  @override
  Future<Transaction> transaction([config]) => throw UnimplementedError();

  @override
  Future rawQuery(String sql, List bindings) => throw UnimplementedError();

  @override
  Future<List<Map<String, dynamic>>> query(
    connection,
    String sql,
    List bindings,
  ) => throw UnimplementedError();

  @override
  Stream<Map<String, dynamic>> streamQuery(
    connection,
    String sql,
    List bindings,
  ) => throw UnimplementedError();

  @override
  Future acquireConnection() => throw UnimplementedError();

  @override
  Future<void> releaseConnection(connection) => Future.value();

  @override
  Future<void> _destroyPool() => Future.value();

  @override
  String wrapIdentifierImpl(String identifier) => '"$identifier"';

  @override
  String parameterPlaceholder(int index) => '\$$index'; // PostgreSQL style

  @override
  String formatValue(value) => value.toString();
}

void main() {
  final client = ExampleClient();

  print('=== Knex Dart Query Generation Examples ===\n');

  // Example 1: Basic SELECT
  print('1. Basic SELECT:');
  var query = QueryBuilder(client)
      .table('users')
      .select(['id', 'name', 'email'])
      .where('active', '=', true)
      .orderBy('created_at', 'desc')
      .limit(10);

  var sql = query.toSQL();
  print('   SQL: ${sql.sql}');
  print('   Bindings: ${sql.bindings}\n');

  // Example 2: JOIN
  print('2. JOIN Query:');
  query = QueryBuilder(client)
      .table('users')
      .join('orders', 'users.id', 'orders.user_id')
      .select(['users.name', 'orders.total'])
      .where('orders.status', '=', 'completed');

  sql = query.toSQL();
  print('   SQL: ${sql.sql}');
  print('   Bindings: ${sql.bindings}\n');

  // Example 3: Aggregates
  print('3. Aggregate Query:');
  query = QueryBuilder(client)
      .table('sales')
      .count('*', AggregateOptions(as: 'total_sales'))
      .sum('amount', AggregateOptions(as: 'revenue'))
      .where('status', '=', 'completed');

  sql = query.toSQL();
  print('   SQL: ${sql.sql}');
  print('   Bindings: ${sql.bindings}\n');

  // Example 4: INSERT
  print('4. INSERT Query:');
  query = QueryBuilder(client)
      .table('users')
      .insert({'name': 'John Doe', 'email': 'john@example.com'})
      .returning(['id']);

  sql = query.toSQL();
  print('   SQL: ${sql.sql}');
  print('   Bindings: ${sql.bindings}\n');

  // Example 5: UPDATE
  print('5. UPDATE Query:');
  query = QueryBuilder(client).table('users').where('id', '=', 1).update({
    'name': 'Jane Doe',
    'email': 'jane@example.com',
  });

  sql = query.toSQL();
  print('   SQL: ${sql.sql}');
  print('   Bindings: ${sql.bindings}\n');

  // Example 6: DELETE
  print('6. DELETE Query:');
  query = QueryBuilder(client).table('users').where('id', '=', 1).delete();

  sql = query.toSQL();
  print('   SQL: ${sql.sql}');
  print('   Bindings: ${sql.bindings}\n');

  // Example 7: Raw expressions
  print('7. Raw SELECT with custom expression:');
  query = QueryBuilder(client)
      .table('users')
      .select([Raw(client).set("CONCAT(first_name, ' ', last_name)")])
      .where('age', '>', 18);

  sql = query.toSQL();
  print('   SQL: ${sql.sql}');
  print('   Bindings: ${sql.bindings}\n');

  print('━' * 60);
  print('Note: These are generated SQL queries only.');
  print('Phase 2 (database execution) is in development.');
  print('━' * 60);
}
