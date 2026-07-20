import '../client/client.dart';
import '../query/query_builder.dart';
import '../query/sql_string.dart';
import '../raw.dart';
import 'schema_builder.dart';
import 'table_builder.dart';

/// Compiles SchemaBuilder DDL operations into SQL statements.
///
class SchemaCompiler {
  final Client client;
  final SchemaBuilder builder;
  final List<Map<String, dynamic>> sequence = [];

  SchemaCompiler(this.client, this.builder);

  /// Helper to wrap identifiers with the correct dialect quotes
  String _wrap(String value) => client.formatter(builder).wrapString(value);

  /// Compile all DDL operations recorded in the SchemaBuilder.
  List<Map<String, dynamic>> toSQL() {
    for (final item in builder.sequence) {
      final method = item['method'] as String;
      final args = item['args'] as List;

      switch (method) {
        case 'createTable':
          _createTable(
            args[0] as String,
            args[1] as void Function(TableBuilder),
          );
          break;
        case 'createTableIfNotExists':
          _createTableIfNotExists(
            args[0] as String,
            args[1] as void Function(TableBuilder),
          );
          break;
        case 'createTableLike':
          _createTableLike(
            args[0] as String,
            args[1] as String,
            args.length > 2 ? args[2] as void Function(TableBuilder) : null,
          );
          break;
        case 'createView':
          _createView(args[0] as String, args[1]);
          break;
        case 'createViewOrReplace':
          _createViewOrReplace(args[0] as String, args[1]);
          break;
        case 'createMaterializedView':
          _createMaterializedView(args[0] as String, args[1]);
          break;
        case 'refreshMaterializedView':
          _refreshMaterializedView(args[0] as String, args[1] as bool);
          break;
        case 'dropView':
          _dropView(args[0] as String);
          break;
        case 'dropViewIfExists':
          _dropViewIfExists(args[0] as String);
          break;
        case 'dropMaterializedView':
          _dropMaterializedView(args[0] as String);
          break;
        case 'dropMaterializedViewIfExists':
          _dropMaterializedViewIfExists(args[0] as String);
          break;
        case 'createSchema':
          _createSchema(args[0] as String);
          break;
        case 'createSchemaIfNotExists':
          _createSchemaIfNotExists(args[0] as String);
          break;
        case 'dropSchema':
          _dropSchema(args[0] as String, args[1] as bool);
          break;
        case 'dropSchemaIfExists':
          _dropSchemaIfExists(args[0] as String, args[1] as bool);
          break;
        case 'createExtension':
          _createExtension(args[0] as String);
          break;
        case 'createExtensionIfNotExists':
          _createExtensionIfNotExists(args[0] as String);
          break;
        case 'dropExtension':
          _dropExtension(args[0] as String);
          break;
        case 'dropExtensionIfExists':
          _dropExtensionIfExists(args[0] as String);
          break;
        case 'dropTable':
          _dropTable(args[0] as String);
          break;
        case 'dropTableIfExists':
          _dropTableIfExists(args[0] as String);
          break;
        case 'renameTable':
          _renameTable(args[0] as String, args[1] as String);
          break;
        case 'renameView':
          _renameView(args[0] as String, args[1] as String);
          break;
        case 'alterTable':
          _alterTable(
            args[0] as String,
            args[1] as void Function(TableBuilder),
          );
          break;
        case 'alterView':
          _alterView(args[0] as String, args[1]);
          break;
        case 'raw':
          _raw(args[0] as String, List<dynamic>.from(args[1] as List));
          break;
      }
    }
    return sequence;
  }

  /// Prefix table name with schema if set
  String _prefixedTableName(String table) {
    if (builder.schema != null) {
      return '${_wrap(builder.schema!)}.${_wrap(table)}';
    }
    return _wrap(table);
  }

  /// Create a table
  void _createTable(String tableName, void Function(TableBuilder) callback) {
    _buildCreateTable(tableName, callback, 'create table');
  }

  /// Create table if not exists
  void _createTableIfNotExists(
    String tableName,
    void Function(TableBuilder) callback,
  ) {
    _buildCreateTable(tableName, callback, 'create table if not exists');
  }

