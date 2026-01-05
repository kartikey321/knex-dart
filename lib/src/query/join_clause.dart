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

  JoinClause(this.table, this.joinType);

  /// Add an ON condition
  ///
  /// JS Reference: joinclause.js lines 53-71
  ///
  /// Supports:
  /// - on(col1, col2) - assumes '=' operator
  /// - on(col1, operator, col2) - explicit operator
  JoinClause on(String first, [String? operator, String? second]) {
    // Determine actual operator and second column
    final actualOperator = second != null ? operator! : '=';
    final actualSecond = second ?? operator!;

    clauses.add({
      'type': 'onBasic',
      'column': first,
      'operator': actualOperator,
      'value': actualSecond,
      'bool': _bool(),
    });

    return this;
  }

  /// Add an AND ON condition (alias for on)
  ///
  /// JS Reference: joinclause.js line 258
  JoinClause andOn(String first, [String? operator, String? second]) {
    return on(first, operator, second);
  }

  /// Add an OR ON condition
  ///
  /// JS Reference: joinclause.js lines 74-76
  JoinClause orOn(String first, [String? operator, String? second]) {
    _boolFlag = 'or';
    return on(first, operator, second);
  }

  /// Get current boolean flag and reset to 'and'
  ///
  /// JS Reference: joinclause.js lines 233-241
  String _bool() {
    final ret = _boolFlag;
    _boolFlag = 'and'; // Reset after use
    return ret;
  }
}
