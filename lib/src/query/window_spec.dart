/// Window function specification for OVER (...) clause.
///
/// Used with window functions like [QueryBuilder.rowNumber],
/// [QueryBuilder.rank], [QueryBuilder.lead], etc.
///
/// Example:
/// ```dart
/// final win = WindowSpec()
///   .partitionBy(['department'])
///   .orderBy('salary', 'desc');
///
/// qb.select(['name']).rowNumber('rn', win);
/// // → SELECT name, row_number() OVER (PARTITION BY "department" ORDER BY "salary" desc) AS "rn"
/// ```
class WindowSpec {
  final List<String> _partitionBy;
  final List<Map<String, String>> _orderBy;
  final int? _frameStart;
  final int? _frameEnd;

  WindowSpec({List<String>? partitionBy, List<Map<String, String>>? orderBy})
    : _partitionBy = partitionBy ?? [],
      _orderBy = orderBy ?? [],
      _frameStart = null,
      _frameEnd = null;

  WindowSpec._({
    required List<String> partitionBy,
    required List<Map<String, String>> orderBy,
    int? frameStart,
    int? frameEnd,
  }) : _partitionBy = partitionBy,
       _orderBy = orderBy,
       _frameStart = frameStart,
       _frameEnd = frameEnd;

  /// Add one or more PARTITION BY columns.
  WindowSpec partitionBy(List<String> columns) {
    return WindowSpec._(
      partitionBy: [..._partitionBy, ...columns],
      orderBy: _orderBy,
      frameStart: _frameStart,
      frameEnd: _frameEnd,
    );
  }

  /// Add an ORDER BY column with optional direction ('asc' | 'desc').
  WindowSpec orderBy(String column, [String direction = 'asc']) {
    return WindowSpec._(
      partitionBy: _partitionBy,
      orderBy: [
        ..._orderBy,
        {'column': column, 'direction': direction},
      ],
      frameStart: _frameStart,
      frameEnd: _frameEnd,
    );
  }

  List<String> get partitions => _partitionBy;
  List<Map<String, String>> get orders => _orderBy;
}
