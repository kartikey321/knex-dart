/// Knex Dart - SQL Query Builder
///
/// A batteries-included SQL query builder for Dart inspired by Knex.js.
/// Supports multiple database dialects via separate driver packages:
///
/// - PostgreSQL: `package:knex_dart_postgres`
/// - MySQL: `package:knex_dart_mysql`
/// - SQLite: `package:knex_dart_sqlite`
///
/// Example using SQLite:
/// ```dart
/// import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';
///
/// final db = await KnexSQLite.connect(filename: ':memory:');
///
/// await db.executeSchema((schema) {
///   schema.createTable('posts', (table) {
///     table.increments('id');
///     table.string('title').notNullable();
///   });
/// });
///
/// final posts = await db.select(db.queryBuilder().table('posts'));
/// ```
library;

// Core exports
export 'src/knex.dart';
export 'src/client/client.dart';
export 'src/client/knex_config.dart';

// Raw and Ref
export 'src/raw.dart';
export 'src/ref.dart';

// Query builder
export 'src/query/query_builder.dart';
export 'src/query/query_compiler.dart';
export 'src/query/join_clause.dart';
export 'src/query/sql_string.dart';
export 'src/query/op.dart';
export 'src/formatter/formatter.dart';

// Schema builder
export 'src/schema/schema_builder.dart';
export 'src/schema/schema_compiler.dart';
export 'src/schema/table_builder.dart';
export 'src/schema/column_builder.dart';
export 'src/schema/schema_ast.dart';
export 'src/schema/json_schema_adapter.dart';

// Migration
export 'src/migration/migration.dart';
export 'src/migration/migration_source.dart';
export 'src/migration/migrator.dart';

// Transaction
export 'src/transaction/transaction.dart';

// Utilities
export 'src/util/knex_exception.dart';
export 'src/util/enums.dart';
export 'src/util/types.dart';
