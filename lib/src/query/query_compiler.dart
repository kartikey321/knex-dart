import '../client/client.dart';
import '../formatter/formatter.dart';
import '../util/enums.dart';
import '../raw.dart';
import 'query_builder.dart';
import 'join_clause.dart';
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
    final pluck = builder.method == QueryMethod.pluck
        ? _pluckColumnName()
        : null;

    return SqlString(sql, bindings, method: method, uid: uid, pluck: pluck);
  }

  /// Return normalized pluck column name (matches Knex.js behavior).
  String? _pluckColumnName() {
    final rawPluck = single['pluck'];
    if (rawPluck == null) return null;

    var value = rawPluck.toString();
    if (value.contains('.')) {
      value = value.split('.').last;
    }
    return value;
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
      case QueryMethod.first:
      case QueryMethod.pluck:
        return _select();
      case QueryMethod.insert:
        return _insertQuery();
      case QueryMethod.update:
        return _updateQuery();
      case QueryMethod.delete:
        return _deleteQuery();
      case QueryMethod.truncate:
        return _truncateQuery();
    }
  }

  /// Compile SELECT query
  ///
  /// JS Reference: querycompiler.js lines 126-179 (select)
  ///
  /// For MVP: Just compile columns, more components added later
  String _select() {
    final parts = <String>[];

    // WITH clauses (must come first in SQL)
    final withSql = _with();
    if (withSql.isNotEmpty) {
      parts.add(withSql);
    }

    // Build base SELECT + FROM
    parts.add(_columns());

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

    // Lock clause (FOR UPDATE / FOR SHARE / ...)
    final lockSql = _lock();
    if (lockSql.isNotEmpty) {
      parts.add(lockSql);
    }

    // Lock wait mode (SKIP LOCKED / NOWAIT)
    final waitModeSql = _waitMode();
    if (waitModeSql.isNotEmpty) {
      parts.add(waitModeSql);
    }

    return parts.join(' ');
  }

  /// Get table name, properly wrapped
  ///
  /// JS Reference: Used in columns() via this.tableName getter
  // Cache for tableName so Raw bindings are only consumed once
  String? _tableNameCache;

  String get tableName {
    if (_tableNameCache != null) return _tableNameCache!;

    final table = single['table'];
    if (table == null) return _tableNameCache = '';

    // Subquery
    if (table is QueryBuilder) {
      return _tableNameCache = _compileSubquery(table, withParens: true);
    }

    // Raw (from fromRaw())
    if (table is Raw) {
      final sql = table.toSQL();
      bindings.addAll(sql.bindings);
      return _tableNameCache = sql.sql;
    }

    // Simple string table name
    if (table is String) {
      return _tableNameCache = _wrapTableIdentifier(table);
    }

    return _tableNameCache = table.toString();
  }

  /// Wrap table identifier with JS-like lowercase `as` for aliases.
  ///
  /// This keeps table alias SQL closer to Knex.js output while leaving
  /// existing column alias formatting behavior unchanged.
  String _wrapTableIdentifier(String table) {
    final lower = table.toLowerCase();
    final asIndex = lower.indexOf(' as ');
    if (asIndex == -1) {
      return formatter.wrapString(table);
    }

    final name = table.substring(0, asIndex).trim();
    final alias = table.substring(asIndex + 4).trim();
    return '${formatter.wrapString(name)} as ${formatter.wrapAsIdentifier(alias)}';
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

      // Handle pluck() columns
      if (stmt['type'] == 'pluck') {
        final pluckValue = stmt['value'];
        if (pluckValue != null) {
          cols.add(formatter.wrap(pluckValue.toString()));
        }
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
        // Check each column - could be string, QueryBuilder, or Raw
        for (final col in columns) {
          if (col is QueryBuilder) {
            cols.add(_compileSubquery(col));
          } else if (col is Raw) {
            final rawSql = col.toSQL();
            bindings.addAll(rawSql.bindings);
            cols.add(rawSql.sql);
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
        continue;
      }

      // Handle analytic / window functions (rank, denseRank, rowNumber)
      // JS Reference: querycompiler.js analytic(stmt) (line 1168)
      if (stmt['type'] == 'analytic') {
        cols.add(_compileAnalytic(stmt));
        continue;
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
      case 'whereJsonObject': // NEW (JSON)
        return _whereJsonObject(statement);
      case 'whereJsonPath': // NEW (JSON)
        return _whereJsonPath(statement);
      case 'whereJsonSupersetOf': // NEW (JSON)
        return _whereJsonSupersetOf(statement);
      case 'whereJsonSubsetOf': // NEW (JSON)
        return _whereJsonSubsetOf(statement);
      case 'whereFullText': // NEW (Full-text)
        return _whereFullText(statement);
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
    // Check for null value and delegate into whereNull
    if (statement['value'] == null) {
      return whereNull(statement);
    }

    return '${_not(statement, '') + formatter.wrap(statement['column'])} ${formatter.operator(statement['operator'])} ${_valueClause(statement)}';
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
      // Handle joinRaw
      if (stmt['type'] == 'joinRaw') {
        final value = stmt['value'];
        if (value is Raw) {
          final rawSql = value.toSQL();
          bindings.addAll(rawSql.bindings);
          sql.add(rawSql.sql);
        } else {
          sql.add(value.toString());
        }
        continue;
      }

      final joinType = stmt['join'] as String? ?? 'inner';
      final table = _wrapTableIdentifier(stmt['table'].toString());

      // Handle CROSS JOIN (no ON clause)
      if (joinType == 'cross') {
        sql.add('cross join $table');
        continue;
      }

      // Check for JoinClause (callback-based join with multiple conditions)
      if (stmt['joinClause'] != null) {
        final joinClause = stmt['joinClause'];
        final clauseSql = _compileJoinClauseSequence(joinClause);
        sql.add('$joinType join $table $clauseSql');
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
      final compiled = _compileJoinClause(cond);
      if (compiled.isEmpty) continue;

      if (isFirst) {
        parts.add(compiled);
        isFirst = false;
      } else {
        final bool = cond['bool']; // 'and' or 'or'
        parts.add('$bool $compiled');
      }
    }

    return parts.join(' ');
  }

  /// Compile join clause sequence including initial `on`/`using` keyword.
  String _compileJoinClauseSequence(dynamic joinClause) {
    final clauses = joinClause.clauses as List<Map<String, dynamic>>;
    if (clauses.isEmpty) return '';

    final sb = StringBuffer();
    for (var i = 0; i < clauses.length; i++) {
      final clause = clauses[i];
      final compiled = _compileJoinClause(clause);
      if (compiled.isEmpty) continue;

      if (i == 0) {
        sb.write(clause['type'] == 'onUsing' ? 'using ' : 'on ');
        sb.write(compiled);
      } else {
        sb.write(' ${clause['bool']} ');
        sb.write(compiled);
      }
    }

    return sb.toString();
  }

  String _compileJoinClause(Map<String, dynamic> clause) {
    final type = clause['type'] as String?;
    switch (type) {
      case 'onBasic':
        return _onBasic(clause);
      case 'onVal':
        return _onVal(clause);
      case 'onIn':
        return _onIn(clause);
      case 'onNull':
        return _onNull(clause);
      case 'onBetween':
        return _onBetween(clause);
      case 'onExists':
        return _onExists(clause);
      case 'onRaw':
        return _onRaw(clause);
      case 'onWrapped':
        return _onWrapped(clause);
      case 'onUsing':
        return _onUsing(clause);
      case 'onJsonPathEquals':
        return _onJsonPathEquals(clause);
      default:
        return '';
    }
  }

  String _onBasic(Map<String, dynamic> clause) {
    final first = formatter.wrap(clause['column']);
    final operator = clause['operator'];
    final second = formatter.wrap(clause['value']);
    return '$first $operator $second';
  }

  String _onVal(Map<String, dynamic> clause) {
    final first = formatter.wrap(clause['column']);
    final operator = clause['operator'];
    final second = client.parameter(clause['value'], bindings);
    return '$first $operator $second';
  }

  String _onIn(Map<String, dynamic> clause) {
    final columns = clause['column'];
    final values = clause['value'];

    if (columns is List) {
      final columnSql = formatter.columnize(columns);
      if (values is! List) {
        throw ArgumentError('Multi-column onIn requires List of tuples');
      }

      final rows = <String>[];
      for (final row in values) {
        if (row is! List) {
          throw ArgumentError('Multi-column onIn values must be List<List>');
        }
        final params = row.map((v) => client.parameter(v, bindings)).join(', ');
        rows.add('($params)');
      }
      return '($columnSql) ${_not(clause, 'in ')}(${rows.join(',')})';
    }

    final first = formatter.wrap(columns);

    String inValues;
    if (values is QueryBuilder) {
      inValues = _compileSubquery(values);
    } else if (values is Raw) {
      final sql = values.toSQL();
      bindings.addAll(sql.bindings);
      inValues = '(${sql.sql})';
    } else if (values is List) {
      final placeholders = values
          .map((v) => client.parameter(v, bindings))
          .join(', ');
      inValues = '($placeholders)';
    } else {
      final p = client.parameter(values, bindings);
      inValues = '($p)';
    }

    return '$first ${_not(clause, 'in ')}$inValues';
  }

  String _onNull(Map<String, dynamic> clause) {
    final first = formatter.wrap(clause['column']);
    return '$first is ${_not(clause, 'null')}';
  }

  String _onBetween(Map<String, dynamic> clause) {
    final first = formatter.wrap(clause['column']);
    final values = (clause['value'] as List).cast<dynamic>();
    final placeholders = values
        .map((v) => client.parameter(v, bindings))
        .join(' and ');
    return '$first ${_not(clause, 'between')} $placeholders';
  }

  String _onExists(Map<String, dynamic> clause) {
    final callback = clause['value'] as Function;
    final subBuilder = QueryBuilder(client);
    callback(subBuilder);
    final subSQL = subBuilder.toSQL();
    bindings.addAll(subSQL.bindings);
    return '${_not(clause, 'exists')} (${subSQL.sql})';
  }

  String _onRaw(Map<String, dynamic> clause) {
    final value = clause['value'];
    if (value is Raw) {
      final sql = value.toSQL();
      bindings.addAll(sql.bindings);
      return sql.sql;
    }
    return value.toString();
  }

  String _onWrapped(Map<String, dynamic> clause) {
    final callback = clause['value'] as Function;
    final nested = JoinClause('', 'inner');
    callback(nested);
    final sql = _compileJoinClauses(nested);
    if (sql.isEmpty) return '';
    return '($sql)';
  }

  String _onUsing(Map<String, dynamic> clause) {
    return '(${formatter.columnize(clause['column'])})';
  }

  String _onJsonPathEquals(Map<String, dynamic> clause) {
    String fn;
    final driver = client.driverName;
    if (driver == 'mysql' || driver == 'mysql2' || driver == 'sqlite3') {
      fn = 'json_extract';
    } else {
      fn = 'jsonb_path_query_first';
    }

    final firstCol = formatter.wrap(clause['columnFirst']);
    final secondCol = formatter.wrap(clause['columnSecond']);
    final firstPath = client.parameter(clause['jsonPathFirst'], bindings);
    final secondPath = client.parameter(clause['jsonPathSecond'], bindings);

    return '$fn($firstCol, $firstPath) = $fn($secondCol, $secondPath)';
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
      if (stmt['type'] == 'groupByRaw') {
        final value = stmt['value'];
        if (value is Raw) {
          final rawSql = value.toSQL();
          bindings.addAll(rawSql.bindings);
          columns.add(rawSql.sql);
        } else {
          columns.add(value.toString());
        }
      } else {
        columns.add(formatter.wrap(stmt['value']));
      }
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
      case 'havingRaw':
        return havingRaw(statement);
      case 'havingIn':
        return havingIn(statement);
      case 'havingBetween':
        return havingBetween(statement);
      case 'havingNull':
        return havingNull(statement);
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

  /// Compile raw HAVING clause
  ///
  /// For complex SQL expressions like count(*) > ?
  String havingRaw(Map<String, dynamic> statement) {
    final sql = statement['value'] as String;
    final rawBindings = (statement['bindings'] as List?) ?? [];

    // Convert ? placeholders to $N
    var result = sql;
    for (var binding in rawBindings) {
      result = result.replaceFirst('?', client.parameter(binding, bindings));
    }

    return result;
  }

  /// Compile HAVING IN clause
  ///
  /// Format: "column" [not] in (?, ?, ?)
  String havingIn(Map<String, dynamic> statement) {
    final column = formatter.wrap(statement['column']);
    final values = statement['value'] as List;
    final not = statement['not'] as bool? ?? false;

    final placeholders = values
        .map((v) => client.parameter(v, bindings))
        .join(', ');
    final modifier = not ? 'not in' : 'in';
    return '$column $modifier ($placeholders)';
  }

  /// Compile HAVING BETWEEN clause
  ///
  /// Format: "column" [not] between ? and ?
  String havingBetween(Map<String, dynamic> statement) {
    final column = formatter.wrap(statement['column']);
    final values = statement['value'] as List;
    final not = statement['not'] as bool? ?? false;

    final low = client.parameter(values[0], bindings);
    final high = client.parameter(values[1], bindings);
    final modifier = not ? 'not between' : 'between';
    return '$column $modifier $low and $high';
  }

  /// Compile HAVING NULL clause
  ///
  /// Format: "column" is [not] null
  String havingNull(Map<String, dynamic> statement) {
    final column = formatter.wrap(statement['column']);
    final not = statement['not'] as bool? ?? false;
    return not ? '$column is not null' : '$column is null';
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
      if (stmt['type'] == 'orderByRaw') {
        final value = stmt['value'];
        if (value is Raw) {
          final rawSql = value.toSQL();
          bindings.addAll(rawSql.bindings);
          sql.add(rawSql.sql);
        } else {
          sql.add(value.toString());
        }
        continue;
      }

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

  /// Compile lock clause
  ///
  /// JS Reference: querycompiler.js lock() + dialect-specific implementations.
  String _lock() {
    final lock = single['lock'] as String?;
    if (lock == null) return '';

    final mysqlLike =
        client.driverName == 'mysql' || client.driverName == 'mysql2';
    final postgresLike =
        client.driverName == 'pg' ||
        client.driverName == 'postgres' ||
        client.driverName == 'postgresql' ||
        client.driverName == 'cockroachdb' ||
        client.driverName == 'mock';

    switch (lock) {
      case 'forUpdate':
        return 'for update${_lockTablesClause(postgresLike)}';
      case 'forShare':
        if (mysqlLike) return 'lock in share mode';
        return 'for share${_lockTablesClause(postgresLike)}';
      case 'forNoKeyUpdate':
        if (!postgresLike) {
          throw StateError(
            '.forNoKeyUpdate() is currently only supported on PostgreSQL',
          );
        }
        return 'for no key update${_lockTablesClause(postgresLike)}';
      case 'forKeyShare':
        if (!postgresLike) {
          throw StateError(
            '.forKeyShare() is currently only supported on PostgreSQL',
          );
        }
        return 'for key share${_lockTablesClause(postgresLike)}';
      default:
        return '';
    }
  }

  /// Compile wait mode clause
  ///
  /// JS Reference: querycompiler.js waitMode() + dialect-specific implementations.
  String _waitMode() {
    final waitMode = single['waitMode'] as String?;
    if (waitMode == null) return '';

    switch (waitMode) {
      case 'skipLocked':
        return 'skip locked';
      case 'noWait':
        return 'nowait';
      default:
        return '';
    }
  }

  /// Optional lock table list for PostgreSQL-style locking.
  String _lockTablesClause(bool postgresLike) {
    if (!postgresLike) return '';

    final tables = single['lockTables'];
    if (tables is! List || tables.isEmpty) return '';

    final tableNames = tables
        .map((t) => _wrapTableIdentifier(t.toString()))
        .join(', ');
    return ' of $tableNames';
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

  /// Compile an analytic / window function column expression.
  ///
  /// Dart port of JS `querycompiler.js analytic(stmt)` (line 1168).
  ///
  /// Produces: `method() over ([partition by ...] order by [...]) [as alias]`
  ///
  /// [stmt] keys (all):
  ///   - `method`       — SQL function name: 'row_number', 'rank', 'dense_rank',
  ///                      'lead', 'lag', 'first_value', 'last_value', 'nth_value'
  ///   - `alias`        — optional alias string (NOT quoted, matching JS behaviour)
  ///   - `raw`          — optional [Raw] whose .sql replaces the entire OVER body
  ///   - `partitions`   — List of String or `{'column': String, 'order': String?}`
  ///   - `order`        — List of String or `{'column': String, 'order': String?}`
  ///   - `sourceColumn` — source column for value funcs (lead/lag/first_value/…)
  ///   - `offset`       — optional int offset for lead/lag
  ///   - `defaultVal`   — optional default value for lead/lag
  ///   - `nthN`         — required int n for nth_value
  ///   - `frameClause`  — optional pre-compiled frame string (e.g. 'rows between …')
  String _compileAnalytic(Map<String, dynamic> stmt) {
    final method = stmt['method'] as String;
    final alias = stmt['alias'] as String?;
    final raw = stmt['raw'];
    final sourceColumn = stmt['sourceColumn'] as String?;
    final offset = stmt['offset'];
    final defaultVal = stmt['defaultVal'];
    final nthN = stmt['nthN'];
    final frameClause = stmt['frameClause'] as String?;

    // Build the function call (with or without source column arguments).
    // defaultVal is added as a bound parameter (not interpolated) to prevent
    // SQL injection when the caller passes a string default value.
    String funcCall;
    if (sourceColumn != null) {
      final quotedCol = formatter.columnize([sourceColumn]);
      if (method == 'nth_value') {
        funcCall = '$method($quotedCol, $nthN)';
      } else if (method == 'lead' || method == 'lag') {
        if (offset != null && defaultVal != null) {
          final defaultPlaceholder = client.parameter(defaultVal, bindings);
          funcCall = '$method($quotedCol, $offset, $defaultPlaceholder)';
        } else if (offset != null) {
          funcCall = '$method($quotedCol, $offset)';
        } else {
          funcCall = '$method($quotedCol)';
        }
      } else {
        // first_value, last_value
        funcCall = '$method($quotedCol)';
      }
    } else {
      funcCall = '$method()';
    }

    var sql = '$funcCall over (';

    if (raw != null && raw is Raw) {
      // Raw OVER clause — JS resolves ?? identifiers via formatter
      final rawSQL = raw.toSQL();
      // Replace ?? with quoted column identifiers from bindings
      var resolved = rawSQL.sql;
      final rawBindings = rawSQL.bindings;
      for (final binding in rawBindings) {
        resolved = resolved.replaceFirst(
          '??',
          formatter.wrap(binding.toString()),
        );
      }
      sql += resolved;
    } else {
      final partitions = (stmt['partitions'] as List?) ?? [];
      final order = (stmt['order'] as List?) ?? [];

      if (partitions.isNotEmpty) {
        sql += 'partition by ';
        sql += partitions
            .map((p) {
              if (p is String) {
                return formatter.columnize([p]);
              } else if (p is Map) {
                final col = formatter.columnize([p['column'] as String]);
                final dir = p['order'] as String?;
                return dir != null ? '$col $dir' : col;
              }
              return p.toString();
            })
            .join(', ');
        sql += ' ';
      }

      sql += 'order by ';
      sql += order
          .map((o) {
            if (o is String) {
              return formatter.columnize([o]);
            } else if (o is Map) {
              final col = formatter.columnize([o['column'] as String]);
              final dir = o['order'] as String?;
              return dir != null ? '$col $dir' : col;
            }
            return o.toString();
          })
          .join(', ');

      if (frameClause != null && frameClause.isNotEmpty) {
        sql += ' $frameClause';
      }
    }

    sql += ')';

    if (alias != null && alias.isNotEmpty) {
      sql += ' as $alias';
    }

    return sql;
  }

  /// Compile WITH clauses (CTEs)
  ///
  /// JS Reference: querycompiler.js _with()
  String _with() {
    final withs = grouped['with'];
    if (withs == null || withs.isEmpty) return '';

    final ctes = <String>[];
    bool isRecursive = false;

    for (final stmt in withs) {
      final type = stmt['type'] as String;
      final alias = stmt['alias'] as String;
      final query = stmt['value'];

      // Check if any CTE is recursive
      if (type == 'withRecursive') {
        isRecursive = true;
      }

      String cteSql;

      if (query is QueryBuilder) {
        // Compile the CTE query
        final cteCompiler = client.queryCompiler(query);
        final cteQuery = cteCompiler.toSQL();
        cteSql = cteQuery.sql;

        // Merge bindings
        bindings.addAll(cteQuery.bindings);
      } else if (query is Raw) {
        final rawSQL = query.toSQL();
        cteSql = rawSQL.sql;
        bindings.addAll(rawSQL.bindings);
      } else {
        continue;
      }

      // Format: "alias" as (query)
      ctes.add('${formatter.wrap(alias)} as ($cteSql)');
    }

    if (ctes.isEmpty) return '';

    // with [recursive] cte1, cte2, ...
    final prefix = isRecursive ? 'with recursive' : 'with';
    return '$prefix ${ctes.join(', ')}';
  }

  /// Generate unique query ID
  ///
  /// Same pattern as Raw._generateUid()
  String _generateUid() {
    final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final random =
        (DateTime.now().microsecond * 1000 + DateTime.now().millisecond)
            .toRadixString(36);
    final uid = '$timestamp$random';
    return uid.substring(0, uid.length < 12 ? uid.length : 12);
  }

  /// Compile INSERT query
  ///
  /// JS Reference: querycompiler.js insert() (line 194)
  String _insertQuery() {
    final parts = <String>[];
    final onConflict = single['onConflict'] as Map<String, dynamic>?;

    // MySQL INSERT IGNORE is a prefix modifier — handle it at INSERT level
    final isIgnorePrefixDialect =
        client.driverName == 'mysql' || client.driverName == 'mysql2';
    final isIgnore = onConflict?['strategy'] == 'ignore';

    parts.add(_insert(ignorePrefix: isIgnorePrefixDialect && isIgnore));

    // ON CONFLICT / ON DUPLICATE KEY UPDATE (non-MySQL ignore is handled here)
    final conflictSql = _onConflict(onConflict);
    if (conflictSql.isNotEmpty) {
      parts.add(conflictSql);
    }

    final returning = _returning();
    if (returning.isNotEmpty) {
      parts.add(returning);
    }

    return parts.join(' ');
  }

  /// Compile INSERT statement
  ///
  /// JS Reference: querycompiler.js _insertBody() (line 222)
  String _insert({bool ignorePrefix = false}) {
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
    final keyword = ignorePrefix ? 'insert ignore into' : 'insert into';
    return '$keyword $table ($columnsSql) values ${valuesClauses.join(', ')}';
  }

  /// Compile ON CONFLICT / ON DUPLICATE KEY UPDATE / INSERT IGNORE clause.
  ///
  /// Postgres / SQLite syntax:
  ///   ON CONFLICT (col) DO NOTHING
  ///   ON CONFLICT (col) DO UPDATE SET col = EXCLUDED.col, ...
  ///
  /// MySQL syntax:
  ///   INSERT IGNORE INTO ...                (handled as prefix in _insert)
  ///   ... ON DUPLICATE KEY UPDATE col=VALUES(col), ...
  String _onConflict(Map<String, dynamic>? onConflict) {
    if (onConflict == null) return '';

    final strategy = onConflict['strategy'] as String;
    final column = onConflict['columns']; // String | List<String> | null

    final isMySQL =
        client.driverName == 'mysql' || client.driverName == 'mysql2';

    if (strategy == 'ignore') {
      if (isMySQL) {
        // MySQL: INSERT IGNORE is a prefix — nothing to add here
        return '';
      }
      // Postgres / SQLite
      final target = _conflictTarget(column);
      return 'on conflict$target do nothing';
    }

    if (strategy == 'merge') {
      final mergeColumns = onConflict['mergeColumns'];
      final insertValue = single['insert'];

      // Determine which columns to update
      final List<String> updateColumns;
      Map<String, dynamic>? rawUpdateValues;

      if (mergeColumns == null) {
        // No arg: update all inserted columns
        final rows = insertValue is List
            ? insertValue.cast<Map<String, dynamic>>()
            : [insertValue as Map<String, dynamic>];
        updateColumns = rows[0].keys.toList();
      } else if (mergeColumns is List) {
        updateColumns = List<String>.from(mergeColumns);
      } else if (mergeColumns is Map) {
        rawUpdateValues = Map<String, dynamic>.from(mergeColumns);
        updateColumns = [];
      } else {
        updateColumns = [];
      }

      if (isMySQL) {
        // MySQL: ON DUPLICATE KEY UPDATE col=VALUES(col), ...
        final setClauses = <String>[];
        if (rawUpdateValues != null) {
          rawUpdateValues.forEach((col, val) {
            final wrappedCol = formatter.wrap(col);
            setClauses.add('$wrappedCol = ${client.parameter(val, bindings)}');
          });
        } else {
          for (final col in updateColumns) {
            final wrappedCol = formatter.wrap(col);
            setClauses.add('$wrappedCol = VALUES($wrappedCol)');
          }
        }
        return 'on duplicate key update ${setClauses.join(', ')}';
      } else {
        // Postgres / SQLite: ON CONFLICT (col) DO UPDATE SET col = EXCLUDED.col, ...
        final target = _conflictTarget(column);
        final setClauses = <String>[];
        if (rawUpdateValues != null) {
          rawUpdateValues.forEach((col, val) {
            final wrappedCol = formatter.wrap(col);
            setClauses.add('$wrappedCol = ${client.parameter(val, bindings)}');
          });
        } else {
          for (final col in updateColumns) {
            final wrappedCol = formatter.wrap(col);
            setClauses.add('$wrappedCol = excluded.$wrappedCol');
          }
        }
        return 'on conflict$target do update set ${setClauses.join(', ')}';
      }
    }

    return '';
  }

  /// Build the conflict target string: ` (col1, col2)` or empty string.
  String _conflictTarget(dynamic column) {
    if (column == null) return '';
    if (column is String) return ' (${formatter.wrap(column)})';
    if (column is List && column.isNotEmpty) {
      return ' (${column.map((c) => formatter.wrap(c as String)).join(', ')})';
    }
    return '';
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

  /// Compile TRUNCATE TABLE statement
  ///
  /// Postgres appends `restart identity`, matching Knex.js behavior.
  String _truncateQuery() {
    final table = tableName;
    final driver = client.driverName;
    if (driver == 'pg' || driver == 'postgres' || driver == 'postgresql') {
      return 'truncate $table restart identity';
    }
    return 'truncate $table';
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

  // ─────────────────────────────────────────────────────────────────────────────
  // JSON OPERATORS (PG, MySQL, SQLite)
  // ─────────────────────────────────────────────────────────────────────────────

  String _whereJsonObject(Map<String, dynamic> statement) {
    return '${_not(statement, '') + formatter.wrap(statement['column'])} = ${_valueClause(statement)}';
  }

  String _whereJsonPath(Map<String, dynamic> statement) {
    if (client.driverName == 'pg') {
      final col = formatter.wrap(statement['column']);
      final path = client.parameter(statement['jsonPath'], bindings);
      final op = formatter.operator(statement['operator']);

      final valStr = statement['value'].toString();
      String castValue = " #>> '{}'";
      if (int.tryParse(valStr) != null) {
        castValue = '::int';
      } else if (double.tryParse(valStr) != null) {
        castValue = '::float';
      }

      final valClause = _valueClause(statement);
      return '${_not(statement, '')}jsonb_path_query_first($col, $path)$castValue $op $valClause';
    } else if (client.driverName == 'mysql' || client.driverName == 'sqlite') {
      final col = formatter.wrap(statement['column']);
      final path = client.parameter(statement['jsonPath'], bindings);
      final op = formatter.operator(statement['operator']);
      final valClause = _valueClause(statement);
      return '${_not(statement, '')}json_extract($col, $path) $op $valClause';
    }
    // Fallback if not supported
    return whereBasic(statement);
  }

  String _whereJsonSupersetOf(Map<String, dynamic> statement) {
    if (client.driverName == 'pg') {
      return '${_not(statement, '') +
          formatter.wrap(statement['column'])} @> ${_valueClause(statement)}';
    }
    statement['operator'] = '=';
    return whereBasic(statement); // Unsupported on other dialects right now
  }

  String _whereJsonSubsetOf(Map<String, dynamic> statement) {
    if (client.driverName == 'pg') {
      return '${_not(statement, '') +
          formatter.wrap(statement['column'])} <@ ${_valueClause(statement)}';
    }
    statement['operator'] = '=';
    return whereBasic(statement); // Unsupported on other dialects right now
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // FULL-TEXT SEARCH
  // ─────────────────────────────────────────────────────────────────────────────

  String _whereFullText(Map<String, dynamic> statement) {
    final columns = statement['columns']; // String or List
    final List<String> colList = columns is List
        ? List<String>.from(columns.map((e) => e.toString()))
        : [columns.toString()];
    final query = statement['query'] as String;
    final options = statement['options'] as Map<String, dynamic>?;

    final driver = client.driverName;

    if (driver == 'pg') {
      // PG: to_tsvector([config,] col) @@ to_tsquery([config,] query)
      // Multiple columns: to_tsvector(col1) || to_tsvector(col2) @@ ...
      final lang = options?['language'] as String?;
      final langArg = lang != null ? "'$lang', " : "";

      final vectors = colList
          .map((c) {
            final wrapped = formatter.wrap(c);
            return "to_tsvector($langArg$wrapped)";
          })
          .join(" || ");

      final queryParam = client.parameter(query, bindings);
      final boolOp = _not(statement, '');
      return '$boolOp($vectors) @@ to_tsquery($langArg$queryParam)';
    }

    if (driver == 'mysql' || driver == 'mysql2') {
      // MySQL: MATCH(col1, col2) AGAINST(query [mode])
      final wrappedCols = colList.map((c) => formatter.wrap(c)).join(', ');
      final queryParam = client.parameter(query, bindings);
      final mode = options?['mode'] as String?;
      final modeArg = mode != null ? ' $mode' : '';
      final boolOp = _not(statement, '');
      return '${boolOp}MATCH($wrappedCols) AGAINST($queryParam$modeArg)';
    }

    if (driver == 'sqlite' || driver == 'sqlite3') {
      // SQLite: col MATCH query (assuming FTS virtual table, usually searching on table name or specific col)
      // If multiple columns, just pick the first or usually the table name is used.  SQLite FTS:  `table MATCH '...'`
      final col = formatter.wrap(colList.first);
      final queryParam = client.parameter(query, bindings);
      final boolOp = _not(statement, '');
      return '$boolOp$col MATCH $queryParam';
    }

    // Fallback if fulltext is unsupported for dialect
    return whereBasic({
      ...statement,
      'operator': 'like',
      'value': '%$query%',
      'column': colList.first,
    });
  }
}
