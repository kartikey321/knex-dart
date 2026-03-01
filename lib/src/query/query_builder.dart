import 'sql_string.dart';
import 'join_clause.dart';
import '../client/client.dart';
import '../util/enums.dart';
import '../raw.dart';
import 'aggregate_options.dart';
import 'analytic.dart';
import 'on_conflict_builder.dart';
export 'analytic.dart';
export 'on_conflict_builder.dart';
export 'json_builder.dart';

// Sentinel for undefined arguments
const _undefined = Object();

/// Query builder for constructing SQL queries
///
/// Provides a fluent API for building SELECT, INSERT, UPDATE, and DELETE queries.
/// This is a stub implementation - full implementation will be added in Week 2.
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
  /// JS Reference: querybuilder.js insert() (line 1225)
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
  /// JS Reference: querybuilder.js returning() (PostgreSQL RETURNING clause)
  ///
  /// Example: insert({...}).returning(['id', 'name'])
  QueryBuilder returning(List<String> columns) {
    _single['returning'] = columns;
    return this;
  }

  /// Specify conflict target and action for INSERT ... ON CONFLICT.
  ///
  /// Mirrors the Knex.js `onConflict()` API exactly:
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
  /// JS Reference: querybuilder.js onConflict() (line 1255-onwards)
  OnConflictBuilder onConflict([dynamic column]) {
    return OnConflictBuilder(this, column);
  }

  /// Update rows with given values
  ///
  /// JS Reference: querybuilder.js update() (line 1234)
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
  /// JS Reference: querybuilder.js increment()
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
  /// JS Reference: querybuilder.js decrement()
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
  /// JS Reference: querybuilder.js first() (line 1144)
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
  /// JS Reference: querybuilder.js pluck() (line 1164)
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
  /// JS Reference: querybuilder.js distinct() (line 300)
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
  /// JS Reference: querybuilder.js join() (line 323), innerJoin() (line 352)
  ///
  /// Supports:
  /// - Simple: join('orders', 'users.id', 'orders.user_id')
  /// - Callback: join('orders', (j) => j.on('users.id', 'orders.user_id'))
  QueryBuilder join(String table, [dynamic first, String? second]) {
    return _performJoin('inner', table, first, second);
  }

  /// Add a LEFT JOIN clause
  ///
  /// JS Reference: querybuilder.js leftJoin() (line 356)
  ///
  /// Supports:
  /// - Simple: leftJoin('profiles', 'users.id', 'profiles.user_id')
  /// - Callback: leftJoin('profiles', (j) => j.on('users.id', 'profiles.user_id'))
  QueryBuilder leftJoin(String table, [dynamic first, String? second]) {
    return _performJoin('left', table, first, second);
  }

  /// Add a RIGHT JOIN clause
  ///
  /// JS Reference: querybuilder.js rightJoin() (line 364)
  ///
  /// Supports:
  /// - Simple: rightJoin('reviews', 'products.id', 'reviews.product_id')
  /// - Callback: rightJoin('reviews', (j) => j.on('products.id', 'reviews.product_id'))
  QueryBuilder rightJoin(String table, [dynamic first, String? second]) {
    return _performJoin('right', table, first, second);
  }

  /// Add a FULL OUTER JOIN clause
  ///
  /// JS Reference: querybuilder.js fullOuterJoin() (line 376)
  QueryBuilder fullOuterJoin(String table, [dynamic first, String? second]) {
    return _performJoin('full outer', table, first, second);
  }

  /// Add a CROSS JOIN clause
  ///
  /// JS Reference: querybuilder.js crossJoin() (line 380)
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

  /// Internal helper for performing joins
  ///
  /// Handles both simple and callback-based joins
  QueryBuilder _performJoin(
    String joinType,
    String table, [
    dynamic first,
    String? second,
  ]) {
    if (first is Function) {
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
  /// JS Reference: querybuilder.js where()
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
    if (column is Function) {
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
  /// JS Reference: querybuilder.js orderBy() (lines 752-764)
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
  /// JS Reference: querybuilder.js limit() (lines 1048-1057)
  ///
  /// Limits the number of rows returned
  QueryBuilder limit(int value) {
    _single['limit'] = value;
    return this;
  }

  /// Set the OFFSET for the query
  ///
  /// JS Reference: querybuilder.js offset() (lines 1029-1045)
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
  /// JS Reference: lib/query/querybuilder.js lines 1660-1669
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
  /// JS Reference: lib/query/querybuilder.js lines 1649-1658
  dynamic _bool([String? val]) {
    if (val != null) {
      _boolFlag = val;
      return this;
    }
    final ret = _boolFlag;
    _boolFlag = 'and';
    return ret;
  }

  /// Get or set the "asColumnFlag" value
  ///
  /// When called with a value, sets the flag and returns `this` for chaining.
  /// When called without arguments, returns current value and resets to `false`.
  ///
  /// JS Reference: lib/query/querybuilder.js lines 1671-1679
  dynamic _asColumn([bool? val]) {
    if (val != null) {
      _asColumnFlag = val;
      return this;
    }
    final ret = _asColumnFlag;
    _asColumnFlag = false;
    return ret;
  }

  /// Add an OR WHERE clause
  ///
  /// JS Reference: querybuilder.js orWhere() (line 483)
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
  /// JS Reference: querybuilder.js whereNull() (line 632)
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
  /// JS Reference: querybuilder.js whereNotNull() (line 649)
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
  /// JS Reference: querybuilder.js whereIn() (line 602)
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
  /// JS Reference: querybuilder.js whereNotIn() (line 622)
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
  /// JS Reference: querybuilder.js whereColumn() (lines 475-480)
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
  /// JS Reference: querybuilder.js whereBetween() (lines 658-677)
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
  /// JS Reference: querybuilder.js whereNotBetween() (lines 679-682)
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
  /// JS Reference: querybuilder.js whereNot() (lines 509-519)
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
  /// JS Reference: querybuilder.js whereExists() (lines 574-584)
  ///
  /// Example:
  /// ```dart
  /// whereExists((qb) {
  ///   qb.select('*').from('orders').whereRaw('orders.user_id = users.id');
  /// })
  /// ```
  QueryBuilder whereExists(Function callback) {
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
  /// JS Reference: querybuilder.js whereNotExists() (lines 586-589)
  QueryBuilder whereNotExists(Function callback) {
    return _not(true).whereExists(callback) as QueryBuilder;
  }

  /// OR version of WHERE EXISTS
  QueryBuilder orWhereExists(Function callback) {
    return _bool('or').whereExists(callback) as QueryBuilder;
  }

  /// OR version of WHERE NOT EXISTS
  QueryBuilder orWhereNotExists(Function callback) {
    return _bool('or')._not(true).whereExists(callback) as QueryBuilder;
  }

  /// Add grouped WHERE conditions in parentheses
  ///
  /// JS Reference: querybuilder.js whereWrapped() (lines 562-572)
  ///
  /// Example:
  /// ```dart
  /// whereWrapped((qb) {
  ///   qb.where('age', '>', 18).orWhere('verified', true);
  /// })
  /// // Generates: WHERE (age > 18 OR verified = true)
  /// ```
  QueryBuilder whereWrapped(Function callback) {
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
  /// JS Reference: querybuilder.js groupBy() (line 728)
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
  /// Knex.js equivalent: `.intersect([qb1, qb2])`
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
  /// Knex.js equivalent: `.except([qb1, qb2])`
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
  /// JS Reference: querybuilder.js with() (line 164)
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
  /// JS Reference: querybuilder.js withRecursive()
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
  /// JS Reference: querybuilder.js having() (line 846)
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
  /// JS Reference: querybuilder.js havingRaw() (line 809)
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
  /// JS Reference: querybuilder.js orHaving()
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
  /// JS Reference: querybuilder.js havingIn()
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
  /// JS Reference: querybuilder.js havingBetween()
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
  /// JS Reference: querybuilder.js havingNull()
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
  // Dart port of Knex.js querybuilder.js _analytic(), rank(), denseRank(),
  // rowNumber() (lines 1568-1631) and analytic.js.
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
          : (second is! List ? [second] : second as List);
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
  /// Knex.js: `.rank(alias, orderByClause, [partitionByClause])`
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
  // BUILDER UTILITIES & LOCKS
  // ============================================================================

  /// Deep clones the query builder
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

  /// Clears all standard groupings (select, where, group, order, having)
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

  /// Truncates the table
  QueryBuilder truncate() {
    _method = QueryMethod.truncate;
    return this;
  }

  QueryBuilder clearSelect() {
    _statements.removeWhere((stmt) => stmt['grouping'] == 'columns');
    return this;
  }

  QueryBuilder clearWhere() {
    _statements.removeWhere((stmt) => stmt['grouping'] == 'where');
    return this;
  }

  QueryBuilder clearGroup() {
    _statements.removeWhere((stmt) => stmt['grouping'] == 'group');
    return this;
  }

  QueryBuilder clearOrder() {
    _statements.removeWhere((stmt) => stmt['grouping'] == 'order');
    return this;
  }

  QueryBuilder clearHaving() {
    _statements.removeWhere((stmt) => stmt['grouping'] == 'having');
    return this;
  }

  QueryBuilder clearCounters() {
    _single.remove('counter');
    return this;
  }

  /// Join raw SQL
  QueryBuilder joinRaw(dynamic sql, [dynamic bindings]) {
    _statements.add({
      'grouping': 'join',
      'type': 'joinRaw',
      'value': sql is Raw ? sql : client.raw(sql.toString(), bindings),
    });
    return this;
  }

  /// Group by raw SQL
  QueryBuilder groupByRaw(dynamic sql, [dynamic bindings]) {
    _statements.add({
      'grouping': 'group',
      'type': 'groupByRaw',
      'value': sql is Raw ? sql : client.raw(sql.toString(), bindings),
    });
    return this;
  }

  /// Order by raw SQL
  QueryBuilder orderByRaw(dynamic sql, [dynamic bindings]) {
    _statements.add({
      'grouping': 'order',
      'type': 'orderByRaw',
      'value': sql is Raw ? sql : client.raw(sql.toString(), bindings),
    });
    return this;
  }

  /// Select from raw SQL
  QueryBuilder fromRaw(dynamic sql, [dynamic bindings]) {
    _single['table'] = sql is Raw ? sql : client.raw(sql.toString(), bindings);
    return this;
  }

  // Modifiers
  Duration? _timeout;
  bool? _cancelOnTimeout;

  QueryBuilder timeout(int ms, {bool cancel = false}) {
    _timeout = Duration(milliseconds: ms);
    _cancelOnTimeout = cancel;
    return this;
  }

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
