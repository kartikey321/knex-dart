import '../raw.dart';
import '../client/client.dart';

/// Formatter for wrapping identifiers and formatting SQL components
///
///
/// Handles identifier wrapping, column formatting, and SQL generation
/// with proper quoting and aliasing based on the database dialect.
class Formatter {
  final Client client;
  final dynamic builder;

  /// Accumulated bindings from processing
  final List<dynamic> bindings = [];

  /// Valid SQL operators (from JS lines 9-64)
  /// Some operators are escaped for specific databases (e.g., ? for PostgreSQL)
  static const Map<String, String> _operators = {
    '=': '=',
    '<': '<',
    '>': '>',
    '<=': '<=',
    '<=>': '<=>',
    '>=': '>=',
    '<>': '<>',
    '!=': '!=',
    'like': 'like',
    'not like': 'not like',
    'between': 'between',
    'not between': 'not between',
    'ilike': 'ilike',
    'not ilike': 'not ilike',
    'exists': 'exists',
    'not exist': 'not exist',
    'rlike': 'rlike',
    'not rlike': 'not rlike',
    'regexp': 'regexp',
    'not regexp': 'not regexp',
    'match': 'match',
    '&': '&',
    '|': '|',
    '^': '^',
    '<<': '<<',
    '>>': '>>',
    '~': '~',
    '~=': '~=',
    '~*': '~*',
    '!~': '!~',
    '!~*': '!~*',
    '#': '#',
    '&&': '&&',
    '@>': '@>',
    '<@': '<@',
    '||': '||',
    '&<': '&<',
    '&>': '&>',
    '-|-': '-|-',
    '@@': '@@',
    '!!': '!!',
    '?': r'\?', // Escaped for PostgreSQL
    '?|': r'\?|', // Escaped for PostgreSQL
    '?&': r'\?&', // Escaped for PostgreSQL
  };

  Formatter(this.client, this.builder);

  /// Format a list of columns with proper identifier wrapping
  ///
  ///
  /// Handles:
  /// - Simple: ['id', 'name'] → "id", "name"
  /// - Objects: { 'alias': 'column' } → "column" as "alias"
  /// - Mixed: ['id', { 'user_name': 'name' }] → "id", "name" as "user_name"
  ///
  /// Example:
  /// ```dart
  /// columnize(['id', 'name']) // → "id", "name"
  /// columnize({ 'user_name': 'name' }) // → "name" as "user_name"
  /// columnize(['id', { 'alias': 'col' }]) // → "id", "col" as "alias"
  /// ```
  String columnize(dynamic target) {
    // Handle Map (object notation for aliasing)
    if (target is Map) {
      return _parseObject(target);
    }

    // Handle List (may contain mixed strings and objects)
    final columns = target is List ? target : [target];
    final parts = <String>[];

    for (final col in columns) {
      if (col is Map) {
        // Object in array: { 'alias': 'column' }
        parts.add(_parseObject(col));
      } else {
        // Simple value (string, number, Raw, etc.)
        parts.add(wrap(col));
      }
    }

    return parts.join(', ');
  }

  /// Parse object notation for column aliasing
  ///
  ///
  /// Handles { 'alias_name': 'column_name' } → "column_name" as "alias_name"
  String _parseObject(Map<dynamic, dynamic> obj) {
    final parts = <String>[];

    for (final alias in obj.keys) {
      final column = obj[alias];

      // Wrap the column and alias
      final wrappedColumn = wrap(column);
      final wrappedAlias = wrapAsIdentifier(alias.toString());

      // Use client's alias method
      parts.add(client.alias(wrappedColumn, wrappedAlias));
    }

    return parts.join(', ');
  }

  /// Validate and return SQL operator
  ///
  ///
  /// Validates operator is in allowed list, handles Raw values.
  /// Throws Exception for invalid operators.
  ///
  /// Operators map from JS lines 9-64 (40+ operators)
  String operator(dynamic value) {
    // Check if Raw first
    final rawSql = _unwrapRaw(value, false);
    if (rawSql != null) return rawSql;

    // Lookup operator (case-insensitive)
    final op = _operators[value.toString().toLowerCase()];
    if (op == null) {
      throw Exception('The operator "$value" is not permitted');
    }
    return op;
  }

