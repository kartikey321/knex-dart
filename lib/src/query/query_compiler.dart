import '../client/client.dart';
import '../formatter/formatter.dart';
import '../util/enums.dart';
import '../raw.dart';
import 'query_builder.dart';
import 'sql_string.dart';

/// Query compiler that transforms QueryBuilder statements into SQL
///
/// JS Reference: lib/query/querycompiler.js
///
/// Core responsibilities:
/// - Group statements by type (columns, where, join, etc.)
/// - Compile statements into dialect-specific SQL
/// - Manage bindings for parameterized queries
/// - Generate unique query IDs
class QueryCompiler {
  final Client client;
  final QueryBuilder builder;

  /// Formatter for wrapping identifiers and columns
  late final Formatter formatter;

  /// Accumulated bindings for this query
  final List<dynamic> bindings = [];

  /// Single-value properties (table, etc.)
  late final Map<String, dynamic> single;

  /// Statements grouped by type
  late final Map<String, List<Map<String, dynamic>>> grouped;

  /// Query method (select, insert, update, delete)
  late final String method;

  /// JS Reference: querycompiler.js lines 49-67 (constructor)
  QueryCompiler(this.client, this.builder) {
    // Get method from builder
    method = builder.method.toString().split('.').last;

    // Get single values (table, etc.)
    single = Map<String, dynamic>.from(builder.single);

    // Group statements by type
    grouped = _groupStatements(builder.statements);

    // Create formatter
    formatter = client.formatter(builder);
  }

  /// Group statements by their grouping or type
  ///
  /// JS Reference: constructor uses lodash groupBy
  Map<String, List<Map<String, dynamic>>> _groupStatements(
    List<dynamic> statements,
  ) {
    final result = <String, List<Map<String, dynamic>>>{};

    for (final stmt in statements) {
      if (stmt is! Map<String, dynamic>) continue;

      // Group by 'grouping' field if present, otherwise by 'type'
      final key =
          stmt['grouping'] as String? ?? stmt['type'] as String? ?? 'unknown';

      result.putIfAbsent(key, () => []).add(stmt);
    }

    return result;
  }

  /// Compile query to SQL
  ///
  /// JS Reference: querycompiler.js lines 70-121 (toSQL)
  SqlString toSQL() {
    // Call method-specific compiler
    final sql = _compileMethod();

    // Generate UID (same pattern as Raw)
    final uid = _generateUid();

    return SqlString(sql, bindings, method: method, uid: uid);
  }

  /// Compile a subquery (QueryBuilder) to SQL with parameter renumbering
  String _compileSubquery(QueryBuilder subquery, {bool withParens = true}) {
    final bindingOffset = bindings.length;
    final subCompiler = client.queryCompiler(subquery);
    var sql = subCompiler.toSQL().sql;

    // Renumber parameters
    if (bindingOffset > 0 && subCompiler.bindings.isNotEmpty) {
      for (var i = subCompiler.bindings.length; i >= 1; i--) {
        sql = sql.replaceAll('\$$i', '\$${bindingOffset + i}');
      }
    }

    bindings.addAll(subCompiler.bindings);

    // Add parentheses if needed
    if (withParens) {
      sql = '($sql)';
    }

    // Add alias AFTER parentheses
    if (subquery.alias != null) {
      sql = '$sql as "${subquery.alias}"';
    }

    return sql;
  }

  /// Dispatch to method-specific compiler
  ///
  /// JS Reference: querycompiler.js _validateAndCompile dispatches to method
  String _compileMethod() {
    // Use the public method getter from builder
    final queryMethod = builder.method;

    switch (queryMethod) {
      case QueryMethod.select:
        return _select();
      case QueryMethod.insert:
        return _insertQuery();
      case QueryMethod.update:
        return _updateQuery();
      case QueryMethod.delete:
        return _deleteQuery();
      default:
        throw UnimplementedError(
          'Query method $queryMethod not yet implemented',
        );
    }
  }

