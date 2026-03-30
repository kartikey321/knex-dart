import 'sql_string.dart';
import 'join_clause.dart';
import '../client/client.dart';
import '../util/enums.dart';
import '../raw.dart';
import 'aggregate_options.dart';
import 'analytic.dart';
import 'on_conflict_builder.dart';
import 'window_spec.dart';
export 'analytic.dart';
export 'on_conflict_builder.dart';
export 'json_builder.dart';
export 'window_spec.dart';

// Sentinel for undefined arguments
const _undefined = Object();

/// Typed callback for subquery/grouped query builders.
typedef QueryBuilderCallback = void Function(QueryBuilder qb);

/// Typed callback for join ON clause builders.
typedef JoinClauseCallback = void Function(JoinClause join);

/// Query builder for constructing SQL queries
///
/// Provides a fluent API for building SELECT, INSERT, UPDATE, and DELETE queries.
///
/// Basic example:
/// ```dart
/// final qb = db.queryBuilder()
///   .table('users')
///   .where('active', true)
///   .orderBy('created_at', 'desc')
///   .limit(10);
///
/// final sql = qb.toSQL();
/// // sql.sql      -> select * from "users" where "active" = ? order by ...
/// // sql.bindings -> [true, 10]
/// ```
class QueryBuilder {
  final Client _client;
  final List<dynamic> _statements = [];
  final Map<String, dynamic> _single = {};
  QueryMethod _method = QueryMethod.select; // Using enum instead of String

  // Flags for WHERE clause modifiers
  bool _notFlag = false; // For NOT conditions
  String _boolFlag = 'and'; // For AND/OR (default: 'and')
  bool _asColumnFlag = false; // For column-to-column comparisons

  // Subquery alias (for use with .as() method)
  String? _alias;

  QueryBuilder(this._client);

  /// Get the client
  Client get client => _client;

  /// Get the query method
  QueryMethod get method => _method;

  /// Get single values (table, etc.) - used by QueryCompiler
  Map<String, dynamic> get single => _single;

  /// Get statements list - used by QueryCompiler
  List<dynamic> get statements => _statements;

  /// Get the alias (for subqueries) - used by QueryCompiler
  String? get alias => _alias;

  /// Convert to SQL
  SqlString toSQL() {
    final compiler = _client.queryCompiler(this);
    return compiler.toSQL();
  }

  @override
  String toString() => toSQL().toString();

  /// Set alias for this query (when used as a subquery)
  ///
  /// Example:
  /// ```dart
  /// knex.from(knex('orders').groupBy('user_id').as('grouped'))
  /// ```
  QueryBuilder as(String alias) {
    _alias = alias;
    return this;
  }

  /// Execute the query
  Future<List<Map<String, dynamic>>> execute() async {
    // Stub - will be implemented in Week 2
    throw UnimplementedError('QueryBuilder.execute() not yet implemented');
  }

  /// Alias for execute
  Future<List<Map<String, dynamic>>> get then => execute();

  bool _isSelectQuery() {
    return _method == QueryMethod.select ||
        _method == QueryMethod.first ||
        _method == QueryMethod.pluck;
  }

  bool _hasLockMode() => _single['lock'] != null;

  // Basic methods - stubs for now

  /// Set the table name
  ///
  /// Can accept either a String table name or a QueryBuilder for subqueries
  QueryBuilder table(dynamic tableName) {
    _single['table'] = tableName;
    return this;
  }

  /// Insert one or more rows
  ///
  ///
  /// Supports:
  /// - Single row: insert({'name': 'John', 'email': 'john@example.com'})
  /// - Multiple rows: insert([{...}, {...}])
  QueryBuilder insert(dynamic values, [List<String>? returning]) {
    _method = QueryMethod.insert;
    _single['insert'] = values;

    if (returning != null) {
      this.returning(returning);
    }

    return this;
  }

  /// Specify columns to return after INSERT/UPDATE/DELETE
  ///
  ///
  /// Example: insert({...}).returning(['id', 'name'])
  QueryBuilder returning(List<String> columns) {
    _single['returning'] = columns;
    return this;
  }

  /// Specify conflict target and action for INSERT ... ON CONFLICT.
  ///
  /// Mirrors the JavaScript query builder `onConflict()` shape:
  ///
  /// ```dart
  /// // UPSERT: update all columns on conflict
  /// qb.insert({'email': 'a@b.com', 'name': 'Alice'})
  ///   .onConflict('email')
  ///   .merge();
  ///
  /// // UPSERT: update only specific columns
  /// qb.insert({'email': 'a@b.com', 'name': 'Alice'})
  ///   .onConflict('email')
  ///   .merge({'name': 'Alice'});
  ///
  /// // Ignore on conflict (INSERT IGNORE / ON CONFLICT DO NOTHING)
  /// qb.insert({...}).onConflict('email').ignore();
  /// ```
  ///
  /// [column] can be a single column name, a List of column names, or null
  /// (lets the DB decide the conflict target via unique constraints).
  ///
  OnConflictBuilder onConflict([dynamic column]) {
    return OnConflictBuilder(this, column);
  }

  /// Update rows with given values
  ///
  ///
  /// Example: update({'name': 'John', 'email': 'john@example.com'})
  QueryBuilder update(Map<String, dynamic> values, [List<String>? returning]) {
    _method = QueryMethod.update;
    _single['update'] = values;

    if (returning != null) {
      this.returning(returning);
    }

    return this;
  }

  /// Increment a column value
  ///
  ///
  /// Example: increment('login_count', 1)
  QueryBuilder increment(String column, [num amount = 1]) {
    _method = QueryMethod.update;

    // Store counter info for compiler
    final counters = _single['counter'] as Map<String, dynamic>? ?? {};
    counters[column] = amount;
    _single['counter'] = counters;

    return this;
  }

  /// Decrement a column value
  ///
  ///
  /// Example: decrement('stock', 5)
  QueryBuilder decrement(String column, [num amount = 1]) {
    return increment(column, -amount);
  }

  /// Execute a delete query
  ///
  /// Returns the current instance for method chaining.
  /// Optionally specify columns to return with PostgreSQL's RETURNING clause.
  QueryBuilder delete([List<String>? returning]) {
    _method = QueryMethod.delete;

    if (returning != null) {
      this.returning(returning);
    }

    return this;
  }

  /// Retrieve the count of rows
  ///
  /// By default counts all rows (*). Optionally specify a column to count.
  /// Use [options] to configure distinct counting or result aliasing.
  QueryBuilder count([dynamic column = '*', AggregateOptions? options]) {
    return _aggregate('count', column ?? '*', options);
  }

