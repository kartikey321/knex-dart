/// MySQL driver for knex_dart.
///
/// Example:
/// ```dart
/// import 'package:knex_dart_mysql/knex_dart_mysql.dart';
///
/// final db = await KnexMySQL.connect(
///   host: 'localhost',
///   database: 'myapp',
///   user: 'user',
///   password: 'password',
/// );
///
/// final users = await db.select(
///   db.queryBuilder().from('users').where('active', '=', true)
/// );
///
/// await db.close();
/// ```
export 'src/mysql_client.dart';
export 'src/knex_mysql.dart';
