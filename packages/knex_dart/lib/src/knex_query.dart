import 'package:knex_dart_capabilities/knex_dart_capabilities.dart';

import 'client/client.dart';
import 'client/knex_config.dart';
import 'formatter/formatter.dart';
import 'query/query_builder.dart';
import 'query/query_compiler.dart';
import 'schema/schema_builder.dart';
import 'schema/schema_compiler.dart';
import 'transaction/transaction.dart';

/// Dialect-only query and schema building — no database connection needed.
///
/// Use this when you want to generate SQL for a specific dialect without
/// installing any driver package. The returned [QueryBuilder] and
/// [SchemaBuilder] produce dialect-correct SQL (identifiers, parameter
/// placeholders) but cannot execute queries.
///
/// ```dart
/// import 'package:knex_dart/knex_dart.dart';
///
/// // Build a postgres query — no postgres driver needed
/// final q = KnexQuery.forDialect(KnexDialect.postgres);
/// final sql = q.from('users')
///     .where('active', '=', true)
///     .select(['id', 'email'])
///     .toSQL();
/// print(sql.sql);      // select "id", "email" from "users" where "active" = $1
/// print(sql.bindings); // [true]
///
/// // Or by driver name (knex.js-style)
/// final q2 = KnexQuery.forClient('mysql2');
/// final sql2 = q2.from('orders').where('status', '=', 'open').toSQL();
/// print(sql2.sql); // select * from `orders` where `status` = ?
/// ```
class KnexQuery {
  final _DialectClient _client;

  KnexQuery._(this._client);

  /// Create a query builder for [dialect].
  factory KnexQuery.forDialect(KnexDialect dialect) =>
      KnexQuery._(_DialectClient._forDialect(dialect));

  /// Create a query builder by driver/client name.
  ///
  /// Accepts the same strings as [dialectFromDriverName]:
  /// `'pg'`, `'postgres'`, `'mysql'`, `'mysql2'`, `'sqlite'`, `'sqlite3'`,
  /// `'mariadb'`, `'redshift'`, `'cockroachdb'`, `'turso'`, `'libsql'`,
  /// `'d1'`, `'duckdb'`, `'snowflake'`, `'bigquery'`.
  factory KnexQuery.forClient(String clientName) {
    final dialect = dialectFromDriverName(clientName);
    if (dialect == null) {
      throw ArgumentError.value(
        clientName,
        'clientName',
        'Unknown client/dialect. Supported: pg, mysql2, sqlite3, mariadb, '
            'redshift, turso, d1, duckdb, snowflake, bigquery',
      );
    }
    return KnexQuery.forDialect(dialect);
  }

  /// The active dialect.
  KnexDialect get dialect => _client._dialect;

  /// The driver name string (e.g. `'pg'`, `'mysql2'`, `'sqlite3'`).
  String get driverName => _client.driverName;

  /// Return a new [QueryBuilder] scoped to this dialect.
  QueryBuilder from(String table) => _client.queryBuilder().table(table);

  /// Return a fresh [QueryBuilder] (no table set yet).
  QueryBuilder queryBuilder() => _client.queryBuilder();

  /// Return a [SchemaBuilder] for DDL generation.
  SchemaBuilder schemaBuilder() => _client.schemaBuilder();
}

// ─── Internal stub client ────────────────────────────────────────────────────

/// Maps [KnexDialect] → identifier quoting + parameter placeholder style.
class _DialectClient extends Client {
  final KnexDialect _dialect;

  _DialectClient._(
    KnexDialect dialect, {
    required String driverStr,
  })  : _dialect = dialect,
        super(KnexConfig(client: driverStr, connection: {}));

  factory _DialectClient._forDialect(KnexDialect dialect) {
    return _DialectClient._(dialect, driverStr: _driverStr(dialect));
  }

  static String _driverStr(KnexDialect dialect) {
    switch (dialect) {
      case KnexDialect.postgres:
        return 'pg';
      case KnexDialect.mysql:
        return 'mysql2';
      case KnexDialect.sqlite:
        return 'sqlite3';
      case KnexDialect.mariadb:
        return 'mariadb';
      case KnexDialect.redshift:
        return 'redshift';
      case KnexDialect.turso:
        return 'turso';
      case KnexDialect.d1:
        return 'd1';
      case KnexDialect.duckdb:
        return 'duckdb';
      case KnexDialect.snowflake:
        return 'snowflake';
      case KnexDialect.bigquery:
        return 'bigquery';
      case KnexDialect.mssql:
        return 'mssql';
    }
  }

  @override
  String get driverName => _driverStr(_dialect);

  // ── Identifier quoting ──────────────────────────────────────────────────

  @override
  String wrapIdentifierImpl(String identifier) {
    switch (_dialect) {
      case KnexDialect.mysql:
      case KnexDialect.mariadb:
      case KnexDialect.bigquery:
        return '`${identifier.replaceAll('`', '``')}`';
      default:
        return '"${identifier.replaceAll('"', '""')}"';
    }
  }

  // ── Parameter placeholders ───────────────────────────────────────────────

  @override
  String parameterPlaceholder(int index) {
    switch (_dialect) {
      case KnexDialect.postgres:
      case KnexDialect.redshift:
      case KnexDialect.duckdb:
        return '\$$index';
      default:
        return '?';
    }
  }

  // ── Stub implementations (no DB connection) ─────────────────────────────

  @override
  QueryBuilder queryBuilder() => QueryBuilder(this);

  @override
  QueryCompiler queryCompiler(QueryBuilder builder) =>
      QueryCompiler(this, builder);

  @override
  dynamic formatter(dynamic builder) => Formatter(this, builder);

  @override
  SchemaBuilder schemaBuilder() => SchemaBuilder(this);

  @override
  SchemaCompiler schemaCompiler(SchemaBuilder builder) =>
      SchemaCompiler(this, builder);

  @override
  String formatValue(value) => value.toString();

  @override
  void initializeDriver() {}

  @override
  void initializePool([poolConfig]) {}

  @override
  Future<dynamic> rawQuery(String sql, List<dynamic> bindings) =>
      throw UnsupportedError(
        'KnexQuery is for SQL generation only — use a driver package to execute queries.',
      );

  @override
  Future<List<Map<String, dynamic>>> query(
    dynamic connection,
    String sql,
    List<dynamic> bindings,
  ) => throw UnsupportedError('KnexQuery does not execute queries.');

  @override
  Stream<Map<String, dynamic>> streamQuery(
    dynamic connection,
    String sql,
    List<dynamic> bindings,
  ) => throw UnsupportedError('KnexQuery does not execute queries.');

  @override
  Future<void> destroy() => Future.value();

  @override
  Future<Transaction> transaction([TransactionConfig? config]) =>
      throw UnsupportedError('KnexQuery does not support transactions.');

  @override
  Future acquireConnection() =>
      throw UnsupportedError('KnexQuery does not connect to any database.');

  @override
  Future<void> releaseConnection(connection) => Future.value();
}