  /// Retrieve the minimum value of a column
  ///
  /// Use [options] to configure distinct or result aliasing.
  QueryBuilder min(dynamic column, [AggregateOptions? options]) {
    return _aggregate('min', column, options);
  }

  /// Retrieve the maximum value of a column
  ///
  /// Use [options] to configure distinct or result aliasing.
  QueryBuilder max(dynamic column, [AggregateOptions? options]) {
    return _aggregate('max', column, options);
  }

  /// Retrieve the sum of values in a column
  ///
  /// Use [options] to configure distinct summation or result aliasing.
  QueryBuilder sum(dynamic column, [AggregateOptions? options]) {
    return _aggregate('sum', column, options);
  }

  /// Retrieve the average of values in a column
  ///
  /// Use [options] to configure distinct averaging or result aliasing.
  QueryBuilder avg(dynamic column, [AggregateOptions? options]) {
    return _aggregate('avg', column, options);
  }

  /// Retrieve the count of distinct values
  ///
  /// Can accept a single column, multiple columns as a List, or a Map for aliasing.
  /// Use [options] to configure result aliasing.
  QueryBuilder countDistinct(dynamic columns, [AggregateOptions? options]) {
    final opts = (options ?? AggregateOptions()).copyWith(distinct: true);
    return _aggregate('count', columns, opts);
  }

  /// Retrieve the sum of distinct values
  ///
  /// Use [options] to configure result aliasing.
  QueryBuilder sumDistinct(dynamic column, [AggregateOptions? options]) {
    final opts = (options ?? AggregateOptions()).copyWith(distinct: true);
    return _aggregate('sum', column, opts);
  }

  /// Retrieve the average of distinct values
  ///
  /// Use [options] to configure result aliasing.
  QueryBuilder avgDistinct(dynamic column, [AggregateOptions? options]) {
    final opts = (options ?? AggregateOptions()).copyWith(distinct: true);
    return _aggregate('avg', column, opts);
  }

  /// Helper for creating aggregate statements
  QueryBuilder _aggregate(
    String method,
    dynamic column,
    AggregateOptions? options,
  ) {
    final opts = options ?? AggregateOptions();
    final isRaw = column is Raw;

    _statements.add({
      'grouping': 'columns',
      'type': isRaw ? 'aggregateRaw' : 'aggregate',
      'method': method,
      'value': column,
      'aggregateDistinct': opts.distinct,
      'alias': opts.as,
    });

    return this;
  }

  /// Alias for table
  ///
  /// Can accept either a String table name or a QueryBuilder for subqueries
  QueryBuilder from(dynamic tableName) => table(tableName);

  /// Select columns
  ///
  /// Supports:
  /// - Simple list: ['id', 'name']
  /// - Object aliasing: [{ 'alias': 'column' }]
  /// - Mixed: ['id', { 'user_name': 'name' }]
  /// - Raw queries: select(client.raw('count(*) as total'))
  QueryBuilder select(dynamic columns) {
    _method = QueryMethod.select; // Using enum

    // Support Raw in select
    if (columns is Raw) {
      _statements.add({
        'type': 'select',
        'grouping': 'columns',
        'value': columns,
      });
      return this;
    }

    _statements.add({
      'type': 'select',
      'grouping': 'columns',
      'columns': columns,
    });
    return this;
  }

  /// Return only the first row (LIMIT 1)
  ///
  QueryBuilder first([dynamic columns]) {
    if (_method != QueryMethod.select) {
      throw StateError('Cannot chain .first() on "${_method.name}" query');
    }

    if (columns != null) {
      if (columns is List) {
        select(columns);
      } else {
        select([columns]);
      }
    }

    _method = QueryMethod.first;
    limit(1);
    return this;
  }

  /// Pluck a single column from a query
  ///
  QueryBuilder pluck(String column) {
    if (_method != QueryMethod.select) {
      throw StateError('Cannot chain .pluck() on "${_method.name}" query');
    }

    _method = QueryMethod.pluck;
    _single['pluck'] = column;
    _statements.add({'grouping': 'columns', 'type': 'pluck', 'value': column});
    return this;
  }

  /// Add a DISTINCT clause
  ///
  ///
  /// Makes the query return only unique/distinct rows
  QueryBuilder distinct([List<String>? columns]) {
    _statements.add({
      'grouping': 'columns',
      'value': columns ?? [],
      'distinct': true,
    });
    return this;
  }

  /// Add an INNER JOIN clause
  ///
  ///
  /// Supports:
  /// - Simple: join('orders', 'users.id', 'orders.user_id')
  /// - Callback: join('orders', (j) => j.on('users.id', 'orders.user_id'))
  QueryBuilder join(String table, [Object? first, String? second]) {
    return _performJoin('inner', table, first, second);
  }

  /// Add a LEFT JOIN clause
  ///
  ///
  /// Supports:
  /// - Simple: leftJoin('profiles', 'users.id', 'profiles.user_id')
  /// - Callback: leftJoin('profiles', (j) => j.on('users.id', 'profiles.user_id'))
  QueryBuilder leftJoin(String table, [Object? first, String? second]) {
    return _performJoin('left', table, first, second);
  }

  /// Add a RIGHT JOIN clause
  ///
  ///
  /// Supports:
  /// - Simple: rightJoin('reviews', 'products.id', 'reviews.product_id')
  /// - Callback: rightJoin('reviews', (j) => j.on('products.id', 'reviews.product_id'))
  QueryBuilder rightJoin(String table, [Object? first, String? second]) {
    return _performJoin('right', table, first, second);
  }

  /// Add a FULL OUTER JOIN clause
  ///
  QueryBuilder fullOuterJoin(String table, [Object? first, String? second]) {
    return _performJoin('full outer', table, first, second);
  }

  /// Add a CROSS JOIN clause
  ///
  ///
  /// CROSS JOIN has no ON condition
  QueryBuilder crossJoin(String table) {
    _statements.add({
      'grouping': 'join',
      'type': 'join',
      'join': 'cross',
      'table': table,
      // No ON clause for CROSS JOIN
    });
    return this;
  }

  // ─── Lateral joins ─────────────────────────────────────────────────────────