  /// Create a table with schema copied from another table.
  void _createTableLike(
    String tableName,
    String tableNameLike, [
    void Function(TableBuilder)? callback,
  ]) {
    final tableRef = _prefixedTableName(tableName);
    final sourceRef = _prefixedTableName(tableNameLike);
    final driver = client.driverName.toLowerCase();

    if (_isPostgresLike(driver)) {
      if (callback == null) {
        _pushQuery('create table $tableRef (like $sourceRef including all)');
        return;
      }

      final tb = TableBuilder(client, 'create', tableName);
      callback(tb);
      final extraColumns = tb.columns
          .map((c) => c.toSQL(dialect: client.driverName, wrap: _wrap))
          .toList();
      final extraSql = extraColumns.isEmpty
          ? ''
          : ', ${extraColumns.join(', ')}';

      _pushQuery(
        'create table $tableRef (like $sourceRef including all$extraSql)',
      );
      _pushDeferredConstraintsForTable(tableName, tableRef, tb);
      return;
    }
    if (_isMySqlLike(driver)) {
      _pushQuery('create table $tableRef like $sourceRef');
      if (callback != null) {
        _alterTable(tableName, callback);
      }
      return;
    }
    if (_isSqliteLike(driver) || driver == 'duckdb') {
      _pushQuery(
        'create table $tableRef as select * from $sourceRef where 0=1',
      );
      if (callback != null) {
        _alterTable(tableName, callback);
      }
      return;
    }
    if (driver == 'mssql') {
      _pushQuery('SELECT * INTO $tableRef FROM $sourceRef WHERE 0=1');
      if (callback != null) {
        _alterTable(tableName, callback);
      }
      return;
    }
    throw UnsupportedError(
      'createTableLike is not supported for dialect "${client.driverName}"',
    );
  }

  void _createView(String viewName, dynamic definition) {
    final compiled = _compileSelectable(definition, operation: 'createView');
    _pushQuery(
      'create view ${_prefixedTableName(viewName)} as ${compiled.sql}',
      compiled.bindings,
    );
  }

  void _createViewOrReplace(String viewName, dynamic definition) {
    final compiled = _compileSelectable(
      definition,
      operation: 'createViewOrReplace',
    );
    final driver = client.driverName.toLowerCase();
    if (_isSqliteLike(driver)) {
      _pushQuery('drop view if exists ${_prefixedTableName(viewName)}');
      _pushQuery(
        'create view ${_prefixedTableName(viewName)} as ${compiled.sql}',
        compiled.bindings,
      );
      return;
    }
    _pushQuery(
      'create or replace view ${_prefixedTableName(viewName)} as ${compiled.sql}',
      compiled.bindings,
    );
  }

  void _createMaterializedView(String viewName, dynamic definition) {
    _ensurePostgresOnly('createMaterializedView');
    final compiled = _compileSelectable(
      definition,
      operation: 'createMaterializedView',
    );
    _pushQuery(
      'create materialized view ${_prefixedTableName(viewName)} as ${compiled.sql}',
      compiled.bindings,
    );
  }

  void _refreshMaterializedView(String viewName, bool concurrently) {
    _ensurePostgresOnly('refreshMaterializedView');
    _pushQuery(
      'refresh materialized view${concurrently ? ' concurrently' : ''} ${_prefixedTableName(viewName)}',
    );
  }

  void _dropView(String viewName) {
    _pushQuery('drop view ${_prefixedTableName(viewName)}');
  }

  void _dropViewIfExists(String viewName) {
    final driver = client.driverName.toLowerCase();
    if (driver == 'mssql') {
      final name = _prefixedTableName(viewName);
      _pushQuery("if object_id('$name', 'V') is not null DROP VIEW $name");
      return;
    }
    _pushQuery('drop view if exists ${_prefixedTableName(viewName)}');
  }

  void _dropMaterializedView(String viewName) {
    _ensurePostgresOnly('dropMaterializedView');
    _pushQuery('drop materialized view ${_prefixedTableName(viewName)}');
  }

  void _dropMaterializedViewIfExists(String viewName) {
    _ensurePostgresOnly('dropMaterializedViewIfExists');
    _pushQuery(
      'drop materialized view if exists ${_prefixedTableName(viewName)}',
    );
  }

  void _createSchema(String schemaName) {
    _ensurePostgresOnly('createSchema');
    _pushQuery('create schema ${_wrap(schemaName)}');
  }

