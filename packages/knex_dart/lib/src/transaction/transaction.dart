import '../client/client.dart';

/// Transaction configuration
@Deprecated(
  'Client.transaction()/Transaction were never implemented (always throw '
  'UnimplementedError) and will be removed in a future major version. Use '
  'the callback-style transaction API instead, e.g. KnexPostgres.trx((trx) '
  'async { ... }) or Client.runInTransaction().',
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
/// `UnimplementedError`. Use the callback-style transaction API instead
/// (e.g. `KnexPostgres.trx((trx) async { ... })`, or `Client.runInTransaction()`).
@Deprecated(
  'Client.transaction()/Transaction were never implemented (always throw '
  'UnimplementedError) and will be removed in a future major version. Use '
  'the callback-style transaction API instead, e.g. KnexPostgres.trx((trx) '
  'async { ... }) or Client.runInTransaction().',
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