  /// Add a `JOIN LATERAL` clause (PostgreSQL / MySQL 8+).
  ///
  /// Emits: `join lateral (subquery) as "alias" on true`
  ///
  /// A lateral join allows the [subquery] to reference columns from tables
  /// appearing **earlier** in the FROM clause — like a correlated subquery
  /// but usable in the SELECT list and with proper row-set semantics.
  ///
  /// [subquery] can be:
  /// - A [QueryBuilder] — compiled inline with parameter renumbering.
  /// - A [Raw] — inserted as raw SQL inside parentheses.
  /// - A `void Function(QueryBuilder)` callback — a fresh [QueryBuilder]
  ///   is created and passed to the callback.
  ///
  /// **Not supported by SQLite.**
  ///
  /// Example:
  /// ```dart
  /// qb.table('users').joinLateral('latest_order', (sub) {
  ///   sub.table('orders')
  ///      .where('orders.user_id', knex.raw('"users"."id"'))
  ///      .orderBy('created_at', 'desc')
  ///      .limit(1);
  /// });
  /// // → join lateral (select * from "orders" where ...) as "latest_order" on true
  /// ```
  QueryBuilder joinLateral(String alias, Object subquery) =>
      _performLateralJoin('inner', alias, subquery);

  /// Add a `LEFT JOIN LATERAL` clause (PostgreSQL / MySQL 8+).
  ///
  /// Like [joinLateral] but rows from the left side that produce no matches
  /// in the lateral subquery are preserved (with NULL columns).
  ///
  /// Emits: `left join lateral (subquery) as "alias" on true`
  QueryBuilder leftJoinLateral(String alias, Object subquery) =>
      _performLateralJoin('left', alias, subquery);

  /// Add a `CROSS JOIN LATERAL` clause (PostgreSQL / MySQL 8+).
  ///
  /// Emits: `cross join lateral (subquery) as "alias"` (no ON clause).
  ///
  /// Equivalent to `JOIN LATERAL ... ON true` in PostgreSQL; rows that
  /// produce an empty lateral subquery are excluded.
  QueryBuilder crossJoinLateral(String alias, Object subquery) =>
      _performLateralJoin('cross', alias, subquery);

  QueryBuilder _performLateralJoin(
    String joinType,
    String alias,
    Object subquery,
  ) {
    final dynamic resolvedQuery;
    if (subquery is QueryBuilderCallback) {
      final qb = QueryBuilder(client);
      subquery(qb);
      resolvedQuery = qb;
    } else if (subquery is QueryBuilder || subquery is Raw) {
      resolvedQuery = subquery;
    } else {
      throw ArgumentError(
        'joinLateral subquery must be a QueryBuilder, Raw, or QueryBuilderCallback',
      );
    }
    _statements.add({
      'grouping': 'join',
      'type': 'joinLateral',
      'joinType': joinType,
      'alias': alias,
      'query': resolvedQuery,
    });
    return this;
  }

  /// Internal helper for performing joins
  ///
  /// Handles both simple and callback-based joins
  QueryBuilder _performJoin(
    String joinType,
    String table, [
    Object? first,
    String? second,
  ]) {
    if (first is JoinClauseCallback) {
      // Callback-based join with complex ON conditions
      final joinClause = JoinClause(table, joinType);
      first(joinClause); // User builds ON conditions

      _statements.add({
        'grouping': 'join',
        'type': 'join',
        'join': joinType,
        'table': table,
        'joinClause': joinClause, // Store full clause object
      });
    } else if (first != null && second != null) {
      // Simple join with two columns
      _statements.add({
        'grouping': 'join',
        'type': 'join',
        'join': joinType,
        'table': table,
        'column1': first,
        'column2': second,
      });
    } else {
      throw ArgumentError(
        'join() requires either (column1, column2) or a callback function',
      );
    }

    return this;
  }

  /// Add a where clause
  ///
  ///
  /// Supports:
  /// - where(column, value) - assumes '=' operator
  /// - where(column, operator, value) - explicit operator
  /// - where(Raw) - raw SQL condition
  QueryBuilder where(
    dynamic column, [
    dynamic operatorOrValue = _undefined,
    dynamic value = _undefined,
  ]) {
    // Support Raw queries
    if (column is Raw) {
      _statements.add({
        'type': 'whereRaw',
        'grouping': 'where',
        'value': column,
        'bool': 'and',
      });
      return this;
    }

    // Support grouped WHERE closures: where((builder) => ...)
    if (column is QueryBuilderCallback) {
      return whereWrapped(column);
    }

    // Determine operator and value based on arguments
    final dynamic operator;
    final dynamic val;

    if (value == _undefined) {
      // 2 arguments: column, value (operator is '=')
      operator = '=';
      val = operatorOrValue;
    } else {
      // 3 arguments: column, operator, value
      operator = operatorOrValue;
      val = value;
    }

    _statements.add({
      'type': 'whereBasic',
      'grouping': 'where',
      'column': column,
      'operator': operator,
      'value': val,
      'bool': _bool(), // Read and reset bool flag
      'not': _not(), // Read and reset not flag
      'asColumn': _asColumnFlag, // Use flag for whereColumn support
    });
    return this;
  }

  /// Add an order by clause
  ///
  ///
  /// Supports orderBy(column, [direction])
  /// - direction defaults to 'asc'
  /// - direction can be 'asc' or 'desc'
  QueryBuilder orderBy(String column, [String direction = 'asc']) {
    _statements.add({
      'grouping': 'order',
      'type': 'orderByBasic',
      'value': column,
      'direction': direction,
    });
    return this;
  }

  /// Set the LIMIT for the query
  ///
  ///
  /// Limits the number of rows returned
  QueryBuilder limit(int value) {
    _single['limit'] = value;
    return this;
  }

  /// Set the OFFSET for the query
  ///
  ///
  /// Skips the specified number of rows
  QueryBuilder offset(int value) {
    _single['offset'] = value;
    return this;
  }

  // ============================================================================
  // FLAG HELPER METHODS
  // ============================================================================

  /// Get or set the "notFlag" value
  ///
  /// When called with a value, sets the flag and returns `this` for chaining.
  /// When called without arguments, returns current value and resets to `false`.
  ///
  dynamic _not([bool? val]) {
    if (val != null) {
      _notFlag = val;
      return this;
    }
    final ret = _notFlag;
    _notFlag = false;
    return ret;
  }

  /// Get or set the "boolFlag" value
  ///
  /// When called with a value, sets the flag and returns `this` for chaining.
  /// When called without arguments, returns current value and resets to `'and'`.
  ///
  dynamic _bool([String? val]) {
    if (val != null) {
      _boolFlag = val;
      return this;
    }
    final ret = _boolFlag;
    _boolFlag = 'and';
    return ret;
  }