  void _createSchemaIfNotExists(String schemaName) {
    _ensurePostgresOnly('createSchemaIfNotExists');
    _pushQuery('create schema if not exists ${_wrap(schemaName)}');
  }

  void _dropSchema(String schemaName, bool cascade) {
    _ensurePostgresOnly('dropSchema');
    _pushQuery('drop schema ${_wrap(schemaName)}${cascade ? ' cascade' : ''}');
  }

  void _dropSchemaIfExists(String schemaName, bool cascade) {
    _ensurePostgresOnly('dropSchemaIfExists');
    _pushQuery(
      'drop schema if exists ${_wrap(schemaName)}${cascade ? ' cascade' : ''}',
    );
  }

  void _createExtension(String extensionName) {
    _ensurePostgresOnly('createExtension');
    _pushQuery('create extension ${_wrap(extensionName)}');
  }

  void _createExtensionIfNotExists(String extensionName) {
    _ensurePostgresOnly('createExtensionIfNotExists');
    _pushQuery('create extension if not exists ${_wrap(extensionName)}');
  }

  void _dropExtension(String extensionName) {
    _ensurePostgresOnly('dropExtension');
    _pushQuery('drop extension ${_wrap(extensionName)}');
  }

  void _dropExtensionIfExists(String extensionName) {
    _ensurePostgresOnly('dropExtensionIfExists');
    _pushQuery('drop extension if exists ${_wrap(extensionName)}');
  }

  void _buildCreateTable(
    String tableName,
    void Function(TableBuilder) callback,
    String prefix,
  ) {
    final tb = TableBuilder(client, 'create', tableName);
    callback(tb);

    // Build column definitions
    final columnDefs = <String>[];
    final deferredConstraints = <Map<String, dynamic>>[];

    for (final col in tb.columns) {
      columnDefs.add(col.toSQL(dialect: client.driverName, wrap: _wrap));

      // Collect unique/FK constraints for separate ALTER TABLE statements
      if (col.isUnique) {
        deferredConstraints.add({
          'type': 'unique',
          'column': col.name,
          'table': tableName,
        });
      }
      if (col.referencesColumn != null && col.referencesTable != null) {
        deferredConstraints.add({
          'type': 'foreign',
          'column': col.name,
          'table': tableName,
          'referencesColumn': col.referencesColumn,
          'referencesTable': col.referencesTable,
          'onDelete': col.onDeleteAction,
          'onUpdate': col.onUpdateAction,
        });
      }
    }

    // Fold a table-level PRIMARY KEY inline into the CREATE TABLE (knex.js
    // parity). This is required for SQLite, which cannot add a primary key via
    // ALTER TABLE after creation; it is also valid for Postgres/MySQL.
    var primaryInline = '';
    for (final stmt in tb.alterStatements) {
      if (stmt['method'] == 'primary') {
        final args = stmt['args'] as List;
        final cols = args[0] is List ? args[0] as List : [args[0]];
        final colStr = cols.map((c) => _wrap(c)).join(', ');
        final constraintName = args.length > 1 && args[1] != null
            ? args[1] as String
            : '${tableName}_pkey';
        primaryInline =
            ', constraint ${_wrap(constraintName)} primary key ($colStr)';
        break; // a table has at most one primary key
      }
    }

    // Main CREATE TABLE statement
    final tableRef = _prefixedTableName(tableName);
    final sql = '$prefix $tableRef (${columnDefs.join(', ')}$primaryInline)';
    _pushQuery(sql);

    _pushDeferredConstraintsForTable(
      tableName,
      tableRef,
      tb,
      precomputed: deferredConstraints,
      skipPrimary: true,
    );
  }

  /// Drop a table
  void _dropTable(String tableName) {
    _pushQuery('drop table ${_prefixedTableName(tableName)}');
  }

  /// Drop a table if it exists
  void _dropTableIfExists(String tableName) {
    final driver = client.driverName.toLowerCase();
    if (driver == 'mssql') {
      final name = _prefixedTableName(tableName);
      _pushQuery("if object_id('$name', 'U') is not null DROP TABLE $name");
      return;
    }
    _pushQuery('drop table if exists ${_prefixedTableName(tableName)}');
  }

