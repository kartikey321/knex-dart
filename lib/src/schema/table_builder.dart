import '../client/client.dart';
import '../raw.dart';
import 'column_builder.dart';

/// Table builder for defining table schema through a callback.
///
/// Mirrors Knex.js TableBuilder. The callback receives this builder,
/// and each column type method creates a [ColumnBuilder] and records it.
///
/// Column types are dialect-aware: PG uses `serial`, `bytea`, `timestamptz`;
/// SQLite uses `integer`, `blob`, `datetime`; MySQL uses `int auto_increment`, etc.
///
/// JS Reference: lib/schema/tablebuilder.js
class TableBuilder {
  final Client client;
  final String method; // 'create', 'alter', 'createIfNot'
  final String tableName;

  /// Column definitions (grouping: 'columns')
  final List<ColumnBuilder> _columns = [];

  /// Alter-table operations (drop column, rename, add index, FK, etc.)
  final List<Map<String, dynamic>> _alterStatements = [];

  /// Table-level settings
  final Map<String, dynamic> _single = {};

  TableBuilder(this.client, this.method, this.tableName);

  /// Get the dialect for type mapping
  String get _dialect => client.driverName;

  // ============================================================================
  // DIALECT-AWARE TYPE RESOLUTION
  // ============================================================================

  String _incrementsType() {
    switch (_dialect) {
      case 'sqlite':
      case 'sqlite3':
        return 'integer primary key autoincrement';
      case 'mysql':
      case 'mysql2':
        return 'int unsigned auto_increment primary key';
      default: // pg
        return 'serial primary key';
    }
  }

  String _bigIncrementsType() {
    switch (_dialect) {
      case 'sqlite':
      case 'sqlite3':
        return 'integer primary key autoincrement';
      case 'mysql':
      case 'mysql2':
        return 'bigint unsigned auto_increment primary key';
      default: // pg
        return 'bigserial primary key';
    }
  }

  String _stringType(int length) {
    switch (_dialect) {
      case 'sqlite':
      case 'sqlite3':
        return 'varchar($length)';
      default:
        return 'varchar($length)';
    }
  }

  String _booleanType() {
    switch (_dialect) {
      case 'sqlite':
      case 'sqlite3':
        return 'boolean'; // SQLite stores as 0/1
      case 'mysql':
      case 'mysql2':
        return 'tinyint(1)';
      default:
        return 'boolean';
    }
  }

  String _datetimeType() {
    switch (_dialect) {
      case 'sqlite':
      case 'sqlite3':
        return 'datetime';
      case 'mysql':
      case 'mysql2':
        return 'datetime';
      default:
        return 'timestamptz';
    }
  }

  String _timestampType() => _datetimeType();

  String _binaryType() {
    switch (_dialect) {
      case 'sqlite':
      case 'sqlite3':
        return 'blob';
      case 'mysql':
      case 'mysql2':
        return 'blob';
      default:
        return 'bytea';
    }
  }

  String _uuidType() {
    switch (_dialect) {
      case 'sqlite':
      case 'sqlite3':
        return 'char(36)';
      case 'mysql':
      case 'mysql2':
        return 'char(36)';
      default:
        return 'uuid';
    }
  }

  String _jsonType() {
    switch (_dialect) {
      case 'sqlite':
      case 'sqlite3':
        return 'text'; // SQLite stores JSON as text
      case 'mysql':
      case 'mysql2':
        return 'json';
      default:
        return 'json';
    }
  }

  String _jsonbType() {
    switch (_dialect) {
      case 'sqlite':
      case 'sqlite3':
        return 'text';
      case 'mysql':
      case 'mysql2':
        return 'json'; // MySQL doesn't distinguish json/jsonb
      default:
        return 'jsonb';
    }
  }

  String _floatType() {
    switch (_dialect) {
      case 'sqlite':
      case 'sqlite3':
        return 'float';
      case 'mysql':
      case 'mysql2':
        return 'float';
      default:
        return 'real';
    }
  }

  String _enumType(String column, List<String> values) {
    switch (_dialect) {
      case 'mysql':
      case 'mysql2':
        final valuesStr = values.map((v) => "'$v'").join(', ');
        return 'enum($valuesStr)';
      default: // PG and SQLite use CHECK constraint
        final valuesStr = values.map((v) => "'$v'").join(', ');
        return 'text check ("$column" in ($valuesStr))';
    }
  }

