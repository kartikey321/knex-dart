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

  /// SQL compilation event stream controllers.
  ///
  /// These streams are legacy/passive observation hooks on [Client]. Live
  /// driver wrappers route database execution through `QueryInterceptor`
  /// instead, so these events should not be used as execution signals.
  final _queryController = StreamController<QueryEvent>.broadcast();
  final _queryErrorController = StreamController<QueryErrorEvent>.broadcast();
  final _queryResponseController =
      StreamController<QueryResponseEvent>.broadcast();

  /// Stream of SQL compilation events.
  ///
  /// Live driver execution is intercepted through `QueryInterceptor`, not this
  /// stream.
  Stream<QueryEvent> get onQuery => _queryController.stream;

  /// Stream of SQL compilation error events.
  ///
  /// Live driver execution is intercepted through `QueryInterceptor`, not this
  /// stream.
  Stream<QueryErrorEvent> get onQueryError => _queryErrorController.stream;

  /// Stream of SQL compilation response events.
  ///
  /// Live driver execution is intercepted through `QueryInterceptor`, not this
  /// stream.
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

  /// Run [action] inside a database transaction on a single pinned connection.
  ///
  /// The default implementation issues raw `BEGIN` / `COMMIT` / `ROLLBACK` via
  /// [rawQuery]. This is correct for single-connection clients such as SQLite,
  /// but unreliable on connection-pooled drivers (Postgres, MySQL) where each
  /// [rawQuery] call may land on a **different** physical connection — making
  /// the transaction a silent no-op.
  ///
  /// Pooled drivers should override this method to acquire one connection,
  /// keep it pinned for the duration of [action], then release it:
  /// ```dart
  /// @override
  /// Future<T> runInTransaction<T>(Future<T> Function() action) =>
  ///     _pool.withConnection((conn) => conn.runTx((_) => action()));
  /// ```
  ///
  /// The [Migrator] calls this when `MigrationConfig.disableTransactions` is
  /// `false`. It defaults to `true` precisely because pooled drivers have not
  /// yet overridden this method.
  Future<T> runInTransaction<T>(Future<T> Function() action) async {
    await rawQuery('BEGIN', const []);
    try {
      final result = await action();
      await rawQuery('COMMIT', const []);
      return result;
    } catch (e) {
      try {
        await rawQuery('ROLLBACK', const []);
      } catch (_) {}
      rethrow;
    }
  }

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

  /// Offset any `$N`-style numbered placeholders in [sql] by [offset]
  /// positions.
  ///
  /// No-op for positional (`?`) dialects, where the pattern never matches.
  /// Used when inlining a compiled fragment (a [Raw] value, a subquery) into
  /// a query that already has [offset] prior bindings, so the fragment's
  /// placeholders continue the running `$N` sequence instead of restarting
  /// from `$1` and colliding with — or leaving gaps in — the placeholders
  /// already emitted for the surrounding query.
  ///
  /// Scans character-by-character rather than using a blind regex, because a
  /// `$N`-shaped substring can legitimately appear inside a single-quoted SQL
  /// string literal embedded in the fragment (e.g. a `Raw` value like
  /// `client.raw("note = '\$1 discount'")`) — that text must be left alone,
  /// not treated as a placeholder. `''` is tracked as the standard SQL
  /// escaped-quote sequence (stays inside the literal, not a close+reopen).
  ///
  /// Placeholder renumbering itself is done digit-by-digit in one pass
  /// (never via repeated `replaceAll('$1', …)`), which avoids a related bug:
  /// `$1` also matches inside `$10`/`$11`, including tokens a prior
  /// substitution just produced — e.g. with offset 9 a two-binding fragment
  /// would rewrite `$2`→`$11`, then `$1`→`$10` would also hit the `$1`
  /// inside that new `$11`, yielding `$101`.
  String offsetPlaceholders(String sql, int offset) {
    if (offset <= 0) return sql;
    final buffer = StringBuffer();
    var inString = false;
    var i = 0;
    while (i < sql.length) {
      final ch = sql[i];
      if (ch == "'") {
        inString = !inString;
        buffer.write(ch);
        i++;
        continue;
      }
      if (!inString && ch == r'$' && i + 1 < sql.length) {
        var j = i + 1;
        while (j < sql.length &&
            sql.codeUnitAt(j) >= 0x30 &&
            sql.codeUnitAt(j) <= 0x39) {
          j++;
        }
        if (j > i + 1) {
          final n = int.parse(sql.substring(i + 1, j));
          buffer.write('\$${n + offset}');
          i = j;
          continue;
        }
      }
      buffer.write(ch);
      i++;
    }
    return buffer.toString();
  }

  /// Add a value to bindings and return the parameter placeholder
  ///
  ///
  /// This is used by the QueryCompiler to add bound parameters
  /// to queries while building the SQL string.
  ///
  /// If [value] is a [Raw] instance, it is inlined as SQL text (its own
  /// bindings spliced into [bindings]) instead of being bound as an opaque
  /// parameter — mirroring knex.js's `Client.prototype.parameter`, which is
  /// the single place Raw values are unwrapped for every parameter position
  /// (insert/update/merge values, where clauses, limit/offset, etc).
  ///
  /// Example:
  /// ```dart
  /// final bindings = [];
  /// final placeholder = client.parameter('active', bindings);
  /// // bindings = ['active']
  /// // placeholder = '$1' (for PostgreSQL)
  /// ```
  String parameter(dynamic value, List<dynamic> bindings) {
    if (value is Raw) {
      final bindingOffset = bindings.length;
      final sql = value.toSQL();
      final offsetSql = offsetPlaceholders(sql.sql, bindingOffset);
      bindings.addAll(sql.bindings);
      return offsetSql;
    }
    if (value is Function) {
      // Callback subquery in a parameter position (e.g.
      // `.where('id', '=', (qb) => qb.select(...))`) — mirrors knex.js's
      // `Client.prototype.parameter`, which checks `typeof value ===
      // 'function'` before falling through to the Raw/QueryBuilder unwrap.
      final subBuilder = QueryBuilder(this);
      (value as dynamic)(subBuilder);
      return parameter(subBuilder, bindings);
    }
    if (value is QueryBuilder) {
      // Scalar subquery in a parameter position (e.g.
      // `.where('id', '=', otherBuilder)`) — mirrors knex.js's
      // `unwrapRaw`/`Client.prototype.parameter`, which compiles a
      // QueryBuilder value the same way it compiles a Raw one instead of
      // binding the builder object itself as an opaque parameter.
      final bindingOffset = bindings.length;
      final subCompiler = queryCompiler(value);
      final sql = subCompiler.toSQL();
      final offsetSql = offsetPlaceholders(sql.sql, bindingOffset);
      bindings.addAll(sql.bindings);
      final isSelectLike = subCompiler.method == 'select' ||
          subCompiler.method == 'first' ||
          subCompiler.method == 'pluck';
      return isSelectLike ? '($offsetSql)' : offsetSql;
    }
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

  QueryEvent({
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