  /// Rename a table
  void _renameTable(String from, String to) {
    final driver = client.driverName.toLowerCase();
    if (_isMySqlLike(driver)) {
      _pushQuery('rename table ${_wrap(from)} to ${_wrap(to)}');
      return;
    }
    if (driver == 'mssql') {
      final fromName = builder.schema != null
          ? '${builder.schema}.$from'
          : from;
      _pushQuery('exec sp_rename ?, ?', [fromName, to]);
      return;
    }
    _pushQuery(
      'alter table ${_prefixedTableName(from)} rename to ${_wrap(to)}',
    );
  }

  /// Rename a view.
  void _renameView(String from, String to) {
    final driver = client.driverName.toLowerCase();
    if (_isPostgresLike(driver)) {
      _pushQuery(
        'alter view ${_prefixedTableName(from)} rename to ${_wrap(to)}',
      );
      return;
    }
    if (_isMySqlLike(driver)) {
      _pushQuery('rename table ${_wrap(from)} to ${_wrap(to)}');
      return;
    }
    if (driver == 'mssql') {
      final fromName = builder.schema != null
          ? '${builder.schema}.$from'
          : from;
      _pushQuery('exec sp_rename ?, ?', [fromName, to]);
      return;
    }
    throw UnsupportedError(
      'renameView is not supported for dialect "${client.driverName}"',
    );
  }