  // ============================================================================
  // COLUMN TYPE METHODS — each creates a ColumnBuilder and records it
  // ============================================================================

  /// Auto-incrementing primary key
  ColumnBuilder increments(String column) {
    final cb = ColumnBuilder(column, _incrementsType());
    _columns.add(cb);
    return cb;
  }

  /// Integer column
  ColumnBuilder integer(String column) {
    final cb = ColumnBuilder(column, 'integer');
    _columns.add(cb);
    return cb;
  }

  /// Big integer column
  ColumnBuilder bigInteger(String column) {
    final cb = ColumnBuilder(column, 'bigint');
    _columns.add(cb);
    return cb;
  }

  /// Big incrementing column
  ColumnBuilder bigIncrements(String column) {
    final cb = ColumnBuilder(column, _bigIncrementsType());
    _columns.add(cb);
    return cb;
  }

  /// String / varchar column
  ColumnBuilder string(String column, [int length = 255]) {
    final cb = ColumnBuilder(column, _stringType(length));
    _columns.add(cb);
    return cb;
  }

  /// Text column
  ColumnBuilder text(String column) {
    final cb = ColumnBuilder(column, 'text');
    _columns.add(cb);
    return cb;
  }

  /// Boolean column
  ColumnBuilder boolean(String column) {
    final cb = ColumnBuilder(column, _booleanType());
    _columns.add(cb);
    return cb;
  }

  /// Date column
  ColumnBuilder date(String column) {
    final cb = ColumnBuilder(column, 'date');
    _columns.add(cb);
    return cb;
  }

  /// DateTime column
  ColumnBuilder datetime(String column) {
    final cb = ColumnBuilder(column, _datetimeType());
    _columns.add(cb);
    return cb;
  }

  /// Timestamp column
  ColumnBuilder timestamp(String column) {
    final cb = ColumnBuilder(column, _timestampType());
    _columns.add(cb);
    return cb;
  }

  /// Time column
  ColumnBuilder time(String column) {
    final cb = ColumnBuilder(column, 'time');
    _columns.add(cb);
    return cb;
  }

  /// Float column
  ColumnBuilder float(String column) {
    final cb = ColumnBuilder(column, _floatType());
    _columns.add(cb);
    return cb;
  }

  /// Double column
  ColumnBuilder doublePrecision(String column) {
    final cb = ColumnBuilder(column, 'double precision');
    _columns.add(cb);
    return cb;
  }

  /// Decimal column
  ColumnBuilder decimal(String column, [int precision = 8, int scale = 2]) {
    final cb = ColumnBuilder(column, 'decimal($precision, $scale)');
    _columns.add(cb);
    return cb;
  }

  /// Binary column
  ColumnBuilder binary(String column) {
    final cb = ColumnBuilder(column, _binaryType());
    _columns.add(cb);
    return cb;
  }

  /// JSON column
  ColumnBuilder json(String column) {
    final cb = ColumnBuilder(column, _jsonType());
    _columns.add(cb);
    return cb;
  }

  /// JSONB column (Postgres)
  ColumnBuilder jsonb(String column) {
    final cb = ColumnBuilder(column, _jsonbType());
    _columns.add(cb);
    return cb;
  }

  /// UUID column
  ColumnBuilder uuid(String column) {
    final cb = ColumnBuilder(column, _uuidType());
    _columns.add(cb);
    return cb;
  }

  /// Enum column
  ColumnBuilder enu(String column, List<String> values) {
    final cb = ColumnBuilder(column, _enumType(column, values));
    _columns.add(cb);
    return cb;
  }

  /// Specific type (raw SQL type)
  ColumnBuilder specificType(String column, String type) {
    final cb = ColumnBuilder(column, type);
    _columns.add(cb);
    return cb;
  }

  /// Timestamps helper — adds created_at and updated_at columns
  void timestamps([bool useTimestamps = false, bool defaultToNow = false]) {
    final type = _datetimeType();
    final createdAt = ColumnBuilder('created_at', type);
    final updatedAt = ColumnBuilder('updated_at', type);

    if (defaultToNow) {
      createdAt.notNullable().defaultTo(Raw(client).set('CURRENT_TIMESTAMP'));
      updatedAt.notNullable().defaultTo(Raw(client).set('CURRENT_TIMESTAMP'));
    }

    _columns.add(createdAt);
    _columns.add(updatedAt);
  }