  /// Add an OR WHERE clause
  ///
  ///
  /// Sets bool='or' then calls where()
  QueryBuilder orWhere(
    dynamic column, [
    dynamic operatorOrValue = _undefined,
    dynamic value = _undefined,
  ]) {
    // Set bool to 'or' for next where clause
    _boolFlag = 'or';
    return where(column, operatorOrValue, value);
  }

  /// Add a WHERE NULL clause
  ///
  QueryBuilder whereNull(String column) {
    _statements.add({
      'grouping': 'where',
      'type': 'whereNull',
      'column': column,
      'not': false,
      'bool': 'and',
    });
    return this;
  }

  /// Add a WHERE NOT NULL clause
  ///
  QueryBuilder whereNotNull(String column) {
    _statements.add({
      'grouping': 'where',
      'type': 'whereNull',
      'column': column,
      'not': true, // Uses NOT flag
      'bool': 'and',
    });
    return this;
  }

  /// Add an OR WHERE NULL clause
  QueryBuilder orWhereNull(String column) {
    _statements.add({
      'grouping': 'where',
      'type': 'whereNull',
      'column': column,
      'not': false,
      'bool': 'or',
    });
    return this;
  }

  /// Add a WHERE IN clause
  ///
  /// Accepts either a List of values or a QueryBuilder for subqueries
  ///
  QueryBuilder whereIn(String column, dynamic values) {
    _statements.add({
      'grouping': 'where',
      'type': 'whereIn',
      'column': column,
      'value': values,
      'not': false,
      'bool': 'and',
    });
    return this;
  }

  /// Add a WHERE NOT IN clause
  ///
  QueryBuilder whereNotIn(String column, dynamic values) {
    _statements.add({
      'grouping': 'where',
      'type': 'whereIn',
      'column': column,
      'value': values,
      'not': true, // Uses NOT flag
      'bool': _bool(), // Read and reset bool flag
    });
    return this;
  }

  // ============================================================================
  // EXTENDED WHERE CLAUSE METHODS
  // ============================================================================

  /// Compare two columns with a WHERE clause
  ///
  ///
  /// Example: whereColumn('updated_at', '>', 'created_at')
  QueryBuilder whereColumn(String column1, String operator, String column2) {
    _asColumnFlag = true;
    where(column1, operator, column2);
    _asColumnFlag = false;
    return this;
  }

  /// OR version of whereColumn
  QueryBuilder orWhereColumn(String column1, String operator, String column2) {
    _asColumnFlag = true;
    orWhere(column1, operator, column2);
    _asColumnFlag = false;
    return this;
  }

  /// Add a WHERE BETWEEN clause
  ///
  ///
  /// Example: whereBetween('age', [18, 65])
  QueryBuilder whereBetween(String column, List values) {
    assert(
      values.length == 2,
      'You must specify 2 values for the whereBetween clause',
    );

    _statements.add({
      'grouping': 'where',
      'type': 'whereBetween',
      'column': column,
      'value': values,
      'not': _not(),
      'bool': _bool(),
    });
    return this;
  }

  /// Add a WHERE NOT BETWEEN clause
  ///
  QueryBuilder whereNotBetween(String column, List values) {
    return _not(true).whereBetween(column, values) as QueryBuilder;
  }

  /// OR version of WHERE BETWEEN
  QueryBuilder orWhereBetween(String column, List values) {
    return _bool('or').whereBetween(column, values) as QueryBuilder;
  }

  /// OR version of WHERE NOT BETWEEN
  QueryBuilder orWhereNotBetween(String column, List values) {
    return _bool('or')._not(true).whereBetween(column, values) as QueryBuilder;
  }

  /// Add a WHERE NOT clause
  ///
  ///
  /// Example: whereNot('status', 'deleted')
  QueryBuilder whereNot(
    dynamic column, [
    dynamic operator = _undefined,
    dynamic value = _undefined,
  ]) {
    // Warning: whereNot is not suitable for "in" and "between"
    // (should use whereNotIn and whereNotBetween instead)
    return _not(true).where(column, operator, value) as QueryBuilder;
  }

  /// OR version of WHERE NOT
  QueryBuilder orWhereNot(
    dynamic column, [
    dynamic operator = _undefined,
    dynamic value = _undefined,
  ]) {
    return _bool('or')._not(true).where(column, operator, value)
        as QueryBuilder;
  }

  /// OR version of WHERE NOT IN
  QueryBuilder orWhereNotIn(String column, List<dynamic> values) {
    return _bool('or').whereNotIn(column, values);
  }

  /// OR version of WHERE NOT NULL
  QueryBuilder orWhereNotNull(String column) {
    _statements.add({
      'grouping': 'where',
      'type': 'whereNull',
      'column': column,
      'not': true,
      'bool': 'or',
    });
    return this;
  }

  /// Add a WHERE EXISTS clause with a subquery
  ///
  ///
  /// Example:
  /// ```dart
  /// whereExists((qb) {
  ///   qb.select('*').from('orders').whereRaw('orders.user_id = users.id');
  /// })
  /// ```
  QueryBuilder whereExists(QueryBuilderCallback callback) {
    _statements.add({
      'grouping': 'where',
      'type': 'whereExists',
      'value': callback,
      'not': _not(),
      'bool': _bool(),
    });
    return this;
  }

  /// Add a WHERE NOT EXISTS clause
  ///
  QueryBuilder whereNotExists(QueryBuilderCallback callback) {
    return _not(true).whereExists(callback) as QueryBuilder;
  }

  /// OR version of WHERE EXISTS
  QueryBuilder orWhereExists(QueryBuilderCallback callback) {
    return _bool('or').whereExists(callback) as QueryBuilder;
  }

  /// OR version of WHERE NOT EXISTS
  QueryBuilder orWhereNotExists(QueryBuilderCallback callback) {
    return _bool('or')._not(true).whereExists(callback) as QueryBuilder;
  }

  /// Add grouped WHERE conditions in parentheses
  ///
  ///
  /// Example:
  /// ```dart
  /// whereWrapped((qb) {
  ///   qb.where('age', '>', 18).orWhere('verified', true);
  /// })
  /// // Generates: WHERE (age > 18 OR verified = true)
  /// ```
  QueryBuilder whereWrapped(QueryBuilderCallback callback) {
    _statements.add({
      'grouping': 'where',
      'type': 'whereWrapped',
      'value': callback,
      'not': _not(),
      'bool': _bool(),
    });
    return this;
  }

  /// Add a GROUP BY clause
  ///
  ///
  /// Groups rows by one or more columns
  QueryBuilder groupBy(String column) {
    _statements.add({
      'grouping': 'group',
      'type': 'groupByBasic',
      'value': column,
    });
    return this;
  }

