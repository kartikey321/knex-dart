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
/// Requires FreeTDS to be installed:
///   - macOS:  `brew install freetds`
///   - Ubuntu: `sudo apt-get install -y freetds-dev libct4`
library;

export 'src/mssql_client.dart';
export 'src/knex_mssql.dart';
