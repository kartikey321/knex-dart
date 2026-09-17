import '../client/client.dart';

/// Transaction configuration
@Deprecated(
  'Client.transaction()/Transaction were never implemented (every driver '
  'override throws) and will be removed in a future major version. Use the '
  'callback-style transaction API instead, e.g. KnexPostgres.trx((trx) '
  'async { ... }). Client.runInTransaction() is safe only on drivers that '
  'override it to pin one physical connection (Postgres, MySQL, SQLite).',
)
class TransactionConfig {
  final String? isolationLevel;
  final bool? readOnly;
  final Map<String, dynamic>? userParams;

  const TransactionConfig({
    this.isolationLevel,
    this.readOnly,
    this.userParams,
  });
}

/// Transaction class
///
/// Never implemented — every driver's `Client.transaction()` override throws
/// (`UnimplementedError` in real drivers, `UnsupportedError` in `KnexQuery`).
/// Use the callback-style transaction API instead (e.g.
/// `KnexPostgres.trx((trx) async { ... })`). `Client.runInTransaction()` is
/// also an option, but only on drivers that override it to pin one physical
/// connection (currently Postgres, MySQL, SQLite) — the base implementation
/// is unsafe on other pooled drivers.
@Deprecated(
  'Client.transaction()/Transaction were never implemented (every driver '
  'override throws) and will be removed in a future major version. Use the '
  'callback-style transaction API instead, e.g. KnexPostgres.trx((trx) '
  'async { ... }). Client.runInTransaction() is safe only on drivers that '
  'override it to pin one physical connection (Postgres, MySQL, SQLite).',
)
class Transaction {
  // ignore: unused_field
  final Client _client;

  Transaction(this._client);

  Future<void> commit() async {
    throw UnimplementedError('Transaction not yet implemented');
  }

  Future<void> rollback() async {
    throw UnimplementedError('Transaction not yet implemented');
  }
}