  /// Add UNION clause - combines results from multiple queries
  QueryBuilder union(List<dynamic> queries, {bool wrap = false}) {
    for (final query in queries) {
      _statements.add({
        'grouping': 'union',
        'type': 'union',
        'value': query,
        'wrap': wrap,
      });
    }
    return this;
  }

  /// Add UNION ALL clause - combines results keeping duplicates
  QueryBuilder unionAll(List<dynamic> queries, {bool wrap = false}) {
    for (final query in queries) {
      _statements.add({
        'grouping': 'union',
        'type': 'union all',
        'value': query,
        'wrap': wrap,
      });
    }
    return this;
  }

  /// Add INTERSECT clause — returns rows that appear in ALL queries.
  ///
  /// Equivalent to SQL `INTERSECT` between the current query and [queries].
  ///
  /// Not supported natively by MySQL (use a workaround with JOIN/WHERE EXISTS).
  QueryBuilder intersect(List<dynamic> queries, {bool wrap = false}) {
    for (final query in queries) {
      _statements.add({
        'grouping': 'union',
        'type': 'intersect',
        'value': query,
        'wrap': wrap,
      });
    }
    return this;
  }

  /// Add INTERSECT ALL clause — returns rows in ALL queries, preserving duplicates.
  QueryBuilder intersectAll(List<dynamic> queries, {bool wrap = false}) {
    for (final query in queries) {
      _statements.add({
        'grouping': 'union',
        'type': 'intersect all',
        'value': query,
        'wrap': wrap,
      });
    }
    return this;
  }

  /// Add EXCEPT clause — returns rows in the first query but NOT in subsequent queries.
  ///
  /// Equivalent to SQL `EXCEPT` between the current query and [queries].
  ///
  /// MySQL calls this `EXCEPT` (8.0+) or can be approximated with `LEFT JOIN WHERE NULL`.
  QueryBuilder except(List<dynamic> queries, {bool wrap = false}) {
    for (final query in queries) {
      _statements.add({
        'grouping': 'union',
        'type': 'except',
        'value': query,
        'wrap': wrap,
      });
    }
    return this;
  }

  /// Add EXCEPT ALL clause — returns rows in the first query but NOT in subsequent queries,
  /// preserving duplicates.
  QueryBuilder exceptAll(List<dynamic> queries, {bool wrap = false}) {
    for (final query in queries) {
      _statements.add({
        'grouping': 'union',
        'type': 'except all',
        'value': query,
        'wrap': wrap,
      });
    }
    return this;
  }

  /// Add a Common Table Expression (CTE)
  ///
  /// CTEs allow complex queries to be broken down into named subqueries
  ///
  /// Note: Named withQuery in Dart since with is a reserved keyword
  QueryBuilder withQuery(String alias, dynamic query) {
    _statements.add({
      'grouping': 'with',
      'type': 'with',
      'alias': alias,
      'value': query,
    });
    return this;
  }

  /// Add a recursive CTE
  ///
  /// Used for hierarchical/recursive data (trees, graphs, etc.)
  ///
  QueryBuilder withRecursive(String alias, dynamic query) {
    _statements.add({
      'grouping': 'with',
      'type': 'withRecursive',
      'alias': alias,
      'value': query,
    });
    return this;
  }

  /// Add a HAVING clause
  ///
  ///
  /// Filters grouped results (like WHERE for aggregates)
  /// Supports two forms:
  /// - having(column, value) - assumes '=' operator
  /// - having(column, operator, value) - explicit operator
  QueryBuilder having(String column, dynamic operatorOrValue, [dynamic value]) {
    _statements.add({
      'grouping': 'having',
      'type': 'havingBasic',
      'column': column,
      'operator': value == null ? '=' : operatorOrValue,
      'value': value ?? operatorOrValue,
      'bool': 'and',
      'not': false,
    });
    return this;
  }

  /// Add a raw HAVING clause to a query
  ///
  ///
  /// Use for complex expressions that shouldn't be wrapped in quotes,
  /// such as aggregate functions: count(*), sum(amount), etc.
  ///
  /// Examples:
  /// ```dart
  /// // Having with aggregate function
  /// query.havingRaw('count(*) > ?', [10]);
  ///
  /// // Multiple conditions
  /// query.havingRaw('sum(amount) > ? AND count(*) > ?', [1000, 5]);
  /// ```
  QueryBuilder havingRaw(String sql, [List<dynamic> bindings = const []]) {
    _statements.add({
      'grouping': 'having',
      'type': 'havingRaw',
      'value': sql,
      'bindings': bindings,
      'bool': 'and',
    });
    return this;
  }

  /// Add an OR raw HAVING clause
  QueryBuilder orHavingRaw(String sql, [List<dynamic> bindings = const []]) {
    _statements.add({
      'grouping': 'having',
      'type': 'havingRaw',
      'value': sql,
      'bindings': bindings,
      'bool': 'or',
    });
    return this;
  }

  /// Add an OR HAVING clause
  ///
  /// Example: .having('total', '>', 100).orHaving('count', '<', 5)
  QueryBuilder orHaving(
    String column,
    dynamic operatorOrValue, [
    dynamic value,
  ]) {
    _statements.add({
      'grouping': 'having',
      'type': 'havingBasic',
      'column': column,
      'operator': value == null ? '=' : operatorOrValue,
      'value': value ?? operatorOrValue,
      'bool': 'or',
      'not': false,
    });
    return this;
  }

  /// Add a HAVING IN clause
  ///
  QueryBuilder havingIn(String column, List<dynamic> values) {
    _statements.add({
      'grouping': 'having',
      'type': 'havingIn',
      'column': column,
      'value': values,
      'bool': 'and',
      'not': false,
    });
    return this;
  }

  /// Add a HAVING NOT IN clause
  QueryBuilder havingNotIn(String column, List<dynamic> values) {
    _statements.add({
      'grouping': 'having',
      'type': 'havingIn',
      'column': column,
      'value': values,
      'bool': 'and',
      'not': true,
    });
    return this;
  }

  /// Add an OR HAVING IN clause
  QueryBuilder orHavingIn(String column, List<dynamic> values) {
    _statements.add({
      'grouping': 'having',
      'type': 'havingIn',
      'column': column,
      'value': values,
      'bool': 'or',
      'not': false,
    });
    return this;
  }

  /// Add an OR HAVING NOT IN clause
  QueryBuilder orHavingNotIn(String column, List<dynamic> values) {
    _statements.add({
      'grouping': 'having',
      'type': 'havingIn',
      'column': column,
      'value': values,
      'bool': 'or',
      'not': true,
    });
    return this;
  }

