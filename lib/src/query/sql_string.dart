/// Represents a compiled SQL query with its bindings
class SqlString {
  /// The SQL query string with placeholders
  final String sql;

  /// The parameter bindings for the query
  final List<dynamic> bindings;

  /// Method type (select, insert, update, delete, etc.)
  final String? method;
  final String? uid; // Query unique identifier (JS: __knexQueryUid)

  SqlString(this.sql, this.bindings, {this.method, this.uid});

  @override
  String toString() => sql;

  /// Convert to a map representation
  Map<String, dynamic> toMap() {
    return {
      'sql': sql,
      'bindings': bindings,
      if (method != null) 'method': method,
    };
  }

  /// Create a copy with different values
  SqlString copyWith({String? sql, List<dynamic>? bindings, String? method}) {
    return SqlString(
      sql ?? this.sql,
      bindings ?? this.bindings,
      method: method ?? this.method,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SqlString) return false;
    return sql == other.sql &&
        _listEquals(bindings, other.bindings) &&
        method == other.method;
  }

  @override
  int get hashCode => Object.hash(sql, Object.hashAll(bindings), method);

  static bool _listEquals(List? a, List? b) {
    if (a == null) return b == null;
    if (b == null || a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
