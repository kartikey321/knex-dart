/// Options for configuring aggregate functions
class AggregateOptions {
  /// Whether to use DISTINCT in the aggregate
  final bool distinct;

  /// Alias for the aggregate result
  final String? as;

  const AggregateOptions({this.distinct = false, this.as});

  /// Create a copy with modified values
  AggregateOptions copyWith({bool? distinct, String? as}) {
    return AggregateOptions(
      distinct: distinct ?? this.distinct,
      as: as ?? this.as,
    );
  }
}