  /// Add a HAVING BETWEEN clause
  ///
  QueryBuilder havingBetween(String column, List<dynamic> values) {
    assert(
      values.length == 2,
      'havingBetween requires a list of exactly 2 values',
    );
    _statements.add({
      'grouping': 'having',
      'type': 'havingBetween',
      'column': column,
      'value': values,
      'bool': 'and',
      'not': false,
    });
    return this;
  }

  /// Add a HAVING NOT BETWEEN clause
  QueryBuilder havingNotBetween(String column, List<dynamic> values) {
    assert(
      values.length == 2,
      'havingNotBetween requires a list of exactly 2 values',
    );
    _statements.add({
      'grouping': 'having',
      'type': 'havingBetween',
      'column': column,
      'value': values,
      'bool': 'and',
      'not': true,
    });
    return this;
  }

  /// Add an OR HAVING BETWEEN clause
  QueryBuilder orHavingBetween(String column, List<dynamic> values) {
    assert(
      values.length == 2,
      'orHavingBetween requires a list of exactly 2 values',
    );
    _statements.add({
      'grouping': 'having',
      'type': 'havingBetween',
      'column': column,
      'value': values,
      'bool': 'or',
      'not': false,
    });
    return this;
  }

  /// Add a HAVING NULL clause
  ///
  QueryBuilder havingNull(String column) {
    _statements.add({
      'grouping': 'having',
      'type': 'havingNull',
      'column': column,
      'bool': 'and',
      'not': false,
    });
    return this;
  }

  /// Add a HAVING NOT NULL clause
  QueryBuilder havingNotNull(String column) {
    _statements.add({
      'grouping': 'having',
      'type': 'havingNull',
      'column': column,
      'bool': 'and',
      'not': true,
    });
    return this;
  }

  /// Add an OR HAVING NULL clause
  QueryBuilder orHavingNull(String column) {
    _statements.add({
      'grouping': 'having',
      'type': 'havingNull',
      'column': column,
      'bool': 'or',
      'not': false,
    });
    return this;
  }

  /// Add an OR HAVING NOT NULL clause
  QueryBuilder orHavingNotNull(String column) {
    _statements.add({
      'grouping': 'having',
      'type': 'havingNull',
      'column': column,
      'bool': 'or',
      'not': true,
    });
    return this;
  }

  /// Set a row-level lock FOR UPDATE
  QueryBuilder forUpdate([List<String>? tables]) {
    _single['lock'] = 'forUpdate';
    _single['lockTables'] = tables ?? <String>[];
    return this;
  }

  /// Set a row-level lock FOR SHARE
  QueryBuilder forShare([List<String>? tables]) {
    _single['lock'] = 'forShare';
    _single['lockTables'] = tables ?? <String>[];
    return this;
  }

  /// PostgreSQL-specific lock mode FOR NO KEY UPDATE
  QueryBuilder forNoKeyUpdate([List<String>? tables]) {
    _single['lock'] = 'forNoKeyUpdate';
    _single['lockTables'] = tables ?? <String>[];
    return this;
  }

  /// PostgreSQL-specific lock mode FOR KEY SHARE
  QueryBuilder forKeyShare([List<String>? tables]) {
    _single['lock'] = 'forKeyShare';
    _single['lockTables'] = tables ?? <String>[];
    return this;
  }

  /// Skip locked rows while waiting on a lock
  QueryBuilder skipLocked() {
    if (!_isSelectQuery()) {
      throw StateError('Cannot chain .skipLocked() on "${_method.name}" query');
    }
    if (!_hasLockMode()) {
      throw StateError(
        '.skipLocked() can only be used after .forShare() or .forUpdate()',
      );
    }
    if (_single['waitMode'] == 'noWait') {
      throw StateError('.skipLocked() cannot be used together with .noWait()');
    }
    _single['waitMode'] = 'skipLocked';
    return this;
  }

  /// Fail immediately when lock cannot be acquired
  QueryBuilder noWait() {
    if (!_isSelectQuery()) {
      throw StateError('Cannot chain .noWait() on "${_method.name}" query');
    }
    if (!_hasLockMode()) {
      throw StateError(
        '.noWait() can only be used after .forShare() or .forUpdate()',
      );
    }
    if (_single['waitMode'] == 'skipLocked') {
      throw StateError('.noWait() cannot be used together with .skipLocked()');
    }
    _single['waitMode'] = 'noWait';
    return this;
  }

  // ============================================================================
  // ANALYTIC / WINDOW FUNCTIONS
  //
  //
  // Supported overloads (matching JS _analytic(alias, second, third)):
  //   1. String/Array: rank(alias, orderBy, [partitionBy])
  //      where orderBy / partitionBy are String or List<String>
  //   2. Raw: rank(alias, raw) — raw OVER clause
  //   3. AnalyticClause callback builder:
  //      rank(alias, (a) => a.orderBy('col').partitionBy('col'))
  // ============================================================================

  /// Internal dispatcher — mirrors JS `_analytic(alias, second, third)`
  QueryBuilder _analytic(
    String method,
    dynamic alias, [
    dynamic second, // String | List | Raw | Function(AnalyticClause)
    dynamic
    third, // String | List (partitionBy) — only for string/array overload
  ]) {
    final aliasStr = alias is String ? alias : null;

    if (second is Function) {
      // Callback overload: build an AnalyticClause and pass it to the fn
      final clause = AnalyticClause(method: method, alias: aliasStr);
      second(clause);
      _statements.add({
        'grouping': 'columns',
        'type': 'analytic',
        'method': method,
        'alias': aliasStr,
        'order': clause.order,
        'partitions': clause.partitions,
      });
    } else if (second is Raw) {
      // Raw overload: bare raw SQL in OVER (...)
      _statements.add({
        'grouping': 'columns',
        'type': 'analytic',
        'method': method,
        'alias': aliasStr,
        'raw': second,
      });
    } else {
      // String/array overload: (alias, orderBy, [partitionBy])
      final order = second == null
          ? []
          : (second is! List ? [second] : second);
      final List partitions;
      if (third == null) {
        partitions = [];
      } else if (third is List) {
        partitions = third;
      } else {
        partitions = [third];
      }
      _statements.add({
        'grouping': 'columns',
        'type': 'analytic',
        'method': method,
        'alias': aliasStr,
        'order': order,
        'partitions': partitions,
      });
    }
    return this;
  }

