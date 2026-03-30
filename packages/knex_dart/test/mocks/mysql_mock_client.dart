import 'mock_client.dart';

/// Mock client for MySQL testing
class MySQLMockClient extends MockClient {
  @override
  String get driverName => 'mysql';

  @override
  String wrapIdentifierImpl(String identifier) => '`$identifier`';

  @override
  String parameterPlaceholder(int index) => '?';
}
