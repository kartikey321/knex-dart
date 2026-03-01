import '../client/client.dart';
import 'schema_builder.dart';
import 'table_builder.dart';

/// Compiles SchemaBuilder DDL operations into SQL statements.
///
/// JS Reference: lib/schema/compiler.js
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
        case 'dropTable':
          _dropTable(args[0] as String);
          break;
        case 'dropTableIfExists':
          _dropTableIfExists(args[0] as String);
          break;
        case 'renameTable':
          _renameTable(args[0] as String, args[1] as String);
          break;
        case 'alterTable':
          _alterTable(
            args[0] as String,
            args[1] as void Function(TableBuilder),
          );
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

    // Main CREATE TABLE statement
    final tableRef = _prefixedTableName(tableName);
    final sql = '$prefix $tableRef (${columnDefs.join(', ')})';
    _pushQuery(sql);

    // Deferred constraints (separate ALTER TABLE statements, matching Knex.js)
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
          // Knex.js either puts them inline during CREATE TABLE or warns
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

    // Also process table-level foreign() calls from alterStatements
    for (final stmt in tb.alterStatements) {
      if (stmt['method'] == 'foreign') {
        final data = (stmt['args'] as List)[0] as Map<String, dynamic>;
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
      }
    }
  }

  /// Drop a table
  void _dropTable(String tableName) {
    _pushQuery('drop table ${_prefixedTableName(tableName)}');
  }

  /// Drop a table if it exists
  void _dropTableIfExists(String tableName) {
    _pushQuery('drop table if exists ${_prefixedTableName(tableName)}');
  }

  /// Rename a table
  void _renameTable(String from, String to) {
    _pushQuery(
      'alter table ${_prefixedTableName(from)} rename to ${_wrap(to)}',
    );
  }

  /// Alter a table
  void _alterTable(String tableName, void Function(TableBuilder) callback) {
    final tb = TableBuilder(client, 'alter', tableName);
    callback(tb);
    final tableRef = _prefixedTableName(tableName);

    // Handle added columns
    for (final col in tb.columns) {
      _pushQuery(
        'alter table $tableRef add column ${col.toSQL(dialect: client.driverName, wrap: _wrap)}',
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
          // JS PG: alter table "t" rename "from" to "to"
          _pushQuery(
            'alter table $tableRef rename ${_wrap(args[0])} to ${_wrap(args[1])}',
          );
          break;
        case 'unique':
          final cols = args[0] is List ? args[0] as List : [args[0]];
          final colStr = cols.map((c) => _wrap(c)).join(', ');
          final constraintName = '${tableName}_${cols.join('_')}_unique';
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
        case 'dropIndex':
          final indexName = args.length > 1 && args[1] != null ? args[1] : null;
          if (indexName != null) {
            _pushQuery('drop index ${_wrap(indexName)}');
          }
          break;
        case 'dropForeign':
          final cols = args[0] is List ? args[0] as List : [args[0]];
          final constraintName = args.length > 1 && args[1] != null
              ? args[1]
              : '${tableName}_${cols.join('_')}_foreign';
          _pushQuery(
            'alter table $tableRef drop constraint ${_wrap(constraintName)}',
          );
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
        case 'setNullable':
          // JS PG: alter table "t" alter column "col" drop not null
          _pushQuery(
            'alter table $tableRef alter column ${_wrap(args[0])} drop not null',
          );
          break;
        case 'dropNullable':
          // JS PG: alter table "t" alter column "col" set not null
          _pushQuery(
            'alter table $tableRef alter column ${_wrap(args[0])} set not null',
          );
          break;
      }
    }
  }

  void _pushQuery(String sql, [List<dynamic> bindings = const []]) {
    sequence.add({'sql': sql, 'bindings': bindings});
  }
}
