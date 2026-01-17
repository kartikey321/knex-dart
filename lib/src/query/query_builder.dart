import 'sql_string.dart';
import 'join_clause.dart';
import '../client/client.dart';
import '../util/enums.dart';
import '../raw.dart';
import 'aggregate_options.dart';

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
  QueryBuilder where(dynamic column, [dynamic operatorOrValue, dynamic value]) {
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

    _statements.add({
      'type': 'whereBasic',
      'grouping': 'where',
      'column': column,
      'operator': value == null ? '=' : operatorOrValue,
      'value': value ?? operatorOrValue,
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
    String column,
    dynamic operatorOrValue, [
    dynamic value,
  ]) {
    // Set bool to 'or' for next where clause
    _boolFlag = 'or';
    final stmt = {
      'type': 'whereBasic',
      'grouping': 'where',
      'column': column,
      'operator': value == null ? '=' : operatorOrValue,
      'value': value ?? operatorOrValue,
      'bool': _bool(), // Read and reset bool flag (will return 'or')
      'not': _not(), // Read and reset not flag
      'asColumn': _asColumnFlag, // Use flag for whereColumn support
    };
    _statements.add(stmt);
    return this;
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
  QueryBuilder whereNot(String column, [dynamic operator, dynamic value]) {
    // Warning: whereNot is not suitable for "in" and "between"
    // (should use whereNotIn and whereNotBetween instead)
    return _not(true).where(column, operator, value) as QueryBuilder;
  }

  /// OR version of WHERE NOT
  QueryBuilder orWhereNot(String column, [dynamic operator, dynamic value]) {
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
}
