/// JoinClause for complex JOIN ON conditions
///
/// Handles multiple ON conditions with AND/OR logic
/// Used in callback-based joins:
/// ```dart
/// join('orders', (j) {
///   j.on('users.id', 'orders.user_id')
///    .andOn('users.active', 'orders.active')
///    .orOn('users.admin', 'true');
/// })
/// ```
class JoinClause {
  /// Table being joined
  final String table;

  /// Join type (inner, left, right, full outer, cross)
  final String joinType;

  /// List of ON clauses
  final List<Map<String, dynamic>> clauses = [];

  /// Current boolean operator for next clause ('and' or 'or')
  String _boolFlag = 'and';
  bool _notFlag = false;

  /// Creates a join clause builder for [table] and [joinType].
  JoinClause(this.table, this.joinType);

  /// Add an ON condition
  ///
  ///
  /// Supports:
  /// - on(col1, col2) - assumes '=' operator
  /// - on(col1, operator, col2) - explicit operator
  JoinClause on(dynamic first, [dynamic operator, dynamic second]) {
    if (first is Function) {
      clauses.add({'type': 'onWrapped', 'value': first, 'bool': _bool()});
      return this;
    }

    if (first is Map<String, dynamic>) {
      final method = _bool() == 'or' ? 'orOn' : 'on';
      first.forEach((key, value) {
        if (method == 'orOn') {
          orOn(key, value);
        } else {
          on(key, value);
        }
      });
      return this;
    }

    // Raw string/sql expression form: on('users.id = orders.user_id')
    if (operator == null && second == null) {
      clauses.add({'type': 'onRaw', 'value': first, 'bool': _bool()});
      return this;
    }

    // Determine actual operator and second column
    final actualOperator = second != null ? operator.toString() : '=';
    final actualSecond = second ?? operator;

    clauses.add({
      'type': 'onBasic',
      'column': first.toString(),
      'operator': actualOperator,
      'value': actualSecond.toString(),
      'bool': _bool(),
    });

    return this;
  }

  /// Add an AND ON condition (alias for on)
  ///
  JoinClause andOn(dynamic first, [dynamic operator, dynamic second]) {
    return on(first, operator, second);
  }

  /// Add an OR ON condition
  ///
  JoinClause orOn(dynamic first, [dynamic operator, dynamic second]) {
    _boolFlag = 'or';
    return on(first, operator, second);
  }

  /// Add ON condition with a bound value on the right side.
  ///
  /// Example: onVal('orders.status', '=', 'completed')
  JoinClause onVal(dynamic first, [dynamic operator, dynamic second]) {
    if (first is Map<String, dynamic>) {
      final method = _bool() == 'or' ? 'orOnVal' : 'onVal';
      first.forEach((key, value) {
        if (method == 'orOnVal') {
          orOnVal(key, value);
        } else {
          onVal(key, value);
        }
      });
      return this;
    }

    final actualOperator = second != null ? operator.toString() : '=';
    final actualSecond = second ?? operator;
    clauses.add({
      'type': 'onVal',
      'column': first.toString(),
      'operator': actualOperator,
      'value': actualSecond,
      'bool': _bool(),
    });
    return this;
  }

  /// Add an AND ON VAL condition (alias for [onVal]).
  JoinClause andOnVal(dynamic first, [dynamic operator, dynamic second]) {
    return onVal(first, operator, second);
  }

  /// Add an OR ON VAL condition.
  JoinClause orOnVal(dynamic first, [dynamic operator, dynamic second]) {
    _boolFlag = 'or';
    return onVal(first, operator, second);
  }

  /// Add an `ON ... IN (...)` condition.
  JoinClause onIn(dynamic column, dynamic values) {
    if (values is List && values.isEmpty) {
      return onRaw('1 = 0');
    }
    clauses.add({
      'type': 'onIn',
      'column': column,
      'value': values,
      'not': _not(),
      'bool': _bool(),
    });
    return this;
  }

  /// Add an AND `ON ... IN (...)` condition.
  JoinClause andOnIn(dynamic column, dynamic values) => onIn(column, values);

  /// Add an OR `ON ... IN (...)` condition.
  JoinClause orOnIn(dynamic column, dynamic values) {
    _boolFlag = 'or';
    return onIn(column, values);
  }

  /// Add an `ON ... NOT IN (...)` condition.
  JoinClause onNotIn(dynamic column, dynamic values) {
    _notFlag = true;
    return onIn(column, values);
  }

  /// Add an AND `ON ... NOT IN (...)` condition.
  JoinClause andOnNotIn(dynamic column, dynamic values) =>
      onNotIn(column, values);

  /// Add an OR `ON ... NOT IN (...)` condition.
  JoinClause orOnNotIn(dynamic column, dynamic values) {
    _boolFlag = 'or';
    _notFlag = true;
    return onIn(column, values);
  }

  /// Add an `ON ... IS NULL` condition.
  JoinClause onNull(String column) {
    clauses.add({
      'type': 'onNull',
      'column': column,
      'not': _not(),
      'bool': _bool(),
    });
    return this;
  }

  /// Add an AND `ON ... IS NULL` condition.
  JoinClause andOnNull(String column) => onNull(column);