  // ============================================================================
  // ALTER TABLE OPERATIONS
  // ============================================================================

  /// Drop a column
  void dropColumn(String column) {
    _alterStatements.add({
      'method': 'dropColumn',
      'args': [column],
    });
  }

  /// Drop multiple columns
  void dropColumns(List<String> columns) {
    for (final col in columns) {
      dropColumn(col);
    }
  }

  /// Rename a column
  void renameColumn(String from, String to) {
    _alterStatements.add({
      'method': 'renameColumn',
      'args': [from, to],
    });
  }

  /// Add index
  void index(dynamic columns, [String? indexName]) {
    _alterStatements.add({
      'method': 'index',
      'args': [columns, indexName],
    });
  }

  /// Add primary key constraint
  void primary(dynamic columns, [String? constraintName]) {
    _alterStatements.add({
      'method': 'primary',
      'args': [columns, constraintName],
    });
  }

  /// Add unique constraint
  void unique(dynamic columns, [String? constraintName]) {
    _alterStatements.add({
      'method': 'unique',
      'args': [columns, constraintName],
    });
  }

  /// Drop primary key
  void dropPrimary([String? constraintName]) {
    _alterStatements.add({
      'method': 'dropPrimary',
      'args': [constraintName],
    });
  }

  /// Drop unique constraint
  void dropUnique(dynamic columns, [String? constraintName]) {
    _alterStatements.add({
      'method': 'dropUnique',
      'args': [columns, constraintName],
    });
  }

  /// Drop foreign key
  void dropForeign(dynamic columns, [String? constraintName]) {
    _alterStatements.add({
      'method': 'dropForeign',
      'args': [columns, constraintName],
    });
  }

  /// Drop index
  void dropIndex(dynamic columns, [String? indexName]) {
    _alterStatements.add({
      'method': 'dropIndex',
      'args': [columns, indexName],
    });
  }

  /// Set a table comment
  void comment(String value) {
    _single['comment'] = value;
  }

  /// Drop timestamps columns (created_at, updated_at)
  void dropTimestamps([bool useCamelCase = false]) {
    final cols =
        useCamelCase ? ['createdAt', 'updatedAt'] : ['created_at', 'updated_at'];
    _alterStatements.add({
      'method': 'dropTimestamps',
      'args': cols,
    });
  }

  /// Set a column to nullable (ALTER TABLE ... ALTER COLUMN ... DROP NOT NULL)
  void setNullable(String column) {
    _alterStatements.add({
      'method': 'setNullable',
      'args': [column],
    });
  }

  /// Set a column to NOT NULL (ALTER TABLE ... ALTER COLUMN ... SET NOT NULL)
  void dropNullable(String column) {
    _alterStatements.add({
      'method': 'dropNullable',
      'args': [column],
    });
  }

  /// Define a foreign key constraint using a fluent builder.
  /// Returns a [ForeignBuilder] for chaining references/onDelete/onUpdate.
  ForeignBuilder foreign(String column) {
    final foreignData = <String, dynamic>{'column': column};
    _alterStatements.add({
      'method': 'foreign',
      'args': [foreignData],
    });
    return ForeignBuilder(foreignData);
  }

  // ============================================================================
  // ACCESSORS
  // ============================================================================

  List<ColumnBuilder> get columns => _columns;
  List<Map<String, dynamic>> get alterStatements => _alterStatements;
  Map<String, dynamic> get single => _single;
}

/// Fluent builder for foreign key constraints on TableBuilder.
///
/// Usage: `table.foreign('user_id').references('id').inTable('users').onDelete('CASCADE')`
class ForeignBuilder {
  final Map<String, dynamic> _data;

  ForeignBuilder(this._data);

  ForeignBuilder references(String column) {
    _data['references'] = column;
    return this;
  }

  ForeignBuilder inTable(String table) {
    _data['inTable'] = table;
    return this;
  }

  ForeignBuilder onDelete(String action) {
    _data['onDelete'] = action.toUpperCase();
    return this;
  }

  ForeignBuilder onUpdate(String action) {
    _data['onUpdate'] = action.toUpperCase();
    return this;
  }
}
