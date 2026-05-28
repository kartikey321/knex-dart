import 'package:knex_dart/knex_dart.dart';

import 'duckdb_client.dart'
    if (dart.library.js_interop) 'duckdb_client_web.dart';

/// DuckDB Knex wrapper.
///
/// DuckDB is an in-process OLAP SQL database. It supports a rich SQL dialect
/// including window functions, CTEs, FULL OUTER JOIN, LATERAL joins,
/// INTERSECT/EXCEPT, JSON functions, and more.
///
/// DuckDB uses PostgreSQL-compatible `$1`-style positional parameters and
/// double-quoted identifiers.
///
/// Example:
/// ```dart
/// // In-memory database
/// final db = KnexDuckDB.memory();
///
/// // Persistent database
/// final db = KnexDuckDB.file('/path/to/analytics.db');
///
/// await db.executeSchema((s) {
///   s.createTable('sales', (t) {
///     t.increments('id');
///     t.string('region');
///     t.integer('amount');
///   });
/// });
///
/// final result = await db.select(
///   db.queryBuilder()
///       .from('sales')
///       .sum('amount as total')
///       .groupBy('region'),
/// );
///
/// db.close();
/// ```
class KnexDuckDB {
  final DuckDBClient _client;

  KnexDuckDB._(this._client);

  /// Open an in-memory DuckDB database.
  static Future<KnexDuckDB> memory() async =>
      KnexDuckDB._(await DuckDBClient.open(':memory:'));

  /// Open a persistent DuckDB database from a file path.
  static Future<KnexDuckDB> file(String path) async =>
      KnexDuckDB._(await DuckDBClient.open(path));

  /// Executes a SELECT-style query and returns rows.
  Future<List<Map<String, dynamic>>> select(QueryBuilder query) =>
      _client.select(query);

  /// Executes any compiled query and returns rows/result payload.
  Future<List<Map<String, dynamic>>> execute(QueryBuilder query) =>
      _client.execute(query);

  /// Executes an INSERT query.
  Future<List<Map<String, dynamic>>> insert(QueryBuilder query) =>
      _client.insert(query);

  /// Executes an UPDATE query.
  Future<List<Map<String, dynamic>>> update(QueryBuilder query) =>
      _client.update(query);

  /// Executes a DELETE query.
  Future<List<Map<String, dynamic>>> delete(QueryBuilder query) =>
      _client.delete(query);

  /// Execute a raw SQL string directly.
  Future<List<Map<String, dynamic>>> raw(
    String sql, [
    List<dynamic>? bindings,
  ]) => _client.raw(sql, bindings);

  /// Create a query builder scoped to the DuckDB dialect.
  ///
  /// Uses double-quote identifiers and `$N` positional parameters.
  QueryBuilder queryBuilder() => _DuckDBSchemaClient().queryBuilder();

  /// Callable shorthand for `queryBuilder().table(name)`.
  QueryBuilder call([String? tableName]) {
    final builder = queryBuilder();
    return tableName != null ? builder.table(tableName) : builder;
  }

  /// Run a transaction with full ACID guarantees.
  Future<T> trx<T>(Future<T> Function(DuckDBTrxClient trx) callback) =>
      _client.trx(callback);

  /// Execute schema DDL operations.
  Future<void> executeSchema(
    void Function(SchemaBuilder schema) callback,
  ) async {
    final mock = _DuckDBSchemaClient();
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

  /// Close the underlying DuckDB database connection.
  Future<void> close() => _client.close();

  /// Alias for [close], matching the core `Knex` API.
  Future<void> destroy() => close();
}

// ============================================================================
// INTERNAL SCHEMA CLIENT
// ============================================================================

/// Internal DuckDB-flavored schema client for SQL generation only.
///
/// DuckDB is largely PostgreSQL-compatible — double-quote identifiers and
/// `$N` positional parameters.
class _DuckDBSchemaClient extends Client {
  _DuckDBSchemaClient() : super(KnexConfig(client: 'duckdb', connection: {}));

  @override
  String get driverName => 'duckdb';

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

  // DuckDB is PostgreSQL-compatible: double-quote identifiers, $N params
  @override
  String wrapIdentifierImpl(String identifier) => '"$identifier"';

  @override
  String parameterPlaceholder(int index) => '\$$index';

  @override
  String formatValue(value) => value.toString();
}
