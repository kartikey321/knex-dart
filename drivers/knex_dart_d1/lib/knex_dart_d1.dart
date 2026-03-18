/// Cloudflare D1 driver for knex_dart.
///
/// Example:
/// ```dart
/// import 'package:knex_dart_d1/knex_dart_d1.dart';
///
/// final db = KnexD1(
///   accountId: 'your-cloudflare-account-id',
///   databaseId: 'your-d1-database-id',
///   apiToken: 'your-cloudflare-api-token',
/// );
///
/// final rows = await db.select(
///   db.queryBuilder().from('users').where('active', '=', 1),
/// );
///
/// // Atomic batch
/// await db.batch((b) {
///   b.add(db.queryBuilder().table('users').insert({'name': 'Alice'}));
///   b.add(db.queryBuilder().table('orders').insert({'user': 'Alice'}));
/// });
///
/// db.close();
/// ```
library;

export 'src/d1_client.dart';
export 'src/knex_d1.dart';
