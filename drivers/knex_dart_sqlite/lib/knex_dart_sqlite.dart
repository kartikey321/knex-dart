/// SQLite driver for knex_dart.
///
/// Example:
/// ```dart
/// import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';
///
/// final db = await KnexSQLite.connect(filename: ':memory:');
/// await db.executeSchema((s) {
///   s.createTable('users', (t) {
///     t.increments('id');
///     t.string('name');
///   });
/// });
///
/// await db.insert(db.queryBuilder().table('users').insert({'name': 'Alice'}));
/// final rows = await db.select(db.queryBuilder().table('users'));
/// await db.close();
/// ```
export 'src/sqlite_client.dart';
export 'src/knex_sqlite.dart';