  /// Compile SELECT query
  ///
  /// JS Reference: querycompiler.js lines 126-179 (select)
  ///
  /// For MVP: Just compile columns, more components added later
  String _select() {
    // Build base SELECT + FROM
    final parts = <String>[_columns()];

    // JOIN clause (after FROM, before WHERE)
    final joinSql = _join();
    if (joinSql.isNotEmpty) {
      parts.add(joinSql);
    }

    // WHERE clause
    final whereSql = _where();
    if (whereSql.isNotEmpty) {
      parts.add(whereSql);
    }

    // GROUP BY clause
    final groupSql = _group();
    if (groupSql.isNotEmpty) {
      parts.add(groupSql);
    }

    // HAVING clause
    final havingSql = _having();
    if (havingSql.isNotEmpty) {
      parts.add(havingSql);
    }

    // UNION clauses (before ORDER BY/LIMIT for correct SQL semantics)
    final unionSql = _union();
    if (unionSql.isNotEmpty) {
      parts.add(unionSql);
    }

    // ORDER BY clause
    final orderSql = _order();
    if (orderSql.isNotEmpty) {
      parts.add(orderSql);
    }

    // LIMIT clause
    final limitSql = _limit();
    if (limitSql.isNotEmpty) {
      parts.add(limitSql);
    }

    // OFFSET clause
    final offsetSql = _offset();
    if (offsetSql.isNotEmpty) {
      parts.add(offsetSql);
    }

    return parts.join(' ');
  }

  /// Get table name, properly wrapped
  ///
  /// JS Reference: Used in columns() via this.tableName getter
  String get tableName {
    final table = single['table'];
    if (table == null) return '';

    // Subquery
    if (table is QueryBuilder) {
      return _compileSubquery(table, withParens: true);
    }

    // Simple string table name
    if (table is String) {
      return formatter.wrapString(table);
    }

    // Raw or other complex types - for later
    return table.toString();
  }

  /// Compile columns clause (SELECT ... FROM ...)
  ///
  /// JS Reference: querycompiler.js lines 277-321 (columns)
  String _columns() {
    // Get column statements
    final columnStmts = grouped['columns'] ?? grouped['select'];

    // No explicit columns = SELECT *
    if (columnStmts == null || columnStmts.isEmpty) {
      if (tableName.isNotEmpty) {
        return 'select * from $tableName';
      }
      return 'select *';
    }

    // Check for DISTINCT flag and collect columns
    bool hasDistinct = false;
    final cols = <String>[];

    for (final stmt in columnStmts) {
      // Handle distinct
      if (stmt['distinct'] == true) {
        hasDistinct = true;
        // If distinct has specific columns, add them
        final distinctValue = stmt['value'];
        if (distinctValue is List && distinctValue.isNotEmpty) {
          final formatted = formatter.columnize(distinctValue);
          cols.add(formatted);
          continue;
        }
      }

      // Handle aggregate functions
      if (stmt['type'] == 'aggregate') {
        cols.addAll(_aggregate(stmt));
        continue;
      }

      // Handle aggregateRaw
      if (stmt['type'] == 'aggregateRaw') {
        cols.add(_aggregateRaw(stmt));
        continue;
      }

      // Handle distinctOn
      if (stmt['distinctOn'] != null) {
        if (stmt['distinctOn'] is List) {
          final distinctCols = stmt['distinctOn'] as List;
          final formatted = formatter.columnize(distinctCols);
          cols.add(formatted);
          continue;
        }
      }

      // Handle regular columns (but check for QueryBuilder first)
      final columns = stmt['columns'];
      if (columns != null && columns is List && columns.isNotEmpty) {
        // Check each column - could be string or QueryBuilder
        for (final col in columns) {
          if (col is QueryBuilder) {
            cols.add(_compileSubquery(col));
          } else {
            // Regular string column
            cols.add(formatter.wrap(col.toString()));
          }
        }
        continue;
      }

      // Handle QueryBuilder subquery in SELECT (when passed as value)
      final stmtValue = stmt['value'];
      if (stmtValue is QueryBuilder) {
        cols.add(_compileSubquery(stmtValue));
        continue;
      }

      // Handle Raw in SELECT
      final rawValue = stmt['value'];
      if (rawValue != null && rawValue is Raw) {
        final sql = rawValue.toSQL();
        bindings.addAll(sql.bindings);
        cols.add(sql.sql);
      }
    }

    // Build SELECT clause
    final columnList = cols.isEmpty ? '*' : cols.join(', ');
    final distinctClause = hasDistinct ? 'distinct ' : '';

    if (tableName.isNotEmpty) {
      return 'select $distinctClause$columnList from $tableName';
    }

    return 'select $distinctClause$columnList';
  }