  /// Alter a table
  void _alterTable(String tableName, void Function(TableBuilder) callback) {
    final driver = client.driverName.toLowerCase();
    final tb = TableBuilder(client, 'alter', tableName);
    callback(tb);
    final tableRef = _prefixedTableName(tableName);

    // Handle added columns
    for (final col in tb.columns) {
      final addKeyword = driver == 'mssql' ? 'add' : 'add column';
      _pushQuery(
        'alter table $tableRef $addKeyword ${col.toSQL(dialect: client.driverName, wrap: _wrap)}',
      );
    }

    // Handle alter statements
    for (final stmt in tb.alterStatements) {
      final method = stmt['method'] as String;
      final args = stmt['args'] as List;

      switch (method) {
        case 'dropColumn':
          _pushQuery('alter table $tableRef drop column ${_wrap(args[0])}');
          break;
        case 'renameColumn':
          if (client.driverName == 'mssql') {
            // MSSQL uses sp_rename with bindings to avoid injection.
            // Object name includes schema prefix when set (matches _renameTable).
            final objectName = builder.schema != null
                ? '${builder.schema}.$tableName.${args[0]}'
                : '$tableName.${args[0]}';
            _pushQuery('exec sp_rename ?, ?, ?', [objectName, args[1], 'COLUMN']);
          } else if (client.driverName == 'mysql' ||
              client.driverName == 'mysql2' ||
              client.driverName == 'mariadb') {
            // MySQL 8+ / MariaDB require the COLUMN keyword.
            _pushQuery(
              'alter table $tableRef rename column ${_wrap(args[0])} to ${_wrap(args[1])}',
            );
          } else {
            // PostgreSQL, SQLite 3.25+, DuckDB — no COLUMN keyword needed.
            _pushQuery(
              'alter table $tableRef rename ${_wrap(args[0])} to ${_wrap(args[1])}',
            );
          }
          break;
        case 'unique':
          final cols = args[0] is List ? args[0] as List : [args[0]];
          final colStr = cols.map((c) => _wrap(c)).join(', ');
          final constraintName = args.length > 1 && args[1] != null
              ? args[1] as String
              : '${tableName}_${cols.join('_')}_unique';
          if (client.driverName == 'sqlite' || client.driverName == 'sqlite3') {
            _pushQuery(
              'create unique index ${_wrap(constraintName)} on $tableRef ($colStr)',
            );
          } else {
            _pushQuery(
              'alter table $tableRef add constraint ${_wrap(constraintName)} unique ($colStr)',
            );
          }
          break;
        case 'index':
          final cols = args[0] is List ? args[0] as List : [args[0]];
          final colStr = cols.map((c) => _wrap(c)).join(', ');
          final indexName = args.length > 1 && args[1] != null
              ? args[1]
              : '${tableName}_${cols.join('_')}_index';
          _pushQuery('create index ${_wrap(indexName)} on $tableRef ($colStr)');
          break;
        case 'fulltext':
          final cols = args[0] is List ? args[0] as List : [args[0]];
          final colStr = cols.map((c) => _wrap(c)).join(', ');
          final indexName = args.length > 1 && args[1] != null ? args[1] : null;
          if (client.driverName == 'mysql' ||
              client.driverName == 'mysql2' ||
              client.driverName == 'mariadb') {
            final indexPart = indexName != null ? ' ${_wrap(indexName)}' : '';
            _pushQuery(
              'alter table $tableRef add fulltext$indexPart ($colStr)',
            );
          } else {
            throw UnsupportedError(
              'fulltext index is only supported for mysql/mariadb dialects',
            );
          }
          break;
        case 'dropIndex':
          // When no explicit name is given, derive it from the columns using
          // the same scheme as index creation (knex.js parity), instead of
          // silently doing nothing.
          final cols = args[0] is List ? args[0] as List : [args[0]];
          final indexName = args.length > 1 && args[1] != null
              ? args[1]
              : '${tableName}_${cols.join('_')}_index';
          if (client.driverName == 'mysql' ||
              client.driverName == 'mysql2' ||
              client.driverName == 'mariadb') {
            // MySQL requires ON <table> to identify the index.
            _pushQuery('drop index ${_wrap(indexName)} on $tableRef');
          } else {
            _pushQuery('drop index ${_wrap(indexName)}');
          }
          break;
        case 'dropForeign':
          final cols = args[0] is List ? args[0] as List : [args[0]];
          final constraintName = args.length > 1 && args[1] != null
              ? args[1]
              : '${tableName}_${cols.join('_')}_foreign';
          if (client.driverName == 'mysql' ||
              client.driverName == 'mysql2' ||
              client.driverName == 'mariadb') {
            _pushQuery(
              'alter table $tableRef drop foreign key ${_wrap(constraintName)}',
            );
          } else {
            _pushQuery(
              'alter table $tableRef drop constraint ${_wrap(constraintName)}',
            );
          }
          break;
        case 'foreign':
          // Fluent foreign key from table.foreign('col').references('id').inTable('t')
          final data = args[0] as Map<String, dynamic>;
          final col = data['column'];
          final refTable = data['inTable'];
          final refCol = data['references'];
          if (refTable != null && refCol != null) {
            final constraintName = '${tableName}_${col}_foreign';
            var fk =
                'alter table $tableRef add constraint ${_wrap(constraintName)} foreign key (${_wrap(col)}) references ${_wrap(refTable)} (${_wrap(refCol)})';
            if (data['onDelete'] != null) {
              fk += ' on delete ${data['onDelete']}';
            }
            if (data['onUpdate'] != null) {
              fk += ' on update ${data['onUpdate']}';
            }
            _pushQuery(fk);
          }
          break;
        case 'dropTimestamps':
          // JS PG: alter table "t" drop column "created_at", drop column "updated_at"
          // JS MySQL: alter table `t` drop `created_at`, drop `updated_at`
          if (client.driverName == 'mysql' || client.driverName == 'mysql2') {
            final dropParts = args
                .map((col) => 'drop ${_wrap(col)}')
                .join(', ');
            _pushQuery('alter table $tableRef $dropParts');
          } else {
            final dropParts = args
                .map((col) => 'drop column ${_wrap(col)}')
                .join(', ');
            _pushQuery('alter table $tableRef $dropParts');
          }
          break;
        case 'primary':
          final cols = args[0] is List ? args[0] as List : [args[0]];
          final colStr = cols.map((c) => _wrap(c)).join(', ');
          final constraintName = args.length > 1 && args[1] != null
              ? args[1] as String
              : '${tableName}_pkey';
          _pushQuery(
            'alter table $tableRef add constraint ${_wrap(constraintName)} primary key ($colStr)',
          );
          break;
        case 'dropPrimary':
          if (client.driverName == 'mysql' ||
              client.driverName == 'mysql2' ||
              client.driverName == 'mariadb') {
            _pushQuery('alter table $tableRef drop primary key');
          } else {
            final constraintName =
                args.isNotEmpty && args[0] != null ? args[0] : '${tableName}_pkey';
            _pushQuery(
              'alter table $tableRef drop constraint ${_wrap(constraintName)}',
            );
          }
          break;
        case 'dropUnique':
          final cols = args[0] is List ? args[0] as List : [args[0]];
          final constraintName = args.length > 1 && args[1] != null
              ? args[1]
              : '${tableName}_${(cols).join('_')}_unique';
          if (client.driverName == 'sqlite' || client.driverName == 'sqlite3') {
            _pushQuery('drop index ${_wrap(constraintName)}');
          } else if (client.driverName == 'mysql' ||
              client.driverName == 'mysql2' ||
              client.driverName == 'mariadb') {
            _pushQuery(
              'alter table $tableRef drop index ${_wrap(constraintName)}',
            );
          } else {
            _pushQuery(
              'alter table $tableRef drop constraint ${_wrap(constraintName)}',
            );
          }
          break;
        case 'setNullable':
          if (client.driverName == 'sqlite' || client.driverName == 'sqlite3') {
            throw UnsupportedError(
              'setNullable is not supported for SQLite — recreate the table instead',
            );
          }
          _pushQuery(
            'alter table $tableRef alter column ${_wrap(args[0])} drop not null',
          );
          break;
        case 'dropNullable':
          if (client.driverName == 'sqlite' || client.driverName == 'sqlite3') {
            throw UnsupportedError(
              'dropNullable is not supported for SQLite — recreate the table instead',
            );
          }
          _pushQuery(
            'alter table $tableRef alter column ${_wrap(args[0])} set not null',
          );
          break;
      }
    }
  }

