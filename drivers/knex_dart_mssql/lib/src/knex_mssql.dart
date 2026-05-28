import 'package:knex_dart/knex_dart.dart';

import 'mssql_client.dart';

export 'mssql_client.dart' show MssqlTrxClient;

/// SQL Server Knex wrapper.
///
/// Example:
/// ```dart
/// import 'package:knex_dart_mssql/knex_dart_mssql.dart';
///
/// final db = await KnexMssql.connect(
///   host: 'localhost',
///   database: 'AdventureWorks',
///   username: 'sa',
///   password: 's3cr3t!',
/// );
///
/// final rows = await db.select(
///   db.queryBuilder().from('users').where('active', '=', 1).limit(10),
/// );
///
/// await db.close();
/// ```
///
/// **Note**: Requires FreeTDS to be installed:
///   - macOS:  `brew install freetds`
///   - Ubuntu: `sudo apt-get install -y freetds-dev libct4`
class KnexMssql {
  final MssqlClient _client;

  KnexMssql._(this._client);

  /// Connect to a SQL Server instance.
  static Future<KnexMssql> connect({
    required String host,
    String port = '1433',
    required String database,
    required String username,
    required String password,
    int timeoutSeconds = 15,
  }) async {
    final client = await MssqlClient.connect(
      host: host,
      port: port,
      database: database,
      username: username,
      password: password,
      timeoutSeconds: timeoutSeconds,
    );
    return KnexMssql._(client);
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

  /// Create a raw SQL fragment for use inside QueryBuilder clauses.
  Raw raw(
    String sql, [
    List<dynamic>? bindings,
  ]) => _MssqlSchemaClient().raw(sql, bindings);

  /// Execute a raw SQL statement directly.
  Future<List<Map<String, dynamic>>> executeRaw(
    String sql, [
    List<dynamic>? bindings,
  ]) => _client.raw(sql, bindings);

  /// Create a query builder scoped to the SQL Server dialect.
  ///
  /// Uses square-bracket identifiers and `?` positional parameters (rewritten
  /// to `@p1`-style before sending to SQL Server).
  QueryBuilder queryBuilder() => _MssqlSchemaClient().queryBuilder();

  /// Callable shorthand for `queryBuilder().table(name)`.
  QueryBuilder call([String? tableName]) {
    final builder = queryBuilder();
    return tableName != null ? builder.table(tableName) : builder;
  }

  /// Run a transaction with ACID guarantees.
  Future<T> trx<T>(Future<T> Function(MssqlTrxClient trx) callback) =>
      _client.trx(callback);

  /// Execute schema DDL operations.
  Future<void> executeSchema(
    void Function(SchemaBuilder schema) callback,
  ) async {
    final mock = _MssqlSchemaClient();
    final builder = mock.schemaBuilder();
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

  /// Alias for [close], matching the core `Knex` API.
  Future<void> destroy() => close();
}

// ============================================================================
// INTERNAL SCHEMA CLIENT
// ============================================================================

class _MssqlSchemaClient extends Client {
  _MssqlSchemaClient()
      : super(KnexConfig(client: 'mssql', connection: {}));

  @override
  String get driverName => 'mssql';

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

  // SQL Server uses bracketed identifiers and ? params
  // which we rewrite to @p1 style in MssqlClient._rewriteParams.
  @override
  String wrapIdentifierImpl(String identifier) =>
      '[${identifier.replaceAll(']', ']]')}]';

  @override
  String parameterPlaceholder(int index) => '?';

  @override
  String formatValue(value) => value.toString();
}