  /// Compile WHERE clause
  ///
  /// JS Reference: querycompiler.js lines 570-595 (where)
  ///
  /// Iterates through WHERE statements and dispatches to type-specific compilers.
  /// First statement gets 'where' keyword, subsequent ones get boolean operator (and/or).
  String _where() {
    final wheres = grouped['where'];
    if (wheres == null || wheres.isEmpty) return '';

    final sql = <String>[];

    for (final stmt in wheres) {
      // Dispatch to type-specific compiler
      final val = _compileWhereType(stmt);

      if (val.isNotEmpty) {
        if (sql.isEmpty) {
          sql.add('where');
        } else {
          // Add boolean operator (and/or)
          final bool = stmt['bool'] as String? ?? 'and';
          sql.add(bool);
        }
        sql.add(val);
      }
    }

    return sql.length > 1 ? sql.join(' ') : '';
  }

  /// Dispatch to type-specific WHERE compiler
  String _compileWhereType(Map<String, dynamic> statement) {
    final type = statement['type'] as String?;

    switch (type) {
      case 'whereBasic':
        return whereBasic(statement);
      case 'whereNull':
        return whereNull(statement);
      case 'whereIn':
        return whereIn(statement);
      case 'whereRaw': // NEW
        return whereRaw(statement);
      case 'whereBetween': // NEW
        return whereBetween(statement);
      case 'whereExists': // NEW
        return whereExists(statement);
      case 'whereWrapped': // NEW
        return whereWrapped(statement);
      default:
        throw Exception('Unknown WHERE type: $type');
    }
  }

  /// Compile basic WHERE clause (column operator value)
  ///
  /// JS Reference: querycompiler.js lines 1055-1075 (whereBasic)
  ///
  /// Examples:
  /// - "status" = $1
  /// - "age" > $1
  /// - "users"."id" != $1
  String whereBasic(Map<String, dynamic> statement) {
    return _not(statement, '') +
        formatter.wrap(statement['column']) +
        ' ' +
        formatter.operator(statement['operator']) +
        ' ' +
        _valueClause(statement);
  }

  /// Format WHERE clause value
  ///
  /// JS Reference: querycompiler.js lines 979-993 (_valueClause)
  ///
  /// If asColumn=true, wraps value as column name.
  /// Otherwise, adds to bindings and returns parameter placeholder.
  String _valueClause(Map<String, dynamic> statement) {
    final asColumn = statement['asColumn'] as bool? ?? false;

    if (asColumn) {
      // Value is a column reference, wrap it as identifier
      return formatter.wrap(statement['value']);
    } else {
      // Value is a binding parameter
      return client.parameter(statement['value'], bindings);
    }
  }

  /// Add NOT prefix if statement has not=true
  ///
  /// JS Reference: querycompiler.js lines 1267-1270 (_not)
  String _not(Map<String, dynamic> statement, String str) {
    final not = statement['not'] as bool? ?? false;
    if (not) return 'not $str';
    return str;
  }

  /// Compile WHERE NULL clause
  ///
  /// JS Reference: querycompiler.js lines 1040-1051 (whereNull)
  ///
  /// Generates "column" is null or "column" is not null
  String whereNull(Map<String, dynamic> statement) {
    final column = formatter.wrap(statement['column']);
    return '$column is ${_not(statement, 'null')}';
  }

  /// Compile WHERE IN clause
  ///
  /// JS Reference: querycompiler.js lines 1016-1024 (whereIn)
  ///
  /// Supports:
  /// - Array of values: "column" in (?, ?, ?)
  /// - Subquery: "column" in (SELECT ...)
  String whereIn(Map<String, dynamic> statement) {
    final column = formatter.wrap(statement['column']);
    final values = statement['value'];

    String valueClause;
    if (values is QueryBuilder) {
      // Subquery
      valueClause = _compileSubquery(values);
    } else {
      // Array of values
      final valuesList = values as List;
      final placeholders = <String>[];
      for (final value in valuesList) {
        placeholders.add(client.parameter(value, bindings));
      }
      valueClause = '(${placeholders.join(', ')})';
    }

    return '$column ${_not(statement, 'in ')}$valueClause';
  }

  /// Compile WHERE raw clause
  ///
  /// JS Reference: querycompiler.js whereRaw()
  ///
  /// Compiles a Raw SQL condition
  String whereRaw(Map<String, dynamic> statement) {
    final raw = statement['value'] as Raw;
    final sql = raw.toSQL();
    bindings.addAll(sql.bindings);
    return sql.sql;
  }