  /// Add `rank() OVER (...) AS alias` to the SELECT list.
  ///
  /// Same call shape as common JS query builders: `rank(alias, orderBy, [partitionBy])`.
  ///
  /// String syntax: `rank('alias', 'email', 'firstName')`
  /// Array syntax:  `rank('alias', ['email', 'addr'], ['firstName', 'lastName'])`
  /// Raw syntax:    `rank('alias', client.raw('order by ?? desc', ['salary']))`
  /// Callback:      `rank('alias', (a) => a.orderBy('email').partitionBy('dept'))`
  QueryBuilder rank(dynamic alias, [dynamic orderBy, dynamic partitionBy]) {
    return _analytic('rank', alias, orderBy, partitionBy);
  }

  /// Add `dense_rank() OVER (...) AS alias` to the SELECT list.
  ///
  /// Same overloads as [rank].
  QueryBuilder denseRank(
    dynamic alias, [
    dynamic orderBy,
    dynamic partitionBy,
  ]) {
    return _analytic('dense_rank', alias, orderBy, partitionBy);
  }

  /// Add `row_number() OVER (...) AS alias` to the SELECT list.
  ///
  /// Same overloads as [rank].
  QueryBuilder rowNumber(
    dynamic alias, [
    dynamic orderBy,
    dynamic partitionBy,
  ]) {
    return _analytic('row_number', alias, orderBy, partitionBy);
  }

  // ============================================================================
  // VALUE WINDOW FUNCTIONS (lead, lag, first_value, last_value, nth_value)
  // ============================================================================

  /// Internal dispatcher for value window functions (those that take a source
  /// column as their first argument inside the SQL function call).
  ///
  /// [method] — SQL function name (e.g. 'lead', 'lag', 'first_value', …)
  /// [alias]  — output alias
  /// [column] — source column passed inside the function call
  /// [offset] — optional offset for lead/lag
  /// [defaultVal] — optional default value for lead/lag
  /// [nthN]   — required integer for nth_value
  /// [second] — OVER clause config: same overloads as [_analytic] (String |
  ///            List | Raw | Function(AnalyticClause) | [WindowSpec])
  /// [third]  — partitionBy when [second] is a String/List
  QueryBuilder _analyticValue(
    String method,
    String alias,
    String column, {
    int? offset,
    dynamic defaultVal,
    int? nthN,
    dynamic second,
    dynamic third,
  }) {
    final stmt = <String, dynamic>{
      'grouping': 'columns',
      'type': 'analytic',
      'method': method,
      'sourceColumn': column,
      'alias': alias,
    };

    if (offset != null) stmt['offset'] = offset;
    if (defaultVal != null) stmt['defaultVal'] = defaultVal;
    if (nthN != null) stmt['nthN'] = nthN;

    if (second is WindowSpec) {
      stmt['partitions'] = second.partitions
          .map((p) => <String, String>{'column': p})
          .toList();
      stmt['order'] = second.orders
          .map(
            (o) => <String, String?>{
              'column': o['column']!,
              'order': o['direction'],
            },
          )
          .toList();
      final fc = second.frameClause;
      if (fc != null) stmt['frameClause'] = fc;
    } else if (second is Function) {
      final clause = AnalyticClause(method: method, alias: alias);
      second(clause);
      stmt['order'] = clause.order;
      stmt['partitions'] = clause.partitions;
    } else if (second is Raw) {
      stmt['raw'] = second;
    } else {
      final order = second == null ? [] : (second is! List ? [second] : second);
      final List partitions;
      if (third == null) {
        partitions = [];
      } else if (third is List) {
        partitions = third;
      } else {
        partitions = [third];
      }
      stmt['order'] = order;
      stmt['partitions'] = partitions;
    }

    _statements.add(stmt);
    return this;
  }

  /// Add `lead(column[, offset[, default]]) OVER (...) AS alias` to the SELECT list.
  ///
  /// [column] is the source column. [second]/[third] configure the OVER clause
  /// the same way as [rank] (orderBy / partitionBy, Raw, callback, or [WindowSpec]).
  /// [offset] defaults to 1 (the SQL default); omit to emit `lead("col")`.
  /// [defaultVal] is the fallback value when there is no lead row.
  ///
  /// Example:
  /// ```dart
  /// qb.lead('next_sal', 'salary', 'salary', 'dept', offset: 1, defaultVal: 0)
  /// // → lead("salary", 1, 0) over (partition by "dept" order by "salary") as next_sal
  /// ```
  QueryBuilder lead(
    String alias,
    String column, [
    dynamic second,
    dynamic third,
    int? offset,
    dynamic defaultVal,
  ]) {
    return _analyticValue(
      'lead',
      alias,
      column,
      offset: offset,
      defaultVal: defaultVal,
      second: second,
      third: third,
    );
  }

  /// Add `lag(column[, offset]) OVER (...) AS alias` to the SELECT list.
  ///
  /// [column] is the source column. [second]/[third] configure the OVER clause.
  /// [offset] is optional; omit to emit `lag("col")`.
  ///
  /// Example:
  /// ```dart
  /// qb.lag('prev_sal', 'salary', 'created_at')
  /// // → lag("salary") over (order by "created_at") as prev_sal
  /// ```
  QueryBuilder lag(
    String alias,
    String column, [
    dynamic second,
    dynamic third,
    int? offset,
  ]) {
    return _analyticValue(
      'lag',
      alias,
      column,
      offset: offset,
      second: second,
      third: third,
    );
  }

  /// Add `first_value(column) OVER (...) AS alias` to the SELECT list.
  ///
  /// [column] is the source column. [second]/[third] configure the OVER clause
  /// the same way as [rank].
  QueryBuilder firstValue(
    String alias,
    String column, [
    dynamic second,
    dynamic third,
  ]) {
    return _analyticValue(
      'first_value',
      alias,
      column,
      second: second,
      third: third,
    );
  }

  /// Add `last_value(column) OVER (...) AS alias` to the SELECT list.
  ///
  /// Cross-dialect note: without an explicit frame clause, most databases use
  /// `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`, which yields
  /// unexpected results. Pass a [WindowSpec] with
  /// `rowsBetween(WindowSpec.unboundedPreceding, WindowSpec.unboundedFollowing)`
  /// for the typical "true last value" behaviour.
  QueryBuilder lastValue(
    String alias,
    String column, [
    dynamic second,
    dynamic third,
  ]) {
    return _analyticValue(
      'last_value',
      alias,
      column,
      second: second,
      third: third,
    );
  }

