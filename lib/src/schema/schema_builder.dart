import '../client/client.dart';

/// Schema builder for DDL operations
///
/// Stub implementation - full implementation in Week 6.
class SchemaBuilder {
  final Client _client;

  SchemaBuilder(this._client);

  Future<void> createTable(
    String tableName,
    void Function(dynamic) callback,
  ) async {
    throw UnimplementedError('SchemaBuilder not yet implemented');
  }
}
