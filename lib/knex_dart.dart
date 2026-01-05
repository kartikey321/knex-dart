/// Knex Dart - SQL Query Builder
///
/// A batteries-included SQL query builder for Dart inspired by Knex.js.
/// Supports multiple database dialects including PostgreSQL, MySQL, SQLite, and more.
///
/// Example:
/// ```dart
/// final knex = Knex(KnexConfig(
///   client: 'postgres',
///   connection: {
///     'host': 'localhost',
///     'database': 'myapp',
///     'user': 'user',
///     'password': 'password',
///   },
/// ));
///
/// // Query
/// final users = await knex('users')
///   .where('active', true)
///   .select(['id', 'name', 'email']);
///
/// // Schema
/// await knex.schema.createTable('posts', (table) {
///   table.increments('id');
///   table.string('title').notNullable();
///   table.text('content');
///   table.integer('user_id').references('id').inTable('users');
///   table.timestamps();
/// });
/// ```

// Core exports
export 'src/knex.dart';
export 'src/client/client.dart';
export 'src/client/knex_config.dart';

// Query builder
export 'src/query/query_builder.dart';
export 'src/query/join_clause.dart';
export 'src/query/sql_string.dart';

// Raw and Ref
export 'src/raw.dart';
export 'src/ref.dart';

// Schema builder
export 'src/schema/schema_builder.dart';
export 'src/schema/table_builder.dart';
export 'src/schema/column_builder.dart';

// Migration
export 'src/migration/migration.dart';
export 'src/migration/migrator.dart';

// Transaction
export 'src/transaction/transaction.dart';

// Utilities
export 'src/util/knex_exception.dart';
export 'src/util/enums.dart';
export 'src/util/types.dart';
