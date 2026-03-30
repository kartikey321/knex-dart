import '../client/client.dart';

/// Transaction configuration
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
/// Stub implementation - full implementation in Week 12.
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
