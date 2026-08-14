import 'package:knex_dart_capabilities/knex_dart_capabilities.dart';

import '../client/client.dart';
import '../formatter/formatter.dart';
import '../util/enums.dart';
import '../raw.dart';
import 'query_builder.dart';
import 'join_clause.dart';
import 'sql_string.dart';

/// Query compiler that transforms QueryBuilder statements into SQL
///
/// Core responsibilities:
/// - Group statements by type (columns, where, join, etc.)
/// - Compile statements into dialect-specific SQL
/// - Manage bindings for parameterized queries
/// - Generate unique query IDs
class QueryCompiler {
  static int _uidCounter = 0;

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

  QueryCompiler(this.client, this.builder) {
    // Get method from builder
    method = builder.method.name;

    // Get single values (table, etc.)
    single = Map<String, dynamic>.from(builder.single);

    // Group statements by type
    grouped = _groupStatements(builder.statements);

    // Create formatter
    formatter = client.formatter(builder);
  }

  bool _supports(SqlCapability capability) {
    final dialect = dialectFromDriverName(client.driverName);
    // Unknown drivers are treated as unknown capability to avoid false
    // negatives; runtime guards only fail when we are certain.
    if (dialect == null) return true;
    return supportsCapability(dialect, capability);
  }

  /// Group statements by their grouping or type
  ///
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

  /// Returns a normalized pluck column name.
  String? _pluckColumnName() {
    final rawPluck = single['pluck'];
    if (rawPluck == null) return null;

    var value = rawPluck.toString();
    if (value.contains('.')) {
      value = value.split('.').last;
    }
    return value;
  }

  /// Shift positional `$N` placeholders in an already-compiled sub-fragment so
  /// they continue after the parent query's existing bindings.
  ///
  /// Performed as a **single** regex pass. Iterated `replaceAll('$1', …)` is
  /// unsafe: `$1` also matches inside `$10`/`$11`, including tokens the
  /// substitution just produced — e.g. with offset 9 a two-binding subquery
  /// rewrote `$2`→`$11`, then `$1`→`$10` also hit the `$1` inside `$11`,
  /// yielding `$101`. Dialects using `?` placeholders are unaffected (no match).
  String _offsetPlaceholders(String sql, int offset) =>
      client.offsetPlaceholders(sql, offset);

  /// Compile a [Raw] fragment for inline embedding into the query under
  /// construction: offsets any `$N` placeholders in its SQL against the
  /// bindings already accumulated, then appends its own bindings.
  ///
  /// This is the single path every Raw-embedding call site in this compiler
  /// must go through — inlining `raw.toSQL().sql` directly and appending
  /// `raw.toSQL().bindings` without offsetting silently corrupts `$N`
  /// numbering (collisions/gaps) the moment the Raw carries its own `?`
  /// bindings and isn't first in the query.
  String _inlineRaw(Raw raw) {
    final bindingOffset = bindings.length;
    final sql = raw.toSQL();
    final offsetSql = _offsetPlaceholders(sql.sql, bindingOffset);
    bindings.addAll(sql.bindings);
    return offsetSql;
  }

  /// Compile a subquery (QueryBuilder) to SQL with parameter renumbering
  String _compileSubquery(QueryBuilder subquery, {bool withParens = true}) {
    final bindingOffset = bindings.length;
    final subCompiler = client.queryCompiler(subquery);
    var sql = subCompiler.toSQL().sql;

    // Renumber parameters
    sql = _offsetPlaceholders(sql, bindingOffset);

    bindings.addAll(subCompiler.bindings);

    // Add parentheses if needed
    if (withParens) {
      sql = '($sql)';
    }

    // Add alias AFTER parentheses. Use the dialect-aware identifier wrapper
    // (backticks for MySQL/SQLite, brackets for MSSQL, double quotes for
    // Postgres) rather than a hardcoded double quote — a bare `"alias"` is
    // invalid MySQL/MSSQL identifier syntax outside ANSI_QUOTES mode.
    if (subquery.alias != null) {
      sql = '$sql as ${formatter.wrapAsIdentifier(subquery.alias!)}';
    }

    return sql;
  }

  /// Compile a `{ alias: column }` select entry to `<column> as "<alias>"`.
  ///
  /// [value] may be a plain column name (String), a [Raw] fragment, or a
  /// [QueryBuilder] subquery — matching knex.js's object-notation column
  /// aliasing (`select({alias: column})`).
  String _aliasedColumn(String alias, dynamic value) {
    final wrappedAlias = client.wrapIdentifier(alias);
    if (value is QueryBuilder) {
      final sql = _compileSubquery(value);
      return '$sql as $wrappedAlias';
    }
    if (value is Raw) {
      return '${_inlineRaw(value)} as $wrappedAlias';
    }
    return '${formatter.wrap(value.toString())} as $wrappedAlias';
  }

  /// Compile a LATERAL join subquery to `(sql)` — no alias appended.
  ///
  /// Handles [QueryBuilder] (with parameter index renumbering for
  /// positional placeholders like `$1`) and [Raw].
  String _compileLateralQuery(dynamic query) {
    if (query is QueryBuilder) {
      final bindingOffset = bindings.length;
      final subCompiler = client.queryCompiler(query);
      var subSql = subCompiler.toSQL().sql;
      subSql = _offsetPlaceholders(subSql, bindingOffset);
      bindings.addAll(subCompiler.bindings);
      return '($subSql)';
    }
    if (query is Raw) {
      return '(${_inlineRaw(query)})';
    }
    return '($query)';
  }

