import '../client/client.dart';
import '../raw.dart';
import 'column_builder.dart';

/// Table builder for defining table schema through a callback.
///
/// and each column type method creates a [ColumnBuilder] and records it.
///
/// Column types are dialect-aware: PG uses `serial`, `bytea`, `timestamptz`;
/// SQLite uses `integer`, `blob`, `datetime`; MySQL uses `int auto_increment`, etc.
///
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

  /// Get the dialect for type mapping.
  ///
  /// Normalizes sqlite-family drivers (`sqlite3`, `turso`, `d1` — all
  /// wire-compatible with SQLite) to `'sqlite'` so every `case 'sqlite':`
  /// below covers all three without repeating the case list. Previously only
  /// `sqlite`/`sqlite3` were handled here, so turso/d1 silently fell through
  /// to the Postgres-shaped `default` branch for every column type.
  String get _dialect {
    final driver = client.driverName;
    if (driver == 'turso' || driver == 'd1' || driver == 'sqlite3') {
      return 'sqlite';
    }
    return driver;
  }

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
      case 'redshift':
        // Redshift has no SERIAL type; IDENTITY is the equivalent.
        return 'integer identity(1,1) primary key not null';
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
      case 'redshift':
        return 'bigint identity(1,1) primary key not null';
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

  String _timestampType([bool useTz = true]) {
    switch (_dialect) {
      case 'sqlite':
      case 'sqlite3':
        return 'datetime';
      case 'mysql':
      case 'mysql2':
        return 'timestamp';
      default:
        return useTz ? 'timestamptz' : 'timestamp';
    }
  }

  String _binaryType() {
    switch (_dialect) {
      case 'sqlite':
      case 'sqlite3':
        return 'blob';
      case 'mysql':
      case 'mysql2':
        return 'blob';
      case 'redshift':
        // Redshift has no BLOB/BYTEA type — knex.js's redshift compiler
        // falls back to varchar(max), same as its text()/json()/jsonb()
        // handling (verified against real knex.js 3.3.0).
        return 'varchar(max)';
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
      case 'redshift':
        // Redshift has no native UUID type either — knex.js's redshift
        // compiler falls back to the same char(36) as MySQL/SQLite
        // (verified against real knex.js 3.3.0), not Postgres's `uuid`.
        return 'char(36)';
      default:
        return 'uuid';
    }
  }

  String _jsonType() {
    switch (_dialect) {
      case 'sqlite':
      case 'sqlite3':
        return 'json';
      case 'mysql':
      case 'mysql2':
        return 'json';
      case 'redshift':
        return 'varchar(max)';
      default:
        return 'json';
    }
  }

  String _jsonbType() {
    switch (_dialect) {
      case 'sqlite':
      case 'sqlite3':
        return 'json';
      case 'mysql':
      case 'mysql2':
        return 'json'; // MySQL doesn't distinguish json/jsonb
      case 'redshift':
        return 'varchar(max)';
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
        // knex.js's base `floating()` column compiler (shared by MySQL,
        // which does not override it) always applies default precision/
        // scale (8, 2) even when the caller passes none — verified against
        // real knex.js 3.3.0: `t.float('foo')` on mysql2 compiles to
        // `float(8, 2)`, not bare `float`.
        return 'float(8, 2)';
      default:
        return 'real';
    }
  }

  /// Double-precision column type, dialect-aware. Verified against real
  /// knex.js 3.3.0: MySQL emits `double`, SQLite aliases it to `float`
  /// (same type-affinity reasoning as `_decimalType` below), everything
  /// else (Postgres-family) keeps `double precision`.
  String _doublePrecisionType() {
    switch (_dialect) {
      case 'mysql':
      case 'mysql2':
        return 'double';
      case 'sqlite':
      case 'sqlite3':
        return 'float';
      default:
        return 'double precision';
    }
  }

  /// Decimal column type, dialect-aware.
  ///
  /// SQLite has no fixed-precision DECIMAL type; knex.js's SQLite column
  /// compiler aliases `decimal`/`double`/`floating` all to the same `float`
  /// type (verified against real knex.js 3.3.0: `t.decimal('foo', 5, 2)` on
  /// sqlite3 compiles to `float`, silently dropping precision/scale). This
  /// matters beyond spelling: SQLite derives column *type affinity* from the
  /// type name — `float` contains "FLOA" -> REAL affinity, but
  /// `decimal(5, 2)` matches no affinity keyword -> NUMERIC affinity, a
  /// different storage/comparison behavior.
  String _decimalType(int precision, int scale) {
    if (_dialect == 'sqlite' || _dialect == 'sqlite3') return 'float';
    return 'decimal($precision, $scale)';
  }

  String _enumType(String column, List<String> values) {
    // Escape single quotes in enum values to prevent broken SQL / injection
    // (e.g. a value like `O'Brien` must become `'O''Brien'`).
    String quote(String v) => "'${v.replaceAll("'", "''")}'";
    switch (_dialect) {
      case 'mysql':
      case 'mysql2':
        final valuesStr = values.map(quote).join(', ');
        return 'enum($valuesStr)';
      case 'redshift':
        // Redshift has no native ENUM type and no CHECK-constraint support
        // for this either — knex.js's redshift compiler emits a bare
        // varchar(255), dropping the value list entirely (verified against
        // real knex.js 3.3.0).
        return 'varchar(255)';
      default: // PG and SQLite use CHECK constraint
        final valuesStr = values.map(quote).join(', ');
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
    // Redshift has no TEXT type — knex.js's redshift compiler falls back to
    // varchar(max), same as binary()/json()/jsonb() (verified against real
    // knex.js 3.3.0).
    final type = _dialect == 'redshift' ? 'varchar(max)' : 'text';
    final cb = ColumnBuilder(column, type);
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

  /// Timestamp column.
  ///
  /// For PostgreSQL:
  /// - `useTz = true`  -> `timestamptz` (default)
  /// - `useTz = false` -> `timestamp`
  ///
  /// For MySQL/SQLite, this maps to `datetime` regardless of [useTz].
  ColumnBuilder timestamp(String column, [bool useTz = true]) {
    final cb = ColumnBuilder(column, _timestampType(useTz));
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
    final cb = ColumnBuilder(column, _doublePrecisionType());
    _columns.add(cb);
    return cb;
  }

  /// Decimal column
  ColumnBuilder decimal(String column, [int precision = 8, int scale = 2]) {
    final cb = ColumnBuilder(column, _decimalType(precision, scale));
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
    final cb = ColumnBuilder(column, _jsonType(), isJson: true);
    _columns.add(cb);
    return cb;
  }

  /// JSONB column (Postgres)
  ColumnBuilder jsonb(String column) {
    final cb = ColumnBuilder(column, _jsonbType(), isJson: true);
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

  /// Timestamps helper — adds created_at and updated_at columns.
  ///
  ///
  /// For PostgreSQL:
  /// - `useTz = true`  -> `timestamptz` (default)
  /// - `useTz = false` -> `timestamp`
  ///
  /// For MySQL/SQLite, this maps to `datetime` regardless of [useTz].
  void timestamps([
    bool useTimestamps = false,
    bool defaultToNow = false,
    bool useTz = true,
  ]) {
    // MySQL is a special case: `timestamps()` uses `datetime`, not the
    // `timestamp` that a single `.timestamp()` column maps to — verified
    // against real knex.js 3.3.0. Every other dialect's `timestamps()`
    // output already matches `_timestampType(useTz)` (including SQLite's
    // shared `datetime` and knex-dart's Postgres-only `useTz` extension,
    // which has no knex.js equivalent and is intentionally preserved here).
    final type = (_dialect == 'mysql' || _dialect == 'mysql2')
        ? 'datetime'
        : _timestampType(useTz);
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

  /// Drop multiple columns. knex.js compiles this to a single ALTER TABLE
  /// statement with one comma-separated `drop column` clause per column
  /// (verified against real knex.js 3.3.0), not one ALTER TABLE per column.
  void dropColumns(List<String> columns) {
    _alterStatements.add({
      'method': 'dropColumns',
      'args': columns,
    });
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

  /// Add fulltext index (MySQL/MariaDB only).
  void fulltext(dynamic columns, [String? indexName]) {
    _alterStatements.add({
      'method': 'fulltext',
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
    final cols = useCamelCase
        ? ['createdAt', 'updatedAt']
        : ['created_at', 'updated_at'];
    _alterStatements.add({'method': 'dropTimestamps', 'args': cols});
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
