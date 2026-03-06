import 'query_builder.dart';

/// Fluent builder for ON CONFLICT / INSERT IGNORE / ON DUPLICATE KEY UPDATE
///
/// Usage:
/// ```dart
/// // PG/SQLite: ON CONFLICT DO NOTHING
/// qb.insert({...}).onConflict('email').ignore();
///
/// // PG: ON CONFLICT DO UPDATE SET all columns
/// qb.insert({...}).onConflict('email').merge();
///
/// // PG: ON CONFLICT DO UPDATE SET specific columns
/// qb.insert({...}).onConflict('email').merge(['name', 'phone']);
/// ```
class OnConflictBuilder {
  final QueryBuilder _queryBuilder;
  final dynamic _conflictColumns;

  OnConflictBuilder(this._queryBuilder, this._conflictColumns);

  /// Generate ON CONFLICT DO NOTHING (PG/SQLite)
  /// or INSERT IGNORE (MySQL)
  QueryBuilder ignore() {
    _queryBuilder.single['onConflict'] = {
      'strategy': 'ignore',
      'columns': _conflictColumns,
    };
    return _queryBuilder;
  }

  /// Generate ON CONFLICT DO UPDATE SET (PG/SQLite)
  /// or ON DUPLICATE KEY UPDATE (MySQL)
  ///
  /// [mergeColumns] - if provided, only merge these columns.
  ///                  Otherwise all inserted columns will be merged.
  QueryBuilder merge([dynamic mergeColumns]) {
    _queryBuilder.single['onConflict'] = {
      'strategy': 'merge',
      'columns': _conflictColumns,
      'mergeColumns': mergeColumns,
    };
    return _queryBuilder;
  }
}
