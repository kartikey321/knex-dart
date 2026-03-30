import 'mock_client.dart';

/// Mock client mimicking SQLite: double-quoted identifiers, ? placeholders.
class SqliteMockClient extends MockClient {
  SqliteMockClient() : super(driverName: 'sqlite3');

  @override
  String wrapIdentifierImpl(String value) {
    if (value == '*') return value;
    return '"$value"';
  }

  @override
  String parameterPlaceholder(int index) => '?';
}
