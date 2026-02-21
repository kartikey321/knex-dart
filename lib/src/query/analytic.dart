/// Dart port of Knex.js `lib/query/analytic.js`
///
/// The [AnalyticClause] is used for window / analytic functions
/// (row_number, rank, dense_rank) when a **callback** is passed.
///
/// In Knex.js the callback receives an `Analytic` instance as `this` so
/// callers can fluently call `.orderBy()` and `.partitionBy()` on it.
/// In Dart (no `this`-binding) we expose the same API on a builder object
/// that is passed to the callback.
///
/// JS Reference: lib/query/analytic.js
class AnalyticClause {
  /// The SQL function name: 'row_number', 'rank', 'dense_rank'
  final String method;

  /// Optional alias (unquoted, as in Knex.js output): `row_number() over (...) as alias`
  final String? alias;

  /// ORDER BY entries — each item is either a String column name or a
  /// Map `{'column': String, 'order': String?}`.
  final List<dynamic> order;

  /// PARTITION BY entries — each item is either a String column name or a
  /// Map `{'column': String, 'order': String?}`.
  final List<dynamic> partitions;

  final String grouping = 'columns';
  final String type = 'analytic';

  AnalyticClause({
    required this.method,
    required this.alias,
    List<dynamic>? order,
    List<dynamic>? partitions,
  }) : order = order ?? [],
       partitions = partitions ?? [];

  /// Add PARTITION BY column(s).
  ///
  /// [column] may be:
  ///   - a `String` column name (optionally with a direction)
  ///   - a `List<dynamic>` of strings or `{'column', 'order'}` maps
  ///
  /// JS Reference: analytic.js `partitionBy(column, direction)`
  AnalyticClause partitionBy(dynamic column, [String? direction]) {
    if (column is List) {
      partitions.addAll(column);
    } else if (column is String) {
      partitions.add({'column': column, 'order': direction});
    }
    return this;
  }

  /// Add ORDER BY column(s).
  ///
  /// [column] may be a `String` or a `List<dynamic>` of strings /
  /// `{'column', 'order'}` maps.
  ///
  /// JS Reference: analytic.js `orderBy(column, direction)`
  AnalyticClause orderBy(dynamic column, [String? direction]) {
    if (column is List) {
      order.addAll(column);
    } else if (column is String) {
      order.add({'column': column, 'order': direction});
    }
    return this;
  }
}