  /// Alter a view definition (compiled as CREATE OR REPLACE VIEW).
  void _alterView(String viewName, dynamic definition) {
    final compiled = _compileSelectable(definition, operation: 'alterView');
    final driver = client.driverName.toLowerCase();
    if (_isSqliteLike(driver)) {
      _pushQuery('drop view if exists ${_prefixedTableName(viewName)}');
      _pushQuery(
        'create view ${_prefixedTableName(viewName)} as ${compiled.sql}',
        compiled.bindings,
      );
      return;
    }
    _pushQuery(
      'create or replace view ${_prefixedTableName(viewName)} as ${compiled.sql}',
      compiled.bindings,
    );
  }

  void _raw(String sql, List<dynamic> bindings) {
    _pushQuery(sql, bindings);
  }

  ({String sql, List<dynamic> bindings}) _compileSelectable(
    dynamic value, {
    required String operation,
  }) {
    if (value is String) {
      return (sql: value, bindings: const []);
    }
    if (value is Raw) {
      final sql = value.toSQL();
      return (sql: sql.sql, bindings: List<dynamic>.from(sql.bindings));
    }
    if (value is QueryBuilder) {
      final sql = value.toSQL();
      return (sql: sql.sql, bindings: List<dynamic>.from(sql.bindings));
    }
    if (value is SqlString) {
      return (sql: value.sql, bindings: List<dynamic>.from(value.bindings));
    }
    throw ArgumentError(
      '$operation requires a SQL definition as String, Raw, QueryBuilder, or SqlString',
    );
  }

  bool _isPostgresLike(String driver) =>
      driver == 'pg' ||
      driver == 'postgres' ||
      driver == 'postgresql' ||
      driver == 'cockroachdb' ||
      driver == 'redshift';

  bool _isMySqlLike(String driver) =>
      driver == 'mysql' || driver == 'mysql2' || driver == 'mariadb';

  bool _isSqliteLike(String driver) =>
      driver == 'sqlite' ||
      driver == 'sqlite3' ||
      driver == 'turso' ||
      driver == 'd1';

