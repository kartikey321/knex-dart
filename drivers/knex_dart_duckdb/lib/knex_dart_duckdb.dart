/// DuckDB driver for knex_dart.
///
/// Example:
/// ```dart
/// import 'package:knex_dart_duckdb/knex_dart_duckdb.dart';
///
/// // In-memory
/// final db = await KnexDuckDB.memory();
///
/// // Or persistent
/// final db = await KnexDuckDB.file('/path/to/analytics.db');
///
/// await db.executeSchema((s) {
///   s.createTable('events', (t) {
///     t.increments('id');
///     t.string('name');
///     t.timestamp('created_at');
///   });
/// });
///
/// final rows = await db.select(
///   db.queryBuilder().from('events').orderBy('created_at', 'desc').limit(10),
/// );
///
/// db.close();
/// ```
library;

export 'src/duckdb_client.dart'
    if (dart.library.js_interop) 'src/duckdb_client_web.dart';
export 'src/knex_duckdb.dart';
