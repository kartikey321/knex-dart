import 'package:mssql_connection/mssql_connection.dart';

void main() async {
  final conn = MssqlConnection.getInstance();
  try {
    final ok = await conn.connect(
      ip: 'localhost',
      port: '1433',
      databaseName: 'knex_test',
      username: 'sa',
      password: 'Knex_Test1!',
      timeoutInSeconds: 15,
    );
    print('connect returned: \$ok');
    if (ok) {
      final result = await conn.getData('SELECT 1 AS n');
      print('query result: \$result');
    }
    await conn.disconnect();
  } catch (e, st) {
    print('ERROR: \$e');
    print(st);
  }
}