  /// Validate and return sort direction (ASC/DESC)
  ///
  ///
  /// Returns validated direction or defaults to 'asc'.
  /// Handles Raw values.
  String direction(dynamic value) {
    // Check if Raw first
    final rawSql = _unwrapRaw(value, false);
    if (rawSql != null) return rawSql;

    // Valid directions
    const orderBys = ['asc', 'desc'];

    // Check if valid (case-insensitive)
    final valueStr = value.toString().toLowerCase();
    return orderBys.contains(valueStr) ? value.toString() : 'asc';
  }

  /// Universal wrapper for any value type
  ///
  ///
  /// Dispatches to appropriate handler based on value type:
  /// - Raw → unwrap to SQL
  /// - Number → return as-is
  /// - String → wrapString
  dynamic wrap(dynamic value, [bool isParameter = false]) {
    // Check if Raw
    final rawSql = _unwrapRaw(value, isParameter);
    if (rawSql != null) return rawSql;

    // Handle by type
    if (value is num) {
      return value;
    }

    // Default: treat as string identifier
    return wrapString(value.toString());
  }

  /// Extract SQL from Raw instance
  ///
  ///
  /// Returns null if not a Raw, otherwise returns SQL string
  /// and accumulates bindings.
  String? _unwrapRaw(dynamic value, bool isParameter) {
    if (value is Raw) {
      // Get the toSQL result
      final sqlResult = value.toSQL();

      // Accumulate bindings
      if (sqlResult.bindings.isNotEmpty) {
        bindings.addAll(sqlResult.bindings);
      }

      // Return the SQL (which is already formatted by Raw.toSQL)
      return sqlResult.sql;
    }

    // Could also handle QueryBuilder here in future

    return null;
  }

  /// Wrap string identifier with quotes, handling dots and aliases
  ///
  ///
  /// Handles:
  /// - Simple: 'users' → "users"
  /// - Dotted: 'schema.table' → "schema"."table"
  /// - Aliased: 'name AS alias' → "name" AS "alias"
  String wrapString(String value) {
    // Check for " AS " alias (case-insensitive)
    final asIndex = value.toLowerCase().indexOf(' as ');
    if (asIndex != -1) {
      final first = value.substring(0, asIndex);
      final second = value.substring(asIndex + 4);
      return client.alias(wrapString(first), wrapAsIdentifier(second));
    }

    // Split by dots
    final segments = value.split('.');
    final wrapped = <String>[];

    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      if (i == 0 && segments.length > 1) {
        // First segment of multi-part: wrap as string recursively
        wrapped.add(wrapString(segment.trim()));
      } else {
        // Other segments: wrap as identifier
        wrapped.add(wrapAsIdentifier(segment));
      }
    }

    return wrapped.join('.');
  }

  /// Wrap as identifier using client's wrapping logic
  ///
  String wrapAsIdentifier(String value) {
    // Skip wrapping for wildcard
    if (value == '*') return value;

    // Use client's identifier wrapping
    return client.wrapIdentifier(value.trim());
  }

  /// Format a parameter value, handling NULL/undefined
  ///
  ///
  /// Returns placeholder for value, with optional fallback for NULL
  String parameter(dynamic value, [dynamic notSetValue]) {
    if (value == null) {
      if (notSetValue != null) {
        return notSetValue.toString();
      }
      // Let client handle NULL
      return client.parameter(null, bindings);
    }
    return client.parameter(value, bindings);
  }

  /// Format a values list for IN clauses
  ///
  ///
  /// Formats value lists: [1,2,3] → (?, ?, ?)
  /// Handles nested arrays: [[1,2,3]] → (?, ?, ?)
  String values(dynamic values) {
    if (values is List) {
      // If single nested array, unwrap it
      if (values.length == 1 && values[0] is List) {
        return '(${_parameterize(values[0] as List)})';
      }
      return '(${_parameterize(values)})';
    }
    // Single value
    return parameter(values);
  }

  /// Helper to parameterize a list of values
  ///
  /// Returns comma-separated placeholders: ?, ?, ?
  String _parameterize(List values) {
    final placeholders = <String>[];
    for (final value in values) {
      placeholders.add(client.parameter(value, bindings));
    }
    return placeholders.join(', ');
  }
}
