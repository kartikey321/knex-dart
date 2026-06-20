import '../query/query_builder.dart';

/// Mixin for driver wrappers that support reactive query watching.
///
/// Drivers that can observe table mutations implement this mixin.
/// Callers can check `db is WatchableClient` before calling [watch].
abstract mixin class WatchableClient {
  /// Watches a query and re-emits results whenever any of its source tables change.
  ///
  /// The stream emits immediately on subscription with the current result set,
  /// then re-emits after each relevant write.
  ///
  /// [debounce] sets the silence window — a re-query fires after this duration
  /// elapses with no further writes. Defaults to null (no time-based debounce).
  ///
  /// [maxPendingWrites] sets a write-count ceiling — a re-query fires as soon
  /// as this many writes accumulate, even if [debounce] has not elapsed.
  /// Defaults to null (no count ceiling).
  ///
  /// When both are set, whichever ceiling is hit first triggers the re-query.
  ///
  /// **Single-listener only.** The returned stream is not a broadcast stream;
  /// calling `.listen()` a second time throws a [StateError]. If multiple
  /// consumers need the same stream, wrap with `.asBroadcastStream()`.
  ///
  /// **Subquery tables are not tracked.** When the primary table is a subquery
  /// rather than a plain string (e.g. `db(db('items').as('sub'))`), no tables
  /// can be inferred and the stream will emit once on subscribe but never
  /// re-emit on writes.
  ///
  /// **DDL does not trigger re-emits.** SQLite's UPDATE_HOOK does not fire for
  /// `CREATE TABLE`, `ALTER TABLE`, or other schema changes.
  Stream<List<Map<String, dynamic>>> watch(
    QueryBuilder query, {
    Duration? debounce,
    int? maxPendingWrites,
  });
}