  /// Dispatch to method-specific compiler
  ///
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
      // knex.js's `union([...], wrap=true)` (and unionAll/intersect/except
      // equivalents) wraps the BASE select too — not just each unioned leg.
      // When the wrap flag is set on ANY union leg, knex.js parenthesizes
      // each leg INCLUDING the base; knex-dart was parenthesizing only the
      // additional legs, dropping the parens around the base. Verified
      // against real knex.js 3.3.0 for the `union/wrapped-array` parity
      // case — see the allowlist/failure history for this batch.
      final unions = grouped['union'];
      final wrapBase = unions is List &&
          (unions as List).any((u) => (u['wrap'] as bool? ?? false));
      if (wrapBase) {
        final baseSql = parts.join(' ');
        parts
          ..clear()
          ..add('($baseSql)');
      }
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
      return _tableNameCache = _inlineRaw(table);
    }

    // Simple string table name
    if (table is String) {
      return _tableNameCache = _wrapTableIdentifier(table);
    }

    return _tableNameCache = table.toString();
  }

  /// Wrap table identifier with JS-like lowercase `as` for aliases.
  ///
  /// This keeps table-alias SQL stable while leaving
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
        // Check each column - could be string, QueryBuilder, Raw, or a
        // { alias: column } aliasing Map
        for (final col in columns) {
          if (col is QueryBuilder) {
            cols.add(_compileSubquery(col));
          } else if (col is Raw) {
            cols.add(_inlineRaw(col));
          } else if (col is Map) {
            col.forEach((alias, value) {
              cols.add(_aliasedColumn(alias.toString(), value));
            });
          } else {
            // Regular column — pass the raw value (not `.toString()`-ed) so
            // `formatter.wrap()` can dispatch on its actual type: a numeric
            // literal (e.g. `select(0)`) must compile to a bare `0`, not a
            // quoted identifier `"0"` (matches knex.js's `wrap()`, which
            // returns `typeof value === 'number'` values as-is).
            cols.add(formatter.wrap(col).toString());
          }
        }
        continue;
      }

      // { alias: column, ... } passed directly to select() (not wrapped in a
      // List) — same aliasing notation, applied to every entry.
      if (columns != null && columns is Map && columns.isNotEmpty) {
        columns.forEach((alias, value) {
          cols.add(_aliasedColumn(alias.toString(), value));
        });
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
        cols.add(_inlineRaw(rawValue));
        continue;
      }

      // Handle analytic / window functions (rank, denseRank, rowNumber)
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
  String _not(Map<String, dynamic> statement, String str) {
    final not = statement['not'] as bool? ?? false;
    if (not) return 'not $str';
    return str;
  }

  /// Compile WHERE NULL clause
  ///
  ///
  /// Generates "column" is null or "column" is not null
  String whereNull(Map<String, dynamic> statement) {
    final column = formatter.wrap(statement['column']);
    return '$column is ${_not(statement, 'null')}';
  }

  /// Compile WHERE IN clause
  ///
  ///
  /// Supports:
  /// - Array of values: "column" in (?, ?, ?)
  /// - Subquery: "column" in (SELECT ...)
  /// - Raw: "column" in (`<raw sql>`) — e.g. `whereIn('id', raw('select (:test)', {...}))`
  String whereIn(Map<String, dynamic> statement) {
    final column = formatter.wrap(statement['column']);
    final values = statement['value'];

    String valueClause;
    if (values is QueryBuilder) {
      // Subquery
      valueClause = _compileSubquery(values);
    } else if (values is Raw) {
      // Raw expression (e.g. a raw subquery) — previously fell through to
      // `values as List`, which threw a TypeError instead of compiling;
      // knex.js supports this directly (`whereIn('id', raw('select (:test)',
      // {test: [1,2,3]}))` → `"id" in (select (?))`).
      valueClause = '(${_inlineRaw(values)})';
    } else if (values is Function) {
      final subBuilder = QueryBuilder(client);
      values(subBuilder);
      valueClause = _compileSubquery(subBuilder);
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
  ///
  /// Compiles a Raw SQL condition. `.whereNot(raw(...))` prefixes with `not `
  /// (matches knex.js: `where not is_active`), mirroring the `_not()` prefix
  /// convention used by every other WHERE compiler above.
  String whereRaw(Map<String, dynamic> statement) {
    final raw = statement['value'] as Raw;
    return '${_not(statement, '')}${_inlineRaw(raw)}';
  }

  /// Compile WHERE BETWEEN clause
  ///
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
  ///
  /// Examples:
  /// - exists (SELECT ...)
  /// - not exists (SELECT ...)
  String whereExists(Map<String, dynamic> statement) {
    final callback = statement['value'] as QueryBuilderCallback;

    // Create a new QueryBuilder for the subquery
    final subBuilder = QueryBuilder(client);
    callback(subBuilder);

    // Get the SQL for the subquery, renumbering $N placeholders to continue
    // from the parent's running binding count (mirrors _compileSubquery()).
    final bindingOffset = bindings.length;
    final subSQL = subBuilder.toSQL();
    final sql = _offsetPlaceholders(subSQL.sql, bindingOffset);
    bindings.addAll(subSQL.bindings);

    return '${_not(statement, 'exists ')}($sql)';
  }

  /// Compile WHERE WRAPPED clause (grouped conditions)
  ///
  ///
  /// Groups WHERE conditions in parentheses
  ///
  /// Example:
  /// - (age > 18 OR verified = true)
  String whereWrapped(Map<String, dynamic> statement) {
    final callback = statement['value'] as QueryBuilderCallback;

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
    whereSQL = _offsetPlaceholders(whereSQL, bindingOffset);

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
          sql.add(_inlineRaw(value));
        } else {
          sql.add(value.toString());
        }
        continue;
      }

      // Handle JOIN LATERAL / LEFT JOIN LATERAL / CROSS JOIN LATERAL
      if (stmt['type'] == 'joinLateral') {
        if (!_supports(SqlCapability.lateralJoin)) {
          throw StateError(
            'LATERAL JOIN is not supported by ${client.driverName}',
          );
        }
        final joinType = stmt['joinType'] as String;
        final alias = client.wrapIdentifier(stmt['alias'] as String);
        final subSql = _compileLateralQuery(stmt['query']);
        if (joinType == 'cross') {
          sql.add('cross join lateral $subSql as $alias');
        } else {
          sql.add('$joinType join lateral $subSql as $alias on true');
        }
        continue;
      }

      final joinType = stmt['join'] as String? ?? 'inner';
      if (joinType == 'full outer' && !_supports(SqlCapability.fullOuterJoin)) {
        throw StateError(
          'FULL OUTER JOIN is not supported by ${client.driverName}',
        );
      }
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
    final value = clause['value'];
    // Raw value: knex.js treats `on('a', '=', raw('?',[v]))` as a raw SQL
    // fragment on the right of the operator — `on "a" = ?` with `v` as
    // binding — NOT as an identifier reference. Without this dispatch,
    // `formatter.wrap` quoted the raw's `?` as a string literal,
    // producing `on "a" = "?"` instead of `on "a" = ?`.
    final second = value is Raw ? _inlineRaw(value) : formatter.wrap(value);
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
      inValues = '(${_inlineRaw(values)})';
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
    final bindingOffset = bindings.length;
    final subSQL = subBuilder.toSQL();
    final sql = _offsetPlaceholders(subSQL.sql, bindingOffset);
    bindings.addAll(subSQL.bindings);
    return '${_not(clause, 'exists')} ($sql)';
  }

  String _onRaw(Map<String, dynamic> clause) {
    final value = clause['value'];
    if (value is Raw) {
      return _inlineRaw(value);
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
          columns.add(_inlineRaw(value));
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
      case 'havingExists':
        return havingExists(statement);
      case 'havingWrapped':
        return havingWrapped(statement);
      default:
        throw Exception('Unknown HAVING type: $type');
    }
  }

  /// Compile basic HAVING clause
  ///
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

  /// Compile HAVING EXISTS clause
  ///
  ///
  /// Examples:
  /// - having exists (SELECT ...)
  /// - having not exists (SELECT ...)
  String havingExists(Map<String, dynamic> statement) {
    final callback = statement['value'] as QueryBuilderCallback;

    // Create a new QueryBuilder for the subquery
    final subBuilder = QueryBuilder(client);
    callback(subBuilder);

    // Get the SQL for the subquery, renumbering $N placeholders to continue
    // from the parent's running binding count (mirrors _compileSubquery()).
    final bindingOffset = bindings.length;
    final subSQL = subBuilder.toSQL();
    final sql = _offsetPlaceholders(subSQL.sql, bindingOffset);
    bindings.addAll(subSQL.bindings);

    return '${_not(statement, 'exists ')}($sql)';
  }

  /// Compile grouped HAVING conditions (parentheses)
  ///
  ///
  /// Mirrors [whereWrapped]: builds the nested HAVING clauses on a fresh
  /// sub-builder, renumbers `$N` placeholders to continue from the parent's
  /// binding count, and strips the leading `having ` prefix.
  String havingWrapped(Map<String, dynamic> statement) {
    final callback = statement['value'] as QueryBuilderCallback;

    // Create a new QueryBuilder for the wrapped conditions
    final subBuilder = QueryBuilder(client);
    callback(subBuilder);

    // Get the current binding count before adding subquery bindings
    final bindingOffset = bindings.length;

    // Compile the HAVING clauses from the sub-builder
    final subCompiler = client.queryCompiler(subBuilder);
    var havingSQL = subCompiler._having();

    if (havingSQL.isEmpty) return '';

    // Renumber parameter placeholders to continue from parent's count
    havingSQL = _offsetPlaceholders(havingSQL, bindingOffset);

    // Merge bindings from subquery into parent bindings
    bindings.addAll(subCompiler.bindings);

    // Remove the leading "having " (7 characters)
    final condition = havingSQL.substring(7);

    // Apply NOT if needed
    final notStr = (statement['not'] as bool? ?? false) ? 'not ' : '';

    return '$notStr($condition)';
  }

  /// Compile ORDER BY clause
  ///
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
          sql.add(_inlineRaw(value));
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
  ///
  /// LIMIT value is parameterized (added to bindings)
  String _limit() {
    final limit = single['limit'];
    if (limit == null) return '';

    if (client.driverName == 'mssql') {
      final offset = single['offset'];
      if (offset == null) {
        return 'OFFSET 0 ROWS FETCH NEXT ${client.parameter(limit, bindings)} ROWS ONLY';
      }
      return '';
    }

    // Add limit value to bindings and get placeholder
    return 'limit ${client.parameter(limit, bindings)}';
  }

  /// Compile OFFSET clause
  ///
  ///
  /// OFFSET value is parameterized (added to bindings)
  String _offset() {
    final offset = single['offset'];
    if (offset == null) return '';

    if (client.driverName == 'mssql') {
      final limit = single['limit'];
      if (limit == null) {
        return 'OFFSET ${client.parameter(offset, bindings)} ROWS';
      }
      return 'OFFSET ${client.parameter(offset, bindings)} ROWS FETCH NEXT ${client.parameter(limit, bindings)} ROWS ONLY';
    }

    // Add offset value to bindings and get placeholder
    return 'offset ${client.parameter(offset, bindings)}';
  }

  /// Compile lock clause
  ///
  String _lock() {
    final lock = single['lock'] as String?;
    if (lock == null) return '';

    // Use the family-aware helper so mariadb (and any future mysql-family
    // driver name) is dispatched correctly here too — same fix as the JSON
    // where family.
    final mysqlLike = _isMySqlLikeDriver;
    final postgresLike = _isPostgresLikeDriver;

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
  String _union() {
    final unions = grouped['union'];
    if (unions == null || unions.isEmpty) return '';

    final parts = <String>[];

    for (final stmt in unions) {
      final type = stmt['type'] as String; // 'union' or 'union all'
      var query = stmt['value'];
      final wrap = stmt['wrap'] as bool? ?? false;

      String sql;

      // Callback form (`.union([(qb) => qb.select(...), ...])`) — matches
      // knex.js's array-of-callbacks union shape. Without this, a Function
      // entry silently fell through to the `else { continue; }` branch below
      // and the whole UNION branch vanished from the SQL with no error.
      if (query is Function) {
        final subBuilder = QueryBuilder(client);
        query(subBuilder);
        query = subBuilder;
      }

      if (query is QueryBuilder) {
        // Get current binding count BEFORE compiling unioned query
        final bindingOffset = bindings.length;

        // Compile the query
        final queryCompiler = client.queryCompiler(query);
        final querySQL = queryCompiler.toSQL();
        sql = querySQL.sql;

        // Renumber parameters to continue from parent's count
        sql = _offsetPlaceholders(sql, bindingOffset);

        // Merge bindings
        bindings.addAll(queryCompiler.bindings);
      } else if (query is Raw) {
        sql = _inlineRaw(query);
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
  ///
  /// Produces: `method() over ([partition by ...] order by [...]) [as alias]`
  ///
  /// [stmt] keys (all):
  ///   - `method`       — SQL function name: 'row_number', 'rank', 'dense_rank',
  ///                      'lead', 'lag', 'first_value', 'last_value', 'nth_value'
  ///   - `alias`        — optional alias string (identifier-wrapped, matching
  ///                      knex.js 3.2.10+'s analytic-function alias escaping)
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
      // If caller passes only an order expression (e.g. `"score" desc`),
      // normalize it to `order by ...` inside OVER(...).
      var overClause = _inlineRaw(raw).trim();
      if (overClause.isNotEmpty && !_isCompleteAnalyticOverClause(overClause)) {
        overClause = 'order by $overClause';
      }
      sql += overClause;
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
      sql += ' as ${formatter.wrap(alias)}';
    }

    return sql;
  }

  bool _isCompleteAnalyticOverClause(String clause) {
    final trimmed = clause.trim();
    final lower = trimmed.toLowerCase();

    if (lower.startsWith('partition by ')) return true;
    if (lower.startsWith('order by ')) return true;
    if (lower.startsWith('rows ')) return true;
    if (lower.startsWith('range ')) return true;
    if (lower.startsWith('groups ')) return true;
    if (lower.startsWith('exclude ')) return true;

    // Window name reference: OVER(window_name)
    if (RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(trimmed)) return true;
    if (RegExp(r'^"[^"]+"$').hasMatch(trimmed)) return true;
    if (RegExp(r'^\[[^\]]+\]$').hasMatch(trimmed)) return true;

    return false;
  }

  /// Compile WITH clauses (CTEs)
  ///
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
        // Capture the binding count BEFORE compiling so positional ($N)
        // placeholders in this CTE can be renumbered to continue from the
        // parent's running total (mirrors _union()). Without this, a second
        // bound CTE restarts at $1 and collides with the first.
        final bindingOffset = bindings.length;

        final cteCompiler = client.queryCompiler(query);
        final cteQuery = cteCompiler.toSQL();
        cteSql = cteQuery.sql;

        cteSql = _offsetPlaceholders(cteSql, bindingOffset);

        // Merge bindings
        bindings.addAll(cteQuery.bindings);

        // If the CTE body itself carries an alias (`.with('x', builder.as('y'))`
        // or a nested `.with()` whose inner query used `.as()`), knex.js wraps
        // the body in its own parens + alias *inside* the outer `"x" as (...)`
        // wrapper: `"x" as ((select ...) as "y")`. Mirror that here — without
        // it the alias was silently dropped.
        if (query.alias != null) {
          cteSql = '($cteSql) as ${formatter.wrapAsIdentifier(query.alias!)}';
        }
      } else if (query is Raw) {
        cteSql = _inlineRaw(query);
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

  /// Generate unique query ID.
  String _generateUid() {
    const maxJsSafeInt = 0x1FFFFFFFFFFFFF;
    _uidCounter = (_uidCounter + 1) & maxJsSafeInt;
    return 'q${_uidCounter.toRadixString(16).padLeft(14, '0')}';
  }

  /// Compile INSERT query
  ///
  String _insertQuery() {
    // An empty INSERT (e.g. `insert([])`, or `insert([{}, {}])` — multiple
    // all-empty rows) is a no-op in knex.js: compiles to nothing at all,
    // dropping WITH/ON CONFLICT/RETURNING too, not just the insert clause
    // itself. Checked up front, before any binding-generating compilation,
    // so it can't touch `bindings` (which would desync placeholder numbers
    // in the non-empty path below, since WITH must be compiled — and its
    // bindings recorded — before INSERT's).
    if (_isEmptyInsert()) return '';

    final parts = <String>[];
    final onConflict = single['onConflict'] as Map<String, dynamic>?;

    // WITH (CTE) clauses must precede INSERT — mirrors _updateQuery() /
    // _deleteQuery(), which both already do this. Without it, a `.with(...)`
    // preceding `.insert(...)` was silently dropped from the compiled SQL.
    final withSql = _with();
    if (withSql.isNotEmpty) {
      parts.add(withSql);
    }

    // MySQL INSERT IGNORE is a prefix modifier — handle it at INSERT level
    final isIgnorePrefixDialect = _isMySqlLikeDriver;
    final isIgnore = onConflict?['strategy'] == 'ignore';

    parts.add(_insert(ignorePrefix: isIgnorePrefixDialect && isIgnore));

    // ON CONFLICT / ON DUPLICATE KEY UPDATE (non-MySQL ignore is handled here)
    final conflictSql = _onConflict(onConflict);
    if (conflictSql.isNotEmpty) {
      parts.add(conflictSql);

      // Postgres/SQLite support a WHERE predicate guard on the DO UPDATE clause
      // (`... do update set ... where <cond>`). MySQL's ON DUPLICATE KEY UPDATE
      // has no such clause — silently dropping the guard would change write
      // semantics, so surface it as an error instead (matches knex.js).
      if (onConflict?['strategy'] == 'merge') {
        final whereStmts = grouped['where'];
        final hasWhere = whereStmts != null && whereStmts.isNotEmpty;
        if (hasWhere) {
          if (_isMySqlLikeDriver) {
            throw StateError(
              '.onConflict().merge().where() is not supported for mysql',
            );
          }
          final where = _where();
          if (where.isNotEmpty) {
            parts.add(where);
          }
        }
      }
    }

    final returning = _returning();
    if (returning.isNotEmpty) {
      parts.add(returning);
    }

    return parts.join(' ');
  }

  /// Whether `.insert(...)` compiles to nothing at all (a no-op), mirroring
  /// [_insert]'s empty-array/all-empty-rows handling without generating any
  /// SQL or touching `bindings` — see [_insertQuery] for why that matters.
  bool _isEmptyInsert() {
    final insertValue = single['insert'];
    if (insertValue == null) return true;
    if (insertValue is List) {
      if (insertValue.isEmpty) return true;
      if (insertValue.length > 1) {
        return insertValue.every((row) => (row as Map).isEmpty);
      }
    }
    return false;
  }

  /// Compile INSERT statement
  ///
  String _insert({bool ignorePrefix = false}) {
    final insertValue = single['insert'];
    if (insertValue == null) return '';

    final table = formatter.wrap(single['table']);
    final keyword = ignorePrefix ? 'insert ignore into' : 'insert into';
    // Mirrors knex.js's per-dialect `_emptyInsertValue`: MySQL requires an
    // explicit empty column/value list, everyone else accepts DEFAULT VALUES.
    final emptyInsertValue =
        _isMySqlLikeDriver ? '() values ()' : 'default values';

    // Normalize to list of maps. Rows may arrive as `Map<dynamic, dynamic>`
    // (e.g. a bare `{}` literal inside a `List` in Dart infers that type, not
    // `Map<String, dynamic>`), so convert element-by-element rather than a
    // blind `List.cast()`, which defers the type check to iteration time and
    // throws deep inside the values-building loop below instead of here.
    final List<Map<String, dynamic>> rows;
    if (insertValue is List) {
      if (insertValue.isEmpty) {
        // knex.js treats `insert([])` as a no-op — compiles to nothing.
        return '';
      }
      rows = insertValue
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
    } else if (insertValue is Map) {
      if (insertValue.isEmpty) {
        return '$keyword $table $emptyInsertValue';
      }
      rows = [Map<String, dynamic>.from(insertValue)];
    } else {
      throw ArgumentError('INSERT values must be Map or List<Map>');
    }

    // Column set is the union of keys across all rows (first-seen order),
    // matching knex.js. A row missing a column emits the SQL `default` keyword
    // for that position rather than silently shifting or dropping values.
    final columns = <String>[];
    final seen = <String>{};
    for (final row in rows) {
      for (final key in row.keys) {
        if (seen.add(key)) columns.add(key);
      }
    }
    // knex.js's `_prepInsert` sorts the column list alphabetically
    // (`Object.keys(data[i]).sort()`), not first-seen-order — the row-value
    // loop below already looks values up by column name (order-independent
    // per row), so sorting here is a pure ordering fix with no semantic
    // change to which value lands in which column.
    columns.sort();

    if (columns.isEmpty) {
      // Every row was an empty map (e.g. `insert([{}])`). A single all-empty
      // row inserts default values for the whole row; more than one is
      // ambiguous — DEFAULT VALUES can't be repeated per-row — so knex.js
      // drops it as a no-op, same as `insert([])`.
      if (rows.length == 1) {
        return '$keyword $table $emptyInsertValue';
      }
      return '';
    }

    final columnsSql = columns.map((c) => formatter.wrap(c)).join(', ');

    // SQLite (and its family: turso, d1) rejects the DEFAULT keyword inside a
    // VALUES list, so a ragged multi-row insert cannot be expressed there by
    // default. knex.js has the same restriction unless the caller opts in via
    // its `useNullAsDefault` config flag (in which case it also switches the
    // whole multi-row shape to a `select ... union all select ...` form — a
    // legacy compatibility shim for SQLite versions predating multi-row
    // VALUES support, <3.7.11/2012, which knex-dart intentionally doesn't
    // replicate; see the `cte/insert-multi-source::sqlite` parity allowlist
    // entry). knex-dart honors the same flag (`KnexConfig.useNullAsDefault`)
    // more simply: a missing cell just binds `null` in the existing native
    // VALUES syntax, which every SQLite version knex-dart targets accepts
    // directly — no shim needed.
    const sqliteFamily = {'sqlite', 'sqlite3', 'turso', 'd1'};
    final isSqliteFamily = sqliteFamily.contains(client.driverName);
    final useNullAsDefault = client.config.useNullAsDefault;

    // Build VALUES clauses
    final valuesClauses = <String>[];
    for (final row in rows) {
      final rowBindings = <String>[];
      for (final col in columns) {
        if (row.containsKey(col)) {
          rowBindings.add(client.parameter(row[col], bindings));
        } else if (useNullAsDefault) {
          rowBindings.add(client.parameter(null, bindings));
        } else {
          if (isSqliteFamily) {
            throw StateError(
              'SQLite does not support DEFAULT in a multi-row INSERT with '
              'differing columns. Give every row the same columns, split '
              'into separate inserts, or set KnexConfig.useNullAsDefault.',
            );
          }
          // Missing cell → SQL DEFAULT keyword (uppercase, matching knex.js and
          // the formatter's not-set sentinel).
          rowBindings.add('DEFAULT');
        }
      }
      valuesClauses.add('(${rowBindings.join(', ')})');
    }

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

    if (strategy == 'ignore') {
      if (_isMySqlLikeDriver) {
        // MySQL: INSERT IGNORE is a prefix — nothing to add here
        return '';
      }
      // `ON CONFLICT DO NOTHING` needs the same ON CONFLICT support as merge;
      // guard it so unsupported dialects (mssql/snowflake/bigquery/redshift)
      // fail loudly instead of emitting invalid SQL.
      if (!_supports(SqlCapability.onConflictMerge)) {
        throw StateError(
          '.onConflict().ignore() is not supported by ${client.driverName}',
        );
      }
      // Postgres / SQLite
      final target = _conflictTarget(column);
      return 'on conflict$target do nothing';
    }

    if (strategy == 'merge') {
      if (!_supports(SqlCapability.onConflictMerge)) {
        throw StateError(
          '.onConflict().merge() is not supported by ${client.driverName}',
        );
      }
      final mergeColumns = onConflict['mergeColumns'];
      final insertValue = single['insert'];

      // Determine which columns to update
      final List<String> updateColumns;
      Map<String, dynamic>? rawUpdateValues;

      if (mergeColumns == null) {
        // No arg: update all inserted columns. knex.js derives this list from
        // the same `_prepInsert` pass used for the INSERT column list itself
        // — the union of every row's keys (not just row[0]'s: a ragged
        // multi-row insert can have a column that only appears from the
        // second row onward, and it must still be merge-updated), sorted
        // alphabetically (`Object.keys(...).sort()`), matching the INSERT
        // column list itself.
        final rows = insertValue is List
            ? insertValue.cast<Map<String, dynamic>>()
            : [insertValue as Map<String, dynamic>];
        final columnSet = <String>{};
        for (final row in rows) {
          columnSet.addAll(row.keys);
        }
        updateColumns = columnSet.toList()..sort();
      } else if (mergeColumns is List) {
        updateColumns = List<String>.from(mergeColumns);
      } else if (mergeColumns is Map) {
        rawUpdateValues = Map<String, dynamic>.from(mergeColumns);
        updateColumns = [];
      } else {
        updateColumns = [];
      }

      if (_isMySqlLikeDriver) {
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
            // Lowercase `values()` — matches knex.js and knex-dart's otherwise
            // all-lowercase keyword style.
            setClauses.add('$wrappedCol = values($wrappedCol)');
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
    if (column is Raw) {
      // A raw conflict target (e.g. `onConflict(raw('(value) WHERE deleted_at
      // IS NULL'))`, a partial-index conflict target) carries its own
      // parens/guard clause — inline it verbatim, matching knex.js. Without
      // this branch the entire target was silently dropped, producing a bare
      // `on conflict do nothing`/`do update` instead of a targeted one.
      return ' ${_inlineRaw(column)}';
    }
    return '';
  }

  /// Compile RETURNING clause
  ///
  String _returning() {
    final returningCols = single['returning'];
    if (returningCols == null ||
        returningCols is! List ||
        returningCols.isEmpty) {
      return '';
    }

    if (!_supports(SqlCapability.returning)) {
      // Mirrors knex.js: dialects without RETURNING support (mysql,
      // redshift, ...) log a warning and silently drop the clause rather
      // than failing the whole query.
      client.logger.warning(
        '.returning() is not supported by ${client.driverName} and will '
        'not have any effect.',
      );
      return '';
    }

    final columns = (returningCols as List<String>)
        .map((c) => formatter.wrap(c))
        .join(', ');

    return 'returning $columns';
  }

  /// Compile UPDATE query
  ///
  String _updateQuery() {
    final parts = <String>[];

    // WITH (CTE) clauses must precede UPDATE.
    final withSql = _with();
    if (withSql.isNotEmpty) {
      parts.add(withSql);
    }

    parts.add(_update());

    final where = _where();
    if (where.isNotEmpty) {
      parts.add(where);
    }

    // MySQL-only extension: `UPDATE ... SET ... WHERE ... ORDER BY ...
    // LIMIT ...`. Standard SQL doesn't allow ORDER BY/LIMIT on UPDATE, so
    // this is gated to MySQL to match knex.js's mysql-querycompiler.
    if (_isMySqlLikeDriver) {
      final order = _order();
      if (order.isNotEmpty) {
        parts.add(order);
      }
      final limit = _limit();
      if (limit.isNotEmpty) {
        parts.add(limit);
      }
    }

    final returning = _returning();
    if (returning.isNotEmpty) {
      parts.add(returning);
    }

    return parts.join(' ');
  }

  /// Compile UPDATE statement
  ///
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

    // MySQL-only extension: `UPDATE table INNER JOIN other ON ... SET ...`.
    // Standard SQL has no JOIN clause on UPDATE, so this is gated to MySQL
    // to match knex.js's mysql-querycompiler.
    final join = _isMySqlLikeDriver ? _join() : '';
    final joinClause = join.isNotEmpty ? ' $join' : '';

    return 'update $table$joinClause set ${updates.join(', ')}';
  }

  /// Compile DELETE query
  ///
  /// Mirrors knex.js's per-dialect handling of `.del()` combined with
  /// `.join(...)`. Standard SQL has no JOIN clause on DELETE, so each dialect
  /// family expresses it differently — silently dropping the join (the
  /// previous behavior here) would change query semantics, not just syntax:
  ///   - Postgres/CockroachDB: `DELETE FROM t USING j WHERE ... AND` join-on
  ///     conditions (join ON conditions fold into WHERE).
  ///   - MySQL/SQLite/Redshift (and default): `DELETE t FROM t` join `WHERE
  ///     ...` (join stays a real JOIN clause; WHERE is untouched).
  String _deleteQuery() {
    final parts = <String>[];

    // WITH (CTE) clauses must precede DELETE.
    final withSql = _with();
    if (withSql.isNotEmpty) {
      parts.add(withSql);
    }

    // Side-effect-free emptiness check — deliberately NOT `_join().isEmpty`.
    // `_join()` compiles ON conditions (via `_compileJoinClauseSequence` →
    // `client.parameter()`) and appends to `bindings` as a side effect;
    // calling it here just to probe emptiness, then compiling the same
    // conditions again in the postgres branch below via
    // `_deleteUsingJoins()`, would append every bound join value TWICE and
    // in the wrong slot (before WHERE's bindings instead of after — SQL text
    // order for the postgres USING transform is `where <where> and <join
    // conditions>`, so bindings must accumulate WHERE-then-join, not
    // join-then-WHERE-then-join-again).
    final hasJoins = (grouped['join']?.isNotEmpty ?? false);

    if (!hasJoins) {
      parts.add(_delete());
      final where = _where();
      if (where.isNotEmpty) {
        parts.add(where);
      }
    } else if (_isPostgresLikeDriver) {
      parts.add(_delete());
      // Compile WHERE first so its bindings land before the join ON
      // conditions' bindings, matching the text order below.
      final where = _where();
      const wherePrefix = 'where ';
      final whereBody = where.isEmpty
          ? ''
          : (where.startsWith(wherePrefix)
                ? where.substring(wherePrefix.length)
                : where); // defensive: never silently drop a non-empty WHERE
      final usingJoins = _deleteUsingJoins();
      if (usingJoins.tables.isNotEmpty) {
        parts.add('using ${usingJoins.tables.join(',')}');
      }
      final combined = [
        if (whereBody.isNotEmpty) whereBody,
        ...usingJoins.conditions,
      ].join(' and ');
      if (combined.isNotEmpty) {
        parts.add('where $combined');
      }
    } else {
      final table = formatter.wrap(single['table']);
      // Text order here is `<join> where ...`, so compile the join first —
      // its bindings must precede WHERE's, matching the SQL text.
      final joinSql = _join();
      parts.add('delete $table from $table $joinSql');
      final where = _where();
      if (where.isNotEmpty) {
        parts.add(where);
      }
    }

    // MySQL-only extension: `DELETE ... WHERE ... LIMIT ...`. Standard SQL
    // has no LIMIT on DELETE, so this is gated to MySQL to match knex.js's
    // mysql-querycompiler.
    if (_isMySqlLikeDriver) {
      final limit = _limit();
      if (limit.isNotEmpty) {
        parts.add(limit);
      }
    }

    // SQLite supports RETURNING on INSERT/UPDATE but NOT DELETE (verified
    // against real knex.js — its sqlite3 dialect never emits it there),
    // unlike every other capability-gated verb, which is symmetric. Skip it
    // here regardless of the `returning` capability flag.
    if (!_isSqliteLikeDriver) {
      final returning = _returning();
      if (returning.isNotEmpty) {
        parts.add(returning);
      }
    }

    return parts.join(' ');
  }

  /// Extracts JOIN tables and their ON-condition text for the Postgres
  /// `DELETE ... USING` transform: each joined table becomes a USING entry
  /// and its ON condition(s) fold into WHERE (see `_deleteQuery`).
  ({List<String> tables, List<String> conditions}) _deleteUsingJoins() {
    final joins = grouped['join'];
    final tables = <String>[];
    final conditions = <String>[];
    if (joins == null) return (tables: tables, conditions: conditions);

    for (final stmt in joins) {
      // Raw/lateral joins have no table+condition shape to fold into USING;
      // leave them out rather than emit something incorrect (not exercised
      // by any known call pattern here).
      if (stmt['type'] == 'joinRaw' || stmt['type'] == 'joinLateral') {
        continue;
      }
      tables.add(_wrapTableIdentifier(stmt['table'].toString()));
      if (stmt['join'] == 'cross') {
        continue; // CROSS JOIN has no ON condition to fold in.
      }
      if (stmt['joinClause'] != null) {
        final cond = _compileJoinClauses(stmt['joinClause']);
        if (cond.isNotEmpty) conditions.add(cond);
      } else {
        final col1 = formatter.wrap(stmt['column1']);
        final col2 = formatter.wrap(stmt['column2']);
        conditions.add('$col1 = $col2');
      }
    }
    return (tables: tables, conditions: conditions);
  }

  /// Compile TRUNCATE TABLE statement
  ///
  /// Postgres appends `restart identity`.
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
          .map((col) => formatter.wrap(col.toString()))
          .join(', ');
      // Postgres-family: with DISTINCT + multiple columns, knex.js's pg
      // query-compiler treats the column list as a row constructor — emitting
      // `count(distinct("foo", "bar"))` (extra parens around the column
      // list) — unlike mysql/sqlite which emit the standard
      // `count(distinct \`foo\`, \`bar\`)`. Verified against real knex.js 3.3.0
      // for all three dialects. (Single-column distinct is identical across
      // all dialects — `count(distinct "foo")` — already handled by the
      // string-value path below.)
      final isPgFamily = const {
        'pg',
        'postgres',
        'postgresql',
        'cockroachdb',
        'redshift',
      }.contains(client.driverName);
      final String aggregated;
      if (distinct.isNotEmpty && value.length > 1 && isPgFamily) {
        aggregated = '$method(distinct($columns))';
      } else if (distinct.isNotEmpty) {
        aggregated = '$method(distinct $columns)';
      } else {
        aggregated = '$method($columns)';
      }
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
              .map((col) => formatter.wrap(col.toString()))
              .join(', ');
          final distinctPart = distinct.isNotEmpty
              ? 'distinct $columns'
              : columns;
          final aggregated = '$method($distinctPart)';
          return addAlias(aggregated, alias);
        }
        final wrapped = formatter.wrap(column.toString());
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

    final wrapped = formatter.wrap(column);
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

    return '$method($distinct${_inlineRaw(raw)})';
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // JSON OPERATORS (PG, MySQL, SQLite)
  // ─────────────────────────────────────────────────────────────────────────────

  // These three driver-family checks previously used bare `client.driverName
  // == 'mysql'` / `== 'sqlite'` / `== 'pg'` comparisons, which never matched
  // this codebase's actual driver-name strings for the core dialects
  // (`mysql2`, `sqlite3`) — the mysql/sqlite branches below were dead code
  // for every dialect built via `KnexQuery.forClient`. Widened to the same
  // alias sets used elsewhere in this file (`_lock()`'s `postgresLike`, the
  // `isMySQL` checks throughout) and to the sqlite-family set (turso/d1),
  // matching the family-aware-dispatch convention this codebase otherwise
  // follows for SQLite-family dialects.
  //
  // `_isPostgresLikeDriver` is also used by `_deleteQuery()`'s
  // Postgres-vs-JOIN-clause DELETE dispatch (deliberately NOT Redshift —
  // knex.js's redshift-querycompiler doesn't inherit pg-querycompiler's
  // `del()` override, and none of Redshift's JSON-where shapes are exercised
  // by knex.js's own test suite either — verified against real knex.js).
  //
  // Includes `mariadb` (knex-dart supports `KnexDialect.mariadb`, which emits
  // driver-name `'mariadb'`, uses the mysql formatter and `?` placeholders
  // — see knex_query.dart `_driverStr`/`wrapIdentifierImpl`/`parameterPlaceholder`).
  // Previously missing here, which silently routed JSON-where, INSERT IGNORE,
  // onConflict merge/ignore, UPDATE join/order/limit and DELETE limit off the
  // intended MySQL-shaped compile path for mariadb — leaving compiled SQL
  // semantically wrong (e.g. `where \`c\` = ?` instead of
  // `where json_contains(\`c\`, ?)`, or a JOIN clause dropped from an UPDATE
  // entirely). Mirrors the `mariadb` inclusion in `schema_compiler`'s
  // `_isMySqlLike`.
  bool get _isMySqlLikeDriver =>
      client.driverName == 'mysql' ||
      client.driverName == 'mysql2' ||
      client.driverName == 'mariadb';
  bool get _isSqliteLikeDriver => const {
    'sqlite',
    'sqlite3',
    'turso',
    'd1',
  }.contains(client.driverName);
  bool get _isPostgresLikeDriver => const {
    'pg',
    'postgres',
    'postgresql',
    'cockroachdb',
    'mock',
  }.contains(client.driverName);

  String _whereJsonObject(Map<String, dynamic> statement) {
    final col = formatter.wrap(statement['column']);
    final val = _valueClause(statement);
    if (_isMySqlLikeDriver) {
      // MySQL has no `=` semantics for JSON columns; knex.js wraps in
      // json_contains() instead.
      return '${_not(statement, '')}json_contains($col, $val)';
    }
    return '${_not(statement, '') + col} = $val';
  }

  String _whereJsonPath(Map<String, dynamic> statement) {
    // Postgres only (NOT cockroachdb — cockroachdb uses `json_extract_path`
    // with the JSONPath split into positional segments, a materially
    // different transform not implemented here; see the
    // `json/where-path::cockroachdb` parity allowlist entry).
    final isPg = client.driverName == 'pg' ||
        client.driverName == 'postgres' ||
        client.driverName == 'postgresql';
    if (isPg) {
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
    } else if (_isMySqlLikeDriver || _isSqliteLikeDriver) {
      final col = formatter.wrap(statement['column']);
      final path = client.parameter(statement['jsonPath'], bindings);
      final op = formatter.operator(statement['operator']);
      final valClause = _valueClause(statement);
      return '${_not(statement, '')}json_extract($col, $path) $op $valClause';
    }
    // Not implemented for this dialect (cockroachdb) or genuinely
    // unsupported (redshift — real knex.js itself throws compiling this).
    // Previously fell through to whereBasic(), silently compiling a plain
    // (wrong) column comparison instead of refusing.
    throw StateError('whereJsonPath is not supported by ${client.driverName}');
  }

  String _whereJsonSupersetOf(Map<String, dynamic> statement) {
    final col = formatter.wrap(statement['column']);
    final val = _valueClause(statement);
    if (_isPostgresLikeDriver) {
      return '${_not(statement, '')}$col @> $val';
    }
    if (_isMySqlLikeDriver) {
      // No space after the comma here — matches knex.js's mysql-querycompiler
      // for whereJsonSupersetOf specifically (whereJsonObject's json_contains
      // call, above, does have a space; knex.js is simply inconsistent about
      // it between the two).
      return '${_not(statement, '')}json_contains($col,$val)';
    }
    // Previously fell through to whereBasic() with operator forced to '=',
    // silently compiling a plain (wrong) equality check instead of
    // refusing.
    throw StateError(
      'whereJsonSupersetOf is not supported by ${client.driverName}',
    );
  }

  String _whereJsonSubsetOf(Map<String, dynamic> statement) {
    final col = formatter.wrap(statement['column']);
    final val = _valueClause(statement);
    if (_isPostgresLikeDriver) {
      return '${_not(statement, '')}$col <@ $val';
    }
    if (_isMySqlLikeDriver) {
      // Argument order is reversed vs. supersetOf — matches knex.js. No
      // space after the comma (see the note in _whereJsonSupersetOf).
      return '${_not(statement, '')}json_contains($val,$col)';
    }
    throw StateError(
      'whereJsonSubsetOf is not supported by ${client.driverName}',
    );
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
