import 'dart:async';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';

import 'knex_config.dart';
import '../query/query_builder.dart';
import '../query/query_compiler.dart';
import '../schema/schema_builder.dart';
import '../schema/schema_compiler.dart';
import '../transaction/transaction.dart';
import '../raw.dart';
import '../ref.dart';

/// Abstract base class for database clients
///
/// Each database dialect (PostgreSQL, MySQL, SQLite, etc.) extends this class
/// to provide dialect-specific implementations of query compilation, connection
/// management, and SQL generation.
abstract class Client {
  /// Configuration for this client
  final KnexConfig config;

  /// Logger for this client
  final Logger logger;

  /// Connection pool (lazy-initialized)
  dynamic _pool;

  /// Event stream controllers
  final _queryController = StreamController<QueryEvent>.broadcast();
  final _queryErrorController = StreamController<QueryErrorEvent>.broadcast();
  final _queryResponseController =
      StreamController<QueryResponseEvent>.broadcast();

  /// Stream of query events
  Stream<QueryEvent> get onQuery => _queryController.stream;

  /// Stream of query error events
  Stream<QueryErrorEvent> get onQueryError => _queryErrorController.stream;

  /// Stream of query response events
  Stream<QueryResponseEvent> get onQueryResponse =>
      _queryResponseController.stream;

  Client(this.config) : logger = Logger('knex.${config.client}') {
    if (config.debug) {
      // Enable debug logging
      Logger.root.level = Level.ALL;
      Logger.root.onRecord.listen((record) {
        print('${record.level.name}: ${record.time}: ${record.message}');
      });
    }
  }

  /// Get the driver name for this client (e.g., 'pg', 'mysql', 'sqlite3')
  String get driverName;

  /// Initialize the database driver
  void initializeDriver();

  /// Initialize the connection pool
  void initializePool([PoolConfig? poolConfig]);

  /// Create a new query builder
  QueryBuilder queryBuilder();

  /// Create a new query compiler
  QueryCompiler queryCompiler(QueryBuilder builder);

  /// Get a formatter for the given builder
  ///
  /// JS Reference: client.js - formatter(builder)
  ///
  /// The formatter handles identifier wrapping, column formatting,
  /// and SQL component generation.
  dynamic formatter(dynamic builder);

  /// Create a new schema builder
  SchemaBuilder schemaBuilder();

  /// Create a new schema compiler
  SchemaCompiler schemaCompiler(SchemaBuilder builder);

  /// Create a new raw query
  Raw raw(String sql, [dynamic bindings]) {
    final rawQuery = Raw(this);
    return rawQuery.set(sql, bindings);
  }

  /// Create a new column reference
  Ref ref(String columnRef) {
    return Ref(this, columnRef);
  }

  /// Start a new transaction
  Future<Transaction> transaction([TransactionConfig? config]);

  /// Execute a raw SQL query
  ///
  /// Returns the raw result from the database driver
  Future<dynamic> rawQuery(String sql, List<dynamic> bindings);

  /// Execute a query and return results
  Future<List<Map<String, dynamic>>> query(
    dynamic connection,
    String sql,
    List<dynamic> bindings,
  );

  /// Stream query results (for large result sets)
  Stream<Map<String, dynamic>> streamQuery(
    dynamic connection,
    String sql,
    List<dynamic> bindings,
  );

  /// Acquire a connection from the pool
  Future<dynamic> acquireConnection();

  /// Release a connection back to the pool
  Future<void> releaseConnection(dynamic connection);

  /// Destroy the connection pool and close all connections
  Future<void> destroy() async {
    await _queryController.close();
    await _queryErrorController.close();
    await _queryResponseController.close();

    if (_pool != null) {
      await _destroyPool();
      _pool = null;
    }
  }

  /// Dialect-specific pool destruction
  @protected
  Future<void> _destroyPool();

  /// Wrap an identifier (table/column name) with the dialect-specific wrapper
  ///
  /// Examples:
  /// - PostgreSQL/SQLite: "identifier"
  /// - MySQL: `identifier`
  /// - MSSQL: [identifier]
  String wrapIdentifier(String identifier) {
    if (identifier == '*') return '*';

    // Allow custom wrapper function from config
    if (config.wrapIdentifier != null) {
      return config.wrapIdentifier!(identifier);
    }

    return wrapIdentifierImpl(identifier);
  }

