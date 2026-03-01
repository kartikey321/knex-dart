import 'package:knex_dart/src/client/client.dart';
import 'package:knex_dart/src/client/knex_config.dart';
import 'package:knex_dart/src/query/query_builder.dart';
import 'package:knex_dart/src/query/query_compiler.dart';
import 'package:knex_dart/src/formatter/formatter.dart';
import 'package:knex_dart/src/schema/schema_builder.dart';
import 'package:knex_dart/src/schema/schema_compiler.dart';
import 'package:knex_dart/src/transaction/transaction.dart';

/// Mock client for testing
class MockClient extends Client {
  final String _driverName;

  MockClient({String driverName = 'pg'})
    : _driverName = driverName,
      super(KnexConfig(client: 'mock', connection: {}));

  @override
  String get driverName => _driverName;

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
      SchemaCompiler(this, builder);

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
  String wrapIdentifierImpl(String value) {
    if (value == '*') return value;
    if (_driverName == 'mysql' || _driverName == 'mysql2') {
      return '`$value`';
    }
    return '"$value"';
  }

  @override
  String parameterPlaceholder(int index) => '\$$index'; // PostgreSQL style

  @override
  String formatValue(value) => value.toString();
}