  /// Compile WHERE BETWEEN clause
  ///
  /// JS Reference: querycompiler.js whereBetween() (lines 1103-1121)
  ///
  /// Examples:
  /// - "age" between $1 and $2
  /// - "score" not between $1 and $2
  String whereBetween(Map<String, dynamic> statement) {
    final column = formatter.wrap(statement['column']);
    final values = statement['value'] as List;

    final placeholders = <String>[];
    for (final value in values) {
      placeholders.add(client.parameter(value, bindings));
    }

    final betweenClause = placeholders.join(' and ');
    return '$column ${_not(statement, 'between ')}$betweenClause';
  }

  /// Compile WHERE EXISTS clause
  ///
  /// JS Reference: querycompiler.js whereExists() (lines 1077-1090)
  ///
  /// Examples:
  /// - exists (SELECT ...)
  /// - not exists (SELECT ...)
  String whereExists(Map<String, dynamic> statement) {
    final callback = statement['value'] as Function;

    // Create a new QueryBuilder for the subquery
    final subBuilder = QueryBuilder(client);
    callback(subBuilder);

    // Get the SQL for the subquery
    final subSQL = subBuilder.toSQL();
    bindings.addAll(subSQL.bindings);

    return '${_not(statement, 'exists ')}(${subSQL.sql})';
  }

  /// Compile WHERE WRAPPED clause (grouped conditions)
  ///
  /// JS Reference: querycompiler.js whereWrapped() (lines 1092-1101)
  ///
  /// Groups WHERE conditions in parentheses
  ///
  /// Example:
  /// - (age > 18 OR verified = true)
  String whereWrapped(Map<String, dynamic> statement) {
    final callback = statement['value'] as Function;

    // Create a new QueryBuilder for the wrapped conditions
    final subBuilder = QueryBuilder(client);
    callback(subBuilder);

    // Get the current binding count before adding subquery bindings
    final bindingOffset = bindings.length;

    // Compile the WHERE clauses from the sub-builder
    final subCompiler = client.queryCompiler(subBuilder);
    var whereSQL = subCompiler._where();

    if (whereSQL.isEmpty) return '';

    // Renumber parameter placeholders to continue from parent's count
    // The subquery uses $1, $2, etc. but should use $N+1, $N+2, etc.
    if (bindingOffset > 0 && subCompiler.bindings.isNotEmpty) {
      // Replace $1 with $(bindingOffset+1), $2 with $(bindingOffset+2), etc.
      // Must iterate backwards to avoid replacing $1 in $10, $11, etc.
      for (var i = subCompiler.bindings.length; i >= 1; i--) {
        whereSQL = whereSQL.replaceAll('\$$i', '\$${bindingOffset + i}');
      }
    }

    // Merge bindings from subquery into parent bindings
    bindings.addAll(subCompiler.bindings);

    // Remove the leading "where " (6 characters)
    final condition = whereSQL.substring(6);

    // Apply NOT if needed
    final notStr = (statement['not'] as bool? ?? false) ? 'not ' : '';

    return '$notStr($condition)';
  }

  /// Compile JOIN clauses
  ///
  /// JS Reference: querycompiler.js join() method
  ///
  /// Supports:
  /// - Simple joins: INNER/LEFT/RIGHT JOIN with single ON
  /// - Callback joins: Complex ON conditions with AND/OR
  /// - CROSS JOIN: No ON clause
  String _join() {
    final joins = grouped['join'];
    if (joins == null || joins.isEmpty) return '';

    final sql = <String>[];
    for (final stmt in joins) {
      final joinType = stmt['join'] as String? ?? 'inner';
      final table = formatter.wrap(stmt['table']);

      // Handle CROSS JOIN (no ON clause)
      if (joinType == 'cross') {
        sql.add('cross join $table');
        continue;
      }

      // Check for JoinClause (callback-based join with multiple conditions)
      if (stmt['joinClause'] != null) {
        final joinClause = stmt['joinClause'];
        final onConditions = _compileJoinClauses(joinClause);
        sql.add('$joinType join $table on $onConditions');
      } else {
        // Simple join with two columns
        final col1 = formatter.wrap(stmt['column1']);
        final col2 = formatter.wrap(stmt['column2']);
        sql.add('$joinType join $table on $col1 = $col2');
      }
    }

    return sql.join(' ');
  }

