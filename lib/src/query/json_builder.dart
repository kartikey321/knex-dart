import 'dart:convert';
import 'query_builder.dart';

/// Extension adding JSON-specific querying capabilities to [QueryBuilder].
///
/// These operators are dialect-specific. They are primarily designed for
/// PostgreSQL (`jsonb` columns) but have some fallback implementations for
/// MySQL (`json_extract`) and SQLite (`json_extract`).
///
/// JS Reference: Knex.js lib/query/builder.js whereJsonObject, whereJsonPath, etc.
extension JsonQueryBuilder on QueryBuilder {
  /// Add a where clause for matching a JSON object.
  ///
  /// PG: `where "column" = '{"a":1}'`
  /// MySQL/SQLite: Often handled similarly depending on dialect JSON support.
  QueryBuilder whereJsonObject(String column, Map<String, dynamic> value) {
    statements.add({
      'grouping': 'where',
      'type': 'whereJsonObject',
      'column': column,
      'value': jsonEncode(value),
      'bool': 'and',
      'not': false,
    });
    return this;
  }

  QueryBuilder orWhereJsonObject(String column, Map<String, dynamic> value) {
    statements.add({
      'grouping': 'where',
      'type': 'whereJsonObject',
      'column': column,
      'value': jsonEncode(value),
      'bool': 'or',
      'not': false,
    });
    return this;
  }

  /// Add a where clause matching a JSON path expression.
  ///
  /// PG: `jsonb_path_query_first("column", path)::type operator value`
  ///
  /// [path] usually follows JSONPath literal syntax like `"$.theme"`
  QueryBuilder whereJsonPath(
    String column,
    String path,
    String operator,
    dynamic value,
  ) {
    statements.add({
      'grouping': 'where',
      'type': 'whereJsonPath',
      'column': column,
      'jsonPath': path,
      'operator': operator,
      'value': value,
      'bool': 'and',
      'not': false,
    });
    return this;
  }

  QueryBuilder orWhereJsonPath(
    String column,
    String path,
    String operator,
    dynamic value,
  ) {
    statements.add({
      'grouping': 'where',
      'type': 'whereJsonPath',
      'column': column,
      'jsonPath': path,
      'operator': operator,
      'value': value,
      'bool': 'or',
      'not': false,
    });
    return this;
  }

  /// Add a where clause expecting the JSON column to be a superset of [value].
  ///
  /// PG: `where "column" @> ?`
  QueryBuilder whereJsonSupersetOf(String column, dynamic value) {
    final encoded = value is String ? value : jsonEncode(value);
    statements.add({
      'grouping': 'where',
      'type': 'whereJsonSupersetOf',
      'column': column,
      'value': encoded,
      'bool': 'and',
      'not': false,
    });
    return this;
  }

  QueryBuilder orWhereJsonSupersetOf(String column, dynamic value) {
    final encoded = value is String ? value : jsonEncode(value);
    statements.add({
      'grouping': 'where',
      'type': 'whereJsonSupersetOf',
      'column': column,
      'value': encoded,
      'bool': 'or',
      'not': false,
    });
    return this;
  }

  /// Add a where clause expecting the JSON column to be a subset of [value].
  ///
  /// PG: `where "column" <@ ?`
  QueryBuilder whereJsonSubsetOf(String column, dynamic value) {
    final encoded = value is String ? value : jsonEncode(value);
    statements.add({
      'grouping': 'where',
      'type': 'whereJsonSubsetOf',
      'column': column,
      'value': encoded,
      'bool': 'and',
      'not': false,
    });
    return this;
  }

  QueryBuilder orWhereJsonSubsetOf(String column, dynamic value) {
    final encoded = value is String ? value : jsonEncode(value);
    statements.add({
      'grouping': 'where',
      'type': 'whereJsonSubsetOf',
      'column': column,
      'value': encoded,
      'bool': 'or',
      'not': false,
    });
    return this;
  }
}
