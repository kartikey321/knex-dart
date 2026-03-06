/// PostgreSQL driver for knex_dart.
///
/// Example:
/// ```dart
/// import 'package:knex_dart_postgres/knex_dart_postgres.dart';
///
/// final db = await KnexPostgres.connect(
///   host: 'localhost',
///   database: 'myapp',
///   username: 'user',
///   password: 'password',
/// );
///
/// final users = await db.select(
///   db.queryBuilder().from('users').where('active', '=', true)
/// );
///
/// await db.close();
/// ```
library;

export 'src/postgres_client.dart';
export 'src/knex_postgres.dart';