  /// Compile JoinClause ON conditions
  ///
  /// Handles multiple ON clauses with AND/OR logic
  String _compileJoinClauses(dynamic joinClause) {
    final clauses = joinClause.clauses as List<Map<String, dynamic>>;
    if (clauses.isEmpty) return '';

    final parts = <String>[];
    bool isFirst = true;

    for (final cond in clauses) {
      if (cond['type'] == 'onBasic') {
        final first = formatter.wrap(cond['column']);
        final operator = cond['operator'];
        final second = formatter.wrap(cond['value']);

        if (isFirst) {
          parts.add('$first $operator $second');
          isFirst = false;
        } else {
          final bool = cond['bool']; // 'and' or 'or'
          parts.add('$bool $first $operator $second');
        }
      }
    }

    return parts.join(' ');
  }

  /// Compile GROUP BY clause
  ///
  /// JS Reference: querycompiler.js lines 597-599 (group), uses _groupsOrders
  ///
  /// Groups rows by one or more columns
  String _group() {
    final groups = grouped['group'];
    if (groups == null || groups.isEmpty) return '';

    final columns = <String>[];
    for (final stmt in groups) {
      columns.add(formatter.wrap(stmt['value']));
    }

    return 'group by ${columns.join(', ')}';
  }

  /// Compile HAVING clause
  ///
  /// JS Reference: querycompiler.js lines 606-624 (having)
  ///
  /// Filters aggregated groups (similar to WHERE for groups)
  String _having() {
    final havings = grouped['having'];
    if (havings == null || havings.isEmpty) return '';

    final sql = <String>['having'];

    for (var i = 0; i < havings.length; i++) {
      final stmt = havings[i];
      final val = _compileHavingType(stmt);

      if (val.isNotEmpty) {
        if (i > 0) {
          // Add boolean operator (and/or)
          final bool = stmt['bool'] as String? ?? 'and';
          sql.add(bool);
        }
        sql.add(val);
      }
    }

    return sql.length > 1 ? sql.join(' ') : '';
  }

  /// Dispatch to type-specific HAVING compiler
  String _compileHavingType(Map<String, dynamic> statement) {
    final type = statement['type'] as String?;

    switch (type) {
      case 'havingBasic':
        return havingBasic(statement);
      default:
        throw Exception('Unknown HAVING type: $type');
    }
  }

  /// Compile basic HAVING clause
  ///
  /// JS Reference: Similar to whereBasic
  ///
  /// Format: "column" operator value
  String havingBasic(Map<String, dynamic> statement) {
    final column = formatter.wrap(statement['column']);
    final operator = statement['operator'] as String? ?? '=';
    final value = client.parameter(statement['value'], bindings);
    return '$column $operator $value';
  }

  /// Compile ORDER BY clause
  ///
  /// JS Reference: querycompiler.js lines 601-603 (order), 1441-1448 (_groupsOrders)
  ///
  /// Iterates through ORDER BY statements and formats each with direction.
  /// Multiple columns are joined with commas.
  String _order() {
    final orders = grouped['order'];
    if (orders == null || orders.isEmpty) return '';

    final sql = <String>[];

    for (final stmt in orders) {
      // Get column and wrap it
      final column = formatter.wrap(stmt['value']);

      // Get direction (default to 'asc' if not specified)
      final direction = stmt['direction'] as String? ?? 'asc';

      // Format: "column" asc  or  "column" desc
      sql.add('$column $direction');
    }

    return 'order by ${sql.join(', ')}';
  }

  /// Compile LIMIT clause
  ///
  /// JS Reference: querycompiler.js lines 807-811 (limit)
  ///
  /// LIMIT value is parameterized (added to bindings)
  String _limit() {
    final limit = single['limit'];
    if (limit == null) return '';

    // Add limit value to bindings and get placeholder
    return 'limit ${client.parameter(limit, bindings)}';
  }

  /// Compile OFFSET clause
  ///
  /// JS Reference: querycompiler.js lines 813-816 (offset)
  ///
  /// OFFSET value is parameterized (added to bindings)
  String _offset() {
    final offset = single['offset'];
    if (offset == null) return '';

    // Add offset value to bindings and get placeholder
    return 'offset ${client.parameter(offset, bindings)}';
  }

