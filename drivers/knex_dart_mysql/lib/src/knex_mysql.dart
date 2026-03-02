import 'package:knex_dart/src/client/client.dart';
import 'package:knex_dart/src/client/knex_config.dart';
import 'package:knex_dart/src/formatter/formatter.dart';
import 'package:knex_dart/src/query/query_builder.dart';
import 'package:knex_dart/src/query/query_compiler.dart';
import 'package:knex_dart/src/schema/schema_builder.dart';
import 'package:knex_dart/src/schema/schema_compiler.dart';
import 'package:knex_dart/src/transaction/transaction.dart';

import 'mysql_client.dart';

/// MySQL-specific Knex wrapper.
class KnexMySQL {
  final MySQLClient _client;

  KnexMySQL._(this._client);

  /// Create a Knex instance connected to MySQL.
  ///
  /// Example:
  /// ```dart
  /// final db = await KnexMySQL.connect(
  ///   host: 'localhost',
  ///   database: 'myapp',
  ///   user: 'user',
  ///   password: 'password',
  /// );
  ///
  /// final users = await db.select(
  ///   db.queryBuilder().from('users').where('active', '=', true)
  /// );
  ///
  /// await db.close();
  /// ```
  static Future<KnexMySQL> connect({
    required String host,
    int port = 3306,
    required String user,
    String? password,
    required String database,
    bool useSSL = false,
    PoolConfig poolConfig = const PoolConfig(),
  }) async {
    final client = await MySQLClient.connect(
      host: host,
      port: port,
      user: user,
      password: password,
      database: database,
      useSSL: useSSL,
      poolConfig: poolConfig,
    );
    return KnexMySQL._(client);
  }

  Future<List<Map<String, dynamic>>> select(QueryBuilder query) =>
      _client.select(query);

  Future<List<Map<String, dynamic>>> execute(QueryBuilder query) =>
      _client.execute(query);

  Future<List<Map<String, dynamic>>> insert(QueryBuilder query) =>
      _client.insert(query);

  Future<List<Map<String, dynamic>>> update(QueryBuilder query) =>
      _client.update(query);

  Future<List<Map<String, dynamic>>> delete(QueryBuilder query) =>
      _client.delete(query);

  Future<List<Map<String, dynamic>>> raw(
    String sql, [
    List<dynamic>? bindings,
  ]) {
    return _client.raw(sql, bindings);
  }

  /// Create a query builder.
  QueryBuilder queryBuilder() => _MySQLSchemaClient().queryBuilder();

  /// Run a transaction. See [MySQLClient.trx].
  Future<T> trx<T>(Future<T> Function(MySQLTrxClient trx) callback) =>
      _client.trx(callback);

  /// Execute schema DDL operations.
  Future<void> executeSchema(
    void Function(SchemaBuilder schema) callback,
  ) async {
    final mysqlMock = _MySQLSchemaClient();
    final builder = mysqlMock.schemaBuilder();
    callback(builder);
    final statements = builder.toSQL();
    for (final stmt in statements) {
      await _client.raw(
        stmt['sql'] as String,
        stmt['bindings'] as List<dynamic>?,
      );
    }
  }

  Future<void> close() => _client.close();
}

// ============================================================================
// INTERNAL SCHEMA CLIENT
// Lightweight "stub" client used only for SQL generation.
// Does not connect to any database.
// ============================================================================

/// Internal MySQL-flavored schema client for SQL generation only.
class _MySQLSchemaClient extends Client {
  _MySQLSchemaClient() : super(KnexConfig(client: 'mysql2', connection: {}));

  @override
  String get driverName => 'mysql2';

  @override
  SchemaCompiler schemaCompiler(SchemaBuilder builder) =>
      SchemaCompiler(this, builder);

  @override
  QueryBuilder queryBuilder() => QueryBuilder(this);

  @override
  Future<dynamic> rawQuery(String sql, List<dynamic> bindings) =>
      throw UnimplementedError();

  @override
  Future<List<Map<String, dynamic>>> query(
    dynamic connection,
    String sql,
    List<dynamic> bindings,
  ) => throw UnimplementedError();

  @override
  Stream<Map<String, dynamic>> streamQuery(
    dynamic connection,
    String sql,
    List<dynamic> bindings,
  ) => throw UnimplementedError();

  @override
  Future<void> destroy() => Future.value();

  @override
  Future<Transaction> transaction([TransactionConfig? config]) =>
      throw UnimplementedError();

  @override
  void initializeDriver() {}

  @override
  void initializePool([poolConfig]) {}

  @override
  QueryCompiler queryCompiler(QueryBuilder builder) =>
      QueryCompiler(this, builder);

  @override
  dynamic formatter(dynamic builder) => Formatter(this, builder);

  @override
  SchemaBuilder schemaBuilder() => SchemaBuilder(this);

  @override
  Future acquireConnection() => throw UnimplementedError();

  @override
  Future<void> releaseConnection(connection) => Future.value();

  @override
  String wrapIdentifierImpl(String identifier) => '`$identifier`';

  @override
  String parameterPlaceholder(int index) => '?';

  @override
  String formatValue(value) => value.toString();
}