  void _pushDeferredConstraintsForTable(
    String tableName,
    String tableRef,
    TableBuilder tb, {
    List<Map<String, dynamic>>? precomputed,
    bool skipPrimary = false,
  }) {
    final deferredConstraints = precomputed ?? <Map<String, dynamic>>[];
    if (precomputed == null) {
      for (final col in tb.columns) {
        if (col.isUnique) {
          deferredConstraints.add({
            'type': 'unique',
            'column': col.name,
            'table': tableName,
          });
        }
        if (col.referencesColumn != null && col.referencesTable != null) {
          deferredConstraints.add({
            'type': 'foreign',
            'column': col.name,
            'table': tableName,
            'referencesColumn': col.referencesColumn,
            'referencesTable': col.referencesTable,
            'onDelete': col.onDeleteAction,
            'onUpdate': col.onUpdateAction,
          });
        }
      }
    }

    for (final constraint in deferredConstraints) {
      if (constraint['type'] == 'unique') {
        final col = constraint['column'];
        final constraintName = '${tableName}_${col}_unique';
        if (client.driverName == 'sqlite' || client.driverName == 'sqlite3') {
          _pushQuery(
            'create unique index ${_wrap(constraintName)} on $tableRef (${_wrap(col)})',
          );
        } else {
          _pushQuery(
            'alter table $tableRef add constraint ${_wrap(constraintName)} unique (${_wrap(col)})',
          );
        }
      } else if (constraint['type'] == 'foreign') {
        if (client.driverName == 'sqlite' || client.driverName == 'sqlite3') {
          // SQLite does not support ALTER TABLE ADD CONSTRAINT for foreign keys
          continue;
        }
        final col = constraint['column'];
        final refTable = constraint['referencesTable'];
        final refCol = constraint['referencesColumn'];
        final constraintName = '${tableName}_${col}_foreign';
        var fk =
            'alter table $tableRef add constraint ${_wrap(constraintName)} foreign key (${_wrap(col)}) references ${_wrap(refTable)} (${_wrap(refCol)})';
        if (constraint['onDelete'] != null) {
          fk += ' on delete ${constraint['onDelete']}';
        }
        if (constraint['onUpdate'] != null) {
          fk += ' on update ${constraint['onUpdate']}';
        }
        _pushQuery(fk);
      }
    }

    for (final stmt in tb.alterStatements) {
      final method = stmt['method'] as String;
      final args = stmt['args'] as List;

      if (method == 'foreign') {
        final data = args[0] as Map<String, dynamic>;
        final col = data['column'];
        final refTable = data['inTable'];
        final refCol = data['references'];
        if (refTable != null && refCol != null) {
          final constraintName = '${tableName}_${col}_foreign';
          var fk =
              'alter table $tableRef add constraint ${_wrap(constraintName)} foreign key (${_wrap(col)}) references ${_wrap(refTable)} (${_wrap(refCol)})';
          if (data['onDelete'] != null) {
            fk += ' on delete ${data['onDelete']}';
          }
          if (data['onUpdate'] != null) {
            fk += ' on update ${data['onUpdate']}';
          }
          _pushQuery(fk);
        }
      } else if (method == 'index') {
        final cols = args[0] is List ? args[0] as List : [args[0]];
        final colStr = cols.map((c) => _wrap(c)).join(', ');
        final indexName = args.length > 1 && args[1] != null
            ? args[1] as String
            : '${tableName}_${cols.join('_')}_index';
        _pushQuery('create index ${_wrap(indexName)} on $tableRef ($colStr)');
      } else if (method == 'unique') {
        final cols = args[0] is List ? args[0] as List : [args[0]];
        final colStr = cols.map((c) => _wrap(c)).join(', ');
        final constraintName = args.length > 1 && args[1] != null
            ? args[1] as String
            : '${tableName}_${cols.join('_')}_unique';
        if (client.driverName == 'sqlite' || client.driverName == 'sqlite3') {
          _pushQuery(
            'create unique index ${_wrap(constraintName)} on $tableRef ($colStr)',
          );
        } else {
          _pushQuery(
            'alter table $tableRef add constraint ${_wrap(constraintName)} unique ($colStr)',
          );
        }
      } else if (method == 'primary' && !skipPrimary) {
        // Only reached for create-table-like paths (Postgres) that cannot fold
        // the key inline; normal createTable folds it into the CREATE statement.
        final cols = args[0] is List ? args[0] as List : [args[0]];
        final colStr = cols.map((c) => _wrap(c)).join(', ');
        final constraintName = args.length > 1 && args[1] != null
            ? args[1] as String
            : '${tableName}_pkey';
        _pushQuery(
          'alter table $tableRef add constraint ${_wrap(constraintName)} primary key ($colStr)',
        );
      }
    }
  }

  void _ensurePostgresOnly(String operation) {
    final driver = client.driverName.toLowerCase();
    if (!_isPostgresLike(driver)) {
      throw UnsupportedError(
        '$operation is not supported for dialect "${client.driverName}"',
      );
    }
  }

  void _pushQuery(String sql, [List<dynamic> bindings = const []]) {
    sequence.add({'sql': sql, 'bindings': bindings});
  }
}