  /// Compile UNION clauses
  ///
  /// JS Reference: querycompiler.js _union() (lines 515-543)
  String _union() {
    final unions = grouped['union'];
    if (unions == null || unions.isEmpty) return '';

    final parts = <String>[];

    for (final stmt in unions) {
      final type = stmt['type'] as String; // 'union' or 'union all'
      final query = stmt['value'];
      final wrap = stmt['wrap'] as bool? ?? false;

      String sql;

      if (query is QueryBuilder) {
        // Get current binding count BEFORE compiling unioned query
        final bindingOffset = bindings.length;

        // Compile the query
        final queryCompiler = client.queryCompiler(query);
        final querySQL = queryCompiler.toSQL();
        sql = querySQL.sql;

        // Renumber parameters to continue from parent's count
        if (bindingOffset > 0 && queryCompiler.bindings.isNotEmpty) {
          // Iterate backwards to avoid replacing $1 in $10, $11, etc.
          for (var i = queryCompiler.bindings.length; i >= 1; i--) {
            sql = sql.replaceAll('\$$i', '\$${bindingOffset + i}');
          }
        }

        // Merge bindings
        bindings.addAll(queryCompiler.bindings);
      } else if (query is Raw) {
        final rawSQL = query.toSQL();
        sql = rawSQL.sql;
        bindings.addAll(rawSQL.bindings);
      } else {
        continue;
      }

      // Wrap if needed
      if (wrap) {
        sql = '($sql)';
      }

      parts.add('$type $sql');
    }

    return parts.join(' ');
  }

  /// Generate unique query ID
  ///
  /// Same pattern as Raw._generateUid()
  String _generateUid() {
    final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final random =
        (DateTime.now().microsecond * 1000 + DateTime.now().millisecond)
            .toRadixString(36);
    return '$timestamp$random'.substring(0, 12);
  }

  /// Compile INSERT query
  ///
  /// JS Reference: querycompiler.js insert() (line 194)
  String _insertQuery() {
    final parts = <String>[];

    parts.add(_insert());

    final returning = _returning();
    if (returning.isNotEmpty) {
      parts.add(returning);
    }

    return parts.join(' ');
  }

  /// Compile INSERT statement
  ///
  /// JS Reference: querycompiler.js _insertBody() (line 222)
  String _insert() {
    final insertValue = single['insert'];
    if (insertValue == null) return '';

    // Normalize to list of maps
    final List<Map<String, dynamic>> rows;
    if (insertValue is List) {
      if (insertValue.isEmpty) {
        throw ArgumentError('Cannot insert empty array');
      }
      rows = insertValue.cast<Map<String, dynamic>>();
    } else if (insertValue is Map<String, dynamic>) {
      if (insertValue.isEmpty) {
        throw ArgumentError('Cannot insert empty object');
      }
      rows = [insertValue];
    } else {
      throw ArgumentError('INSERT values must be Map or List<Map>');
    }

    // Get columns from first row
    final columns = rows[0].keys.toList();
    final columnsSql = columns.map((c) => formatter.wrap(c)).join(', ');

    // Build VALUES clauses
    final valuesClauses = <String>[];
    for (final row in rows) {
      final rowBindings = <String>[];
      for (final col in columns) {
        final value = row[col];
        rowBindings.add(client.parameter(value, bindings));
      }
      valuesClauses.add('(${rowBindings.join(', ')})');
    }

    final table = formatter.wrap(single['table']);
    return 'insert into $table ($columnsSql) values ${valuesClauses.join(', ')}';
  }

  /// Compile RETURNING clause
  ///
  /// JS Reference: PostgreSQL-specific RETURNING clause
  String _returning() {
    final returningCols = single['returning'];
    if (returningCols == null ||
        returningCols is! List ||
        returningCols.isEmpty) {
      return '';
    }

    final columns = (returningCols as List<String>)
        .map((c) => formatter.wrap(c))
        .join(', ');

    return 'returning $columns';
  }

  /// Compile UPDATE query
  ///
  /// JS Reference: querycompiler.js update() (line 254)
  String _updateQuery() {
    final parts = <String>[];

    parts.add(_update());

    // Assuming _where() is defined elsewhere and returns a String
    // If not, this will cause a compilation error.
    // For this change, I'm assuming it exists.
    final where = _where();
    if (where.isNotEmpty) {
      parts.add(where);
    }

    final returning = _returning();
    if (returning.isNotEmpty) {
      parts.add(returning);
    }

    return parts.join(' ');
  }

