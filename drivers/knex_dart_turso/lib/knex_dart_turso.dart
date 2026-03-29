/// Turso (libSQL) driver for knex_dart.
///
/// Example:
/// ```dart
/// import 'package:knex_dart_turso/knex_dart_turso.dart';
///
/// final db = KnexTurso(
///   url: 'https://my-db-org.turso.io',
///   authToken: 'eyJ...',
/// );
///
/// final users = await db.select(
///   db.queryBuilder().from('users').where('active', '=', 1),
/// );
///
/// db.close();
/// ```
library;

export 'src/turso_client.dart';
export 'src/knex_turso.dart';
