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
  final String? _frameType; // 'rows' or 'range'

  // ── Frame boundary constants ──────────────────────────────────────────────
  //
  // These sentinels are chosen to be far outside any realistic frame offset
  // (SQL frame offsets are typically small positive integers like 1–100).
  // Do NOT pass raw integers like -2 or 2 to rowsBetween/rangeBetween if you
  // mean "2 preceding/following" — use those integers directly; the constants
  // below are reserved for the unbounded/currentRow semantics only.

  /// Use as a frame boundary: UNBOUNDED PRECEDING.
  static const int unboundedPreceding = -0x7FFFFFFF;

  /// Use as a frame boundary: CURRENT ROW.
  static const int currentRow = 0;

  /// Use as a frame boundary: UNBOUNDED FOLLOWING.
  static const int unboundedFollowing = 0x7FFFFFFF;

  WindowSpec({List<String>? partitionBy, List<Map<String, String>>? orderBy})
    : _partitionBy = partitionBy ?? [],
      _orderBy = orderBy ?? [],
      _frameStart = null,
      _frameEnd = null,
      _frameType = null;

  WindowSpec._({
    required List<String> partitionBy,
    required List<Map<String, String>> orderBy,
    int? frameStart,
    int? frameEnd,
    String? frameType,
  }) : _partitionBy = partitionBy,
       _orderBy = orderBy,
       _frameStart = frameStart,
       _frameEnd = frameEnd,
       _frameType = frameType;

  /// Add one or more PARTITION BY columns.
  WindowSpec partitionBy(List<String> columns) {
    return WindowSpec._(
      partitionBy: [..._partitionBy, ...columns],
      orderBy: _orderBy,
      frameStart: _frameStart,
      frameEnd: _frameEnd,
      frameType: _frameType,
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
      frameType: _frameType,
    );
  }

  /// Specify a ROWS BETWEEN frame clause.
  ///
  /// Use the [unboundedPreceding], [currentRow], [unboundedFollowing] constants
  /// or positive/negative integers for n PRECEDING / n FOLLOWING.
  ///
  /// Example:
  /// ```dart
  /// WindowSpec().rowsBetween(WindowSpec.unboundedPreceding, WindowSpec.currentRow)
  /// // → ROWS BETWEEN unbounded preceding AND current row
  /// ```
  WindowSpec rowsBetween(int start, int end) {
    return WindowSpec._(
      partitionBy: _partitionBy,
      orderBy: _orderBy,
      frameStart: start,
      frameEnd: end,
      frameType: 'rows',
    );
  }

  /// Specify a RANGE BETWEEN frame clause.
  ///
  /// Use the [unboundedPreceding], [currentRow], [unboundedFollowing] constants
  /// or positive/negative integers for n PRECEDING / n FOLLOWING.
  WindowSpec rangeBetween(int start, int end) {
    return WindowSpec._(
      partitionBy: _partitionBy,
      orderBy: _orderBy,
      frameStart: start,
      frameEnd: end,
      frameType: 'range',
    );
  }

  List<String> get partitions => _partitionBy;
  List<Map<String, String>> get orders => _orderBy;

  /// The compiled frame clause string (e.g. `rows between unbounded preceding and current row`),
  /// or null if no frame was specified.
  String? get frameClause {
    if (_frameType == null || _frameStart == null || _frameEnd == null) {
      return null;
    }
    return '$_frameType between ${_frameToken(_frameStart)} and ${_frameToken(_frameEnd)}';
  }

  static String _frameToken(int v) {
    if (v == unboundedPreceding) return 'unbounded preceding';
    if (v == currentRow) return 'current row';
    if (v == unboundedFollowing) return 'unbounded following';
    return '${v.abs()} ${v < 0 ? 'preceding' : 'following'}';
  }
}
