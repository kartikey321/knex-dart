/// Snowflake driver for knex_dart.
///
/// Example:
/// ```dart
/// import 'package:knex_dart_snowflake/knex_dart_snowflake.dart';
///
/// final db = KnexSnowflake(
///   account: 'myorg-myaccount',
///   token: 'your-oauth-token',
///   database: 'MY_DATABASE',
///   schema: 'PUBLIC',
///   warehouse: 'COMPUTE_WH',
/// );
///
/// final rows = await db.select(
///   db.queryBuilder().from('ORDERS').where('STATUS', '=', 'OPEN'),
/// );
///
/// db.close();
/// ```
library;

export 'src/snowflake_client.dart';
export 'src/knex_snowflake.dart';