  /// Format value AS alias for SQL
  ///
  /// Example: alias('"column"', '"alias"') → '"column" AS "alias"'
  String alias(String value, String alias) {
    return '$value AS $alias';
  }

  /// Dialect-specific identifier wrapping implementation
  @protected
  String wrapIdentifierImpl(String identifier);

  /// Get parameter placeholder for given position (1-indexed)
  ///
  /// Subclasses should implement based on dialect:
  /// - PostgreSQL: $1, $2, $3, ...
  /// - MySQL/SQLite: ?, ?, ?, ...
  /// - Oracle: :1, :2, :3, ...
  String parameterPlaceholder(int index);

  /// Add a value to bindings and return the parameter placeholder
  ///
  /// JS Reference: client.js parameter() method
  ///
  /// This is used by the QueryCompiler to add bound parameters
  /// to queries while building the SQL string.
  ///
  /// Example:
  /// ```dart
  /// final bindings = [];
  /// final placeholder = client.parameter('active', bindings);
  /// // bindings = ['active']
  /// // placeholder = '$1' (for PostgreSQL)
  /// ```
  String parameter(dynamic value, List<dynamic> bindings) {
    bindings.add(value);
    return parameterPlaceholder(bindings.length);
  }

  /// Format a value for SQL (escaping as needed)
  String formatValue(dynamic value);

  /// Prepare bindings for the query (dialect-specific formatting)
  List<dynamic> prepareBindings(List<dynamic> bindings) {
    return bindings;
  }

  /// Position bindings in SQL (convert ? to dialect-specific placeholders)
  String positionBindings(String sql) {
    return sql;
  }

  /// Post-process query response (apply custom transformations)
  dynamic postProcessResponse(dynamic response, dynamic queryContext) {
    if (config.postProcessResponse != null) {
      return config.postProcessResponse!(response, queryContext);
    }
    return response;
  }

  /// Emit a query event
  @protected
  void emitQuery(
    String sql,
    List<dynamic> bindings,
    String uid, [
    String? txId,
  ]) {
    _queryController.add(
      QueryEvent(sql: sql, bindings: bindings, uid: uid, txId: txId),
    );

    if (config.debug) {
      logger.info('Query: $sql');
      logger.fine('Bindings: $bindings');
    }
  }

  /// Emit a query error event
  @protected
  void emitQueryError(
    Object error,
    StackTrace stackTrace,
    String sql,
    List<dynamic> bindings, [
    String? uid,
  ]) {
    final queryEvent = QueryEvent(
      sql: sql,
      bindings: bindings,
      uid: uid ?? 'unknown',
    );

    _queryErrorController.add(
      QueryErrorEvent(error: error, stackTrace: stackTrace, query: queryEvent),
    );

    logger.severe('Query error: $error\nSQL: $sql\nBindings: $bindings');
  }

  /// Emit a query response event
  @protected
  void emitQueryResponse(
    dynamic response,
    String sql,
    List<dynamic> bindings,
    String uid, [
    QueryBuilder? builder,
  ]) {
    final queryEvent = QueryEvent(sql: sql, bindings: bindings, uid: uid);

    _queryResponseController.add(
      QueryResponseEvent(
        response: response,
        query: queryEvent,
        builder: builder,
      ),
    );
  }
}

/// Event emitted when a query is executed
class QueryEvent {
  final String sql;
  final List<dynamic> bindings;
  final String uid;
  final String? txId;

  const QueryEvent({
    required this.sql,
    required this.bindings,
    required this.uid,
    this.txId,
  });
}

/// Event emitted when a query fails
class QueryErrorEvent {
  final Object error;
  final StackTrace stackTrace;
  final QueryEvent query;

  const QueryErrorEvent({
    required this.error,
    required this.stackTrace,
    required this.query,
  });
}

/// Event emitted when a query succeeds
class QueryResponseEvent {
  final dynamic response;
  final QueryEvent query;
  final QueryBuilder? builder;

  const QueryResponseEvent({
    required this.response,
    required this.query,
    this.builder,
  });
}