  /// Add `nth_value(column, n) OVER (...) AS alias` to the SELECT list.
  ///
  /// [n] is 1-based (the 1st, 2nd, … row in the window).
  ///
  /// Note: not supported in MySQL 5.x; requires MySQL 8+ or PostgreSQL.
  QueryBuilder nthValue(
    String alias,
    String column,
    int n, [
    dynamic second,
    dynamic third,
  ]) {
    return _analyticValue(
      'nth_value',
      alias,
      column,
      nthN: n,
      second: second,
      third: third,
    );
  }

  // ============================================================================
  // BUILDER UTILITIES & LOCKS
  // ============================================================================

  /// Creates a deep clone of this query builder.
  ///
  /// Useful when branching query variants from a common base.
  QueryBuilder clone() {
    final cloned = QueryBuilder(_client);
    cloned._statements.addAll(_statements);
    cloned._single.addAll(
      _single.map((key, value) {
        if (value is List) return MapEntry(key, List.from(value));
        if (value is Map) return MapEntry(key, Map.from(value));
        return MapEntry(key, value);
      }),
    );
    cloned._method = _method;
    cloned._notFlag = _notFlag;
    cloned._boolFlag = _boolFlag;
    cloned._asColumnFlag = _asColumnFlag;
    cloned._alias = _alias;
    if (_timeout != null) cloned._timeout = _timeout;
    if (_cancelOnTimeout != null) cloned._cancelOnTimeout = _cancelOnTimeout;
    return cloned;
  }

  /// Clears query state.
  ///
  /// If [target] is provided, only that statement grouping is removed
  /// (for example: `'where'` or `'order'`). Otherwise all statements and
  /// single-value options are reset.
  QueryBuilder clear([String? target]) {
    if (target != null) {
      _statements.removeWhere((stmt) => stmt['grouping'] == target);
    } else {
      _statements.clear();
      _single.clear();
      _method = QueryMethod.select;
    }
    return this;
  }

  /// Marks this query as `TRUNCATE`.
  QueryBuilder truncate() {
    _method = QueryMethod.truncate;
    return this;
  }

  /// Removes selected columns from this query.
  QueryBuilder clearSelect() {
    _statements.removeWhere((stmt) => stmt['grouping'] == 'columns');
    return this;
  }

  /// Removes WHERE clauses from this query.
  QueryBuilder clearWhere() {
    _statements.removeWhere((stmt) => stmt['grouping'] == 'where');
    return this;
  }

  /// Removes GROUP BY clauses from this query.
  QueryBuilder clearGroup() {
    _statements.removeWhere((stmt) => stmt['grouping'] == 'group');
    return this;
  }

  /// Removes ORDER BY clauses from this query.
  QueryBuilder clearOrder() {
    _statements.removeWhere((stmt) => stmt['grouping'] == 'order');
    return this;
  }

  /// Removes HAVING clauses from this query.
  QueryBuilder clearHaving() {
    _statements.removeWhere((stmt) => stmt['grouping'] == 'having');
    return this;
  }

  /// Removes increment/decrement counter mutations from this query.
  QueryBuilder clearCounters() {
    _single.remove('counter');
    return this;
  }

  /// Adds a raw JOIN fragment.
  QueryBuilder joinRaw(dynamic sql, [dynamic bindings]) {
    _statements.add({
      'grouping': 'join',
      'type': 'joinRaw',
      'value': sql is Raw ? sql : client.raw(sql.toString(), bindings),
    });
    return this;
  }

  /// Adds a raw GROUP BY fragment.
  QueryBuilder groupByRaw(dynamic sql, [dynamic bindings]) {
    _statements.add({
      'grouping': 'group',
      'type': 'groupByRaw',
      'value': sql is Raw ? sql : client.raw(sql.toString(), bindings),
    });
    return this;
  }

  /// Adds a raw ORDER BY fragment.
  QueryBuilder orderByRaw(dynamic sql, [dynamic bindings]) {
    _statements.add({
      'grouping': 'order',
      'type': 'orderByRaw',
      'value': sql is Raw ? sql : client.raw(sql.toString(), bindings),
    });
    return this;
  }

  /// Uses a raw table/subquery source in FROM.
  QueryBuilder fromRaw(dynamic sql, [dynamic bindings]) {
    _single['table'] = sql is Raw ? sql : client.raw(sql.toString(), bindings);
    return this;
  }

  // Modifiers
  Duration? _timeout;
  bool? _cancelOnTimeout;

  /// Sets a query timeout duration.
  ///
  /// [ms] is in milliseconds. [cancel] indicates whether cancellation should
  /// be requested when timeout is reached (driver support may vary).
  QueryBuilder timeout(int ms, {bool cancel = false}) {
    _timeout = Duration(milliseconds: ms);
    _cancelOnTimeout = cancel;
    return this;
  }

  /// Applies a reusable modifier callback to this builder.
  ///
  /// Example:
  /// ```dart
  /// void onlyActive(QueryBuilder qb) => qb.where('active', true);
  /// db.queryBuilder().table('users').modify(onlyActive);
  /// ```
  QueryBuilder modify(Function callback, [List<dynamic> args = const []]) {
    Function.apply(callback, <dynamic>[this, ...args]);
    return this;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // FULLTEXT SEARCH (whereFullText)
  // ─────────────────────────────────────────────────────────────────────────────

  /// Add a full-text search clause for the given column(s).
  ///
  /// This generates dialect-specific full-text queries:
  /// - **PostgreSQL**: `to_tsvector(col) @@ to_tsquery(?)` (optionally with language/config)
  /// - **MySQL**: `MATCH(col) AGAINST(?)` (optionally with mode)
  /// - **SQLite**: `col MATCH ?` (using FTS4/FTS5)
  ///
  /// [columns] can be a single `String` or a `List<String>`.
  /// [query] is the search string.
  /// [options] can include dialect-specific tweaks like `language` for PG or `mode` for MySQL.
  QueryBuilder whereFullText(
    dynamic columns,
    String query, [
    Map<String, dynamic>? options,
  ]) {
    _statements.add({
      'grouping': 'where',
      'type': 'whereFullText',
      'columns': columns, // String or List<String>
      'query': query,
      'options': options,
      'bool': 'and',
      'not': false,
    });
    return this;
  }

  /// OR variant of [whereFullText].
  QueryBuilder orWhereFullText(
    dynamic columns,
    String query, [
    Map<String, dynamic>? options,
  ]) {
    _statements.add({
      'grouping': 'where',
      'type': 'whereFullText',
      'columns': columns,
      'query': query,
      'options': options,
      'bool': 'or',
      'not': false,
    });
    return this;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // HAVING CLAUSES
}

// ─────────────────────────────────────────────────────────────────────────────
// OnConflictBuilder
//