  /// Compile UPDATE statement
  ///
  /// JS Reference: querycompiler.js _updateBody()
  String _update() {
    final updateMap = single['update'] as Map<String, dynamic>?;
    final counterMap = single['counter'] as Map<String, dynamic>?;

    if (updateMap == null && counterMap == null) {
      throw ArgumentError('Empty .update() call detected!');
    }

    final updates = <String>[];

    // Handle regular UPDATE values
    if (updateMap != null) {
      for (final entry in updateMap.entries) {
        final col = formatter.wrap(entry.key);
        final val = client.parameter(entry.value, bindings);
        updates.add('$col = $val');
      }
    }

    // Handle increment/decrement counters
    if (counterMap != null) {
      for (final entry in counterMap.entries) {
        final col = formatter.wrap(entry.key);
        final amount = entry.value as num;
        final operator = amount >= 0 ? '+' : '-';
        final absAmount = client.parameter(amount.abs(), bindings);
        updates.add('$col = $col $operator $absAmount');
      }
    }

    final table = formatter.wrap(single['table']);
    return 'update $table set ${updates.join(', ')}';
  }

  /// Compile DELETE query
  ///
  /// JS Reference: querycompiler.js delete() (line 263)
  String _deleteQuery() {
    final parts = <String>[];

    parts.add(_delete());

    final where = _where();
    if (where.isNotEmpty) {
      parts.add(where);
    }

    final returning = _returning();
    if (returning.isNotEmpty) {
      parts.add(returning);
    }

    return parts.join(' ');
  }

  /// Compile DELETE statement
  ///
  /// JS Reference: querycompiler.js _deleteBody()
  String _delete() {
    final table = formatter.wrap(single['table']);
    return 'delete from $table';
  }

  /// Compile aggregate functions
  ///
  /// Handles array, object, and string column values with optional aliasing
  /// and distinct support.
  List<String> _aggregate(Map<String, dynamic> stmt) {
    final value = stmt['value'];
    final method = stmt['method'] as String;
    final distinct = stmt['aggregateDistinct'] == true ? 'distinct ' : '';

    // Helper to add alias
    String addAlias(String value, String? alias) {
      if (alias != null && alias.isNotEmpty) {
        return '$value as ${client.wrapIdentifier(alias)}';
      }
      return value;
    }

    // Handle array values: count(['id', 'name'])
    if (value is List) {
      final columns = value
          .map((col) => client.wrapIdentifier(col.toString()))
          .join(', ');
      final distinctPart = distinct.isNotEmpty ? 'distinct $columns' : columns;
      final aggregated = '$method($distinctPart)';
      return [addAlias(aggregated, stmt['alias'] as String?)];
    }

    // Handle map values: count({total: 'id', cnt: 'name'})
    if (value is Map) {
      if (stmt['alias'] != null) {
        throw Exception('When using an object explicit alias can not be used');
      }
      return value.entries.map((entry) {
        final alias = entry.key as String;
        final column = entry.value;
        if (column is List) {
          final columns = column
              .map((col) => client.wrapIdentifier(col.toString()))
              .join(', ');
          final distinctPart = distinct.isNotEmpty
              ? 'distinct $columns'
              : columns;
          final aggregated = '$method($distinctPart)';
          return addAlias(aggregated, alias);
        }
        final wrapped = client.wrapIdentifier(column.toString());
        final aggregated = '$method($distinct$wrapped)';
        return addAlias(aggregated, alias);
      }).toList();
    }

    // Handle string values with optional inline " as alias" parsing
    var column = value.toString();
    String? alias = stmt['alias'] as String?;

    final asIndex = column.toLowerCase().indexOf(' as ');
    if (asIndex != -1) {
      if (alias != null) {
        throw Exception('Found multiple aliases for same column: $column');
      }
      alias = column.substring(asIndex + 4).trim();
      column = column.substring(0, asIndex).trim();
    }

    final wrapped = client.wrapIdentifier(column);
    final aggregated = '$method($distinct$wrapped)';
    return [addAlias(aggregated, alias)];
  }

  /// Compile raw aggregate functions
  ///
  /// Handles Raw instances within aggregate functions (e.g., count(raw(...))
  String _aggregateRaw(Map<String, dynamic> stmt) {
    final distinct = stmt['aggregateDistinct'] == true ? 'distinct ' : '';
    final method = stmt['method'] as String;
    final raw = stmt['value'] as Raw;
    final sql = raw.toSQL();

    // Add bindings from the Raw instance
    bindings.addAll(sql.bindings);

    return '$method($distinct${sql.sql})';
  }
}
