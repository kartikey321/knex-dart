/// Microsoft SQL Server driver for knex_dart.
///
/// Example:
/// ```dart
/// import 'package:knex_dart_mssql/knex_dart_mssql.dart';
///
/// final db = await KnexMssql.connect(
///   host: 'localhost',
///   database: 'AdventureWorks',
///   username: 'sa',
///   password: const String.fromEnvironment('MSSQL_PASSWORD'),
/// );
///
/// final rows = await db.select(
///   db.queryBuilder().from('orders').where('status', '=', 'open'),
/// );
///
/// await db.close();
/// ```
///
/// Pure Dart — no native library or system dependency to install. Works
/// anywhere a Dart `Socket`/`SecureSocket` does, speaking TDS over
/// [`mssql`](https://pub.dev/packages/mssql).
library;

export 'src/mssql_client.dart';
export 'src/knex_mssql.dart';
