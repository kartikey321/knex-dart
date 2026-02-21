/// JoinClause for complex JOIN ON conditions
///
/// JS Reference: lib/query/joinclause.js
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

  JoinClause(this.table, this.joinType);

  /// Add an ON condition
  ///
  /// JS Reference: joinclause.js lines 53-71
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
  /// JS Reference: joinclause.js line 258
  JoinClause andOn(dynamic first, [dynamic operator, dynamic second]) {
    return on(first, operator, second);
  }

  /// Add an OR ON condition
  ///
  /// JS Reference: joinclause.js lines 74-76
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

  JoinClause andOnVal(dynamic first, [dynamic operator, dynamic second]) {
    return onVal(first, operator, second);
  }

  JoinClause orOnVal(dynamic first, [dynamic operator, dynamic second]) {
    _boolFlag = 'or';
    return onVal(first, operator, second);
  }

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

  JoinClause andOnIn(dynamic column, dynamic values) => onIn(column, values);

  JoinClause orOnIn(dynamic column, dynamic values) {
    _boolFlag = 'or';
    return onIn(column, values);
  }

  JoinClause onNotIn(dynamic column, dynamic values) {
    _notFlag = true;
    return onIn(column, values);
  }

  JoinClause andOnNotIn(dynamic column, dynamic values) =>
      onNotIn(column, values);

  JoinClause orOnNotIn(dynamic column, dynamic values) {
    _boolFlag = 'or';
    _notFlag = true;
    return onIn(column, values);
  }

  JoinClause onNull(String column) {
    clauses.add({
      'type': 'onNull',
      'column': column,
      'not': _not(),
      'bool': _bool(),
    });
    return this;
  }

  JoinClause andOnNull(String column) => onNull(column);

  JoinClause orOnNull(String column) {
    _boolFlag = 'or';
    return onNull(column);
  }

  JoinClause onNotNull(String column) {
    _notFlag = true;
    return onNull(column);
  }

  JoinClause andOnNotNull(String column) => onNotNull(column);

  JoinClause orOnNotNull(String column) {
    _boolFlag = 'or';
    _notFlag = true;
    return onNull(column);
  }

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

  JoinClause andOnBetween(String column, List<dynamic> values) =>
      onBetween(column, values);

  JoinClause orOnBetween(String column, List<dynamic> values) {
    _boolFlag = 'or';
    return onBetween(column, values);
  }

  JoinClause onNotBetween(String column, List<dynamic> values) {
    _notFlag = true;
    return onBetween(column, values);
  }

  JoinClause andOnNotBetween(String column, List<dynamic> values) =>
      onNotBetween(column, values);

  JoinClause orOnNotBetween(String column, List<dynamic> values) {
    _boolFlag = 'or';
    _notFlag = true;
    return onBetween(column, values);
  }

  JoinClause onExists(Function callback) {
    clauses.add({
      'type': 'onExists',
      'value': callback,
      'not': _not(),
      'bool': _bool(),
    });
    return this;
  }

  JoinClause andOnExists(Function callback) => onExists(callback);

  JoinClause orOnExists(Function callback) {
    _boolFlag = 'or';
    return onExists(callback);
  }

  JoinClause onNotExists(Function callback) {
    _notFlag = true;
    return onExists(callback);
  }

  JoinClause andOnNotExists(Function callback) => onNotExists(callback);

  JoinClause orOnNotExists(Function callback) {
    _boolFlag = 'or';
    _notFlag = true;
    return onExists(callback);
  }

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
  /// JS Reference: joinclause.js lines 233-241
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