  /// Add an OR `ON ... IS NULL` condition.
  JoinClause orOnNull(String column) {
    _boolFlag = 'or';
    return onNull(column);
  }

  /// Add an `ON ... IS NOT NULL` condition.
  JoinClause onNotNull(String column) {
    _notFlag = true;
    return onNull(column);
  }

  /// Add an AND `ON ... IS NOT NULL` condition.
  JoinClause andOnNotNull(String column) => onNotNull(column);

  /// Add an OR `ON ... IS NOT NULL` condition.
  JoinClause orOnNotNull(String column) {
    _boolFlag = 'or';
    _notFlag = true;
    return onNull(column);
  }

  /// Add an `ON ... BETWEEN ? AND ?` condition.
  JoinClause onBetween(String column, List<dynamic> values) {
    if (values.length != 2) {
      throw ArgumentError('You must specify 2 values for the onBetween clause');
    }
    clauses.add({
      'type': 'onBetween',
      'column': column,
      'value': values,
      'not': _not(),
      'bool': _bool(),
    });
    return this;
  }

  /// Add an AND `ON ... BETWEEN` condition.
  JoinClause andOnBetween(String column, List<dynamic> values) =>
      onBetween(column, values);

  /// Add an OR `ON ... BETWEEN` condition.
  JoinClause orOnBetween(String column, List<dynamic> values) {
    _boolFlag = 'or';
    return onBetween(column, values);
  }

  /// Add an `ON ... NOT BETWEEN` condition.
  JoinClause onNotBetween(String column, List<dynamic> values) {
    _notFlag = true;
    return onBetween(column, values);
  }

  /// Add an AND `ON ... NOT BETWEEN` condition.
  JoinClause andOnNotBetween(String column, List<dynamic> values) =>
      onNotBetween(column, values);

  /// Add an OR `ON ... NOT BETWEEN` condition.
  JoinClause orOnNotBetween(String column, List<dynamic> values) {
    _boolFlag = 'or';
    _notFlag = true;
    return onBetween(column, values);
  }

  /// Add an `ON EXISTS (subquery)` condition.
  JoinClause onExists(Function callback) {
    clauses.add({
      'type': 'onExists',
      'value': callback,
      'not': _not(),
      'bool': _bool(),
    });
    return this;
  }

  /// Add an AND `ON EXISTS (...)` condition.
  JoinClause andOnExists(Function callback) => onExists(callback);

  /// Add an OR `ON EXISTS (...)` condition.
  JoinClause orOnExists(Function callback) {
    _boolFlag = 'or';
    return onExists(callback);
  }

  /// Add an `ON NOT EXISTS (subquery)` condition.
  JoinClause onNotExists(Function callback) {
    _notFlag = true;
    return onExists(callback);
  }

  /// Add an AND `ON NOT EXISTS (...)` condition.
  JoinClause andOnNotExists(Function callback) => onNotExists(callback);

  /// Add an OR `ON NOT EXISTS (...)` condition.
  JoinClause orOnNotExists(Function callback) {
    _boolFlag = 'or';
    _notFlag = true;
    return onExists(callback);
  }

  /// Add a raw ON expression.
  JoinClause onRaw(dynamic value) {
    clauses.add({'type': 'onRaw', 'value': value, 'bool': _bool()});
    return this;
  }

  /// Add a USING clause to the join.
  ///
  /// Example: join('accounts', (j) => j.using(['user_id']))
  JoinClause using(dynamic columns) {
    clauses.add({'type': 'onUsing', 'column': columns, 'bool': _bool()});
    return this;
  }

  /// Compare two JSON paths for equality in join conditions.
  ///
  /// Example:
  /// onJsonPathEquals('users.meta', '$.id', 'orders.meta', '$.user_id')
  JoinClause onJsonPathEquals(
    String columnFirst,
    String jsonPathFirst,
    String columnSecond,
    String jsonPathSecond,
  ) {
    clauses.add({
      'type': 'onJsonPathEquals',
      'columnFirst': columnFirst,
      'jsonPathFirst': jsonPathFirst,
      'columnSecond': columnSecond,
      'jsonPathSecond': jsonPathSecond,
      'bool': _bool(),
      'not': _not(),
    });
    return this;
  }

  /// Add an AND JSON-path equality condition (alias for [onJsonPathEquals]).
  JoinClause andOnJsonPathEquals(
    String columnFirst,
    String jsonPathFirst,
    String columnSecond,
    String jsonPathSecond,
  ) {
    return onJsonPathEquals(
      columnFirst,
      jsonPathFirst,
      columnSecond,
      jsonPathSecond,
    );
  }

  /// Add an OR JSON-path equality condition.
  JoinClause orOnJsonPathEquals(
    String columnFirst,
    String jsonPathFirst,
    String columnSecond,
    String jsonPathSecond,
  ) {
    _boolFlag = 'or';
    return onJsonPathEquals(
      columnFirst,
      jsonPathFirst,
      columnSecond,
      jsonPathSecond,
    );
  }

  /// Get current boolean flag and reset to 'and'
  ///
  String _bool() {
    final ret = _boolFlag;
    _boolFlag = 'and'; // Reset after use
    return ret;
  }

  bool _not() {
    final ret = _notFlag;
    _notFlag = false;
    return ret;
  }
}
