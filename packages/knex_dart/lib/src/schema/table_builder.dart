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

  /// MySQL-family driver-name set. Includes `mariadb` (which emits
  /// driver-name `'mariadb'`, not `'mysql2'`). Previously every per-type
  /// `switch (_dialect) { case 'mysql': case 'mysql2': ... }` block below
  /// silently dispatched mariadb to the Postgres-shaped `default` branch —
  /// dropping the unsigned/auto_increment-friendly type, the tinyint(1)
  /// boolean synonym, the float-with-precision spelling, etc. Same family-
  /// missing bug pattern the parity harness's mariadb dialect caught for
  /// the query-compiler family-aware helpers — see the commit history for
  /// `_isMySqlLikeDriver` (query_compiler.dart) and `_mysqlLike`
  /// (column_builder.dart).
  static const _mysqlLike = {'mysql', 'mysql2', 'mariadb'};

  bool get _isMysqlDialect => _mysqlLike.contains(_dialect);
  bool get _isRedshiftDialect => _dialect == 'redshift';

  // ============================================================================
  // DIALECT-AWARE TYPE RESOLUTION
  // ============================================================================

  String _incrementsType() {
    if (_dialect == 'sqlite') return 'integer primary key autoincrement';
    if (_isMysqlDialect) return 'int unsigned auto_increment primary key';
    if (_isRedshiftDialect) {
      // Redshift has no SERIAL type; IDENTITY is the equivalent.
      return 'integer identity(1,1) primary key not null';
    }
    return 'serial primary key'; // pg, cockroachdb
  }

  String _bigIncrementsType() {
    if (_dialect == 'sqlite') return 'integer primary key autoincrement';
    if (_isMysqlDialect) {
      return 'bigint unsigned auto_increment primary key';
    }
    if (_isRedshiftDialect) {
      return 'bigint identity(1,1) primary key not null';
    }
    return 'bigserial primary key'; // pg, cockroachdb
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
    // knex.js 3.x: ALL clients (pg, mysql2, sqlite3, cockroachdb, redshift,
    // and the mysql/mariadb family) emit `boolean` for `table.boolean(col)`.
    // Verified against real knex.js 3.3.0:
    //   pg:          alter table "users" add column "foo" boolean
    //   mysql2:      alter table `users` add `foo` boolean
    //   sqlite3:     alter table `users` add column `foo` boolean
    //   cockroachdb: alter table "users" add column "foo" boolean
    //   redshift:    alter table "users" add column "foo" boolean
    // Previously knex-dart emitted `tinyint(1)` for mysql/mariadb — a legacy
    // spelling knex.js dropped. MariaDB 10.0+ has `BOOLEAN` as a true alias
    // for `TINYINT(1)` (column means the same thing, just different keyword
    // spelling); Postgres/SQLite both treat `BOOLEAN` as a real type.
    return 'boolean';
  }

  String _datetimeType() {
    if (_isMysqlDialect) return 'datetime';
    if (_dialect == 'sqlite') return 'datetime';
    return 'timestamptz';
  }

  String _timestampType([bool useTz = true]) {
    if (_isMysqlDialect) return 'timestamp';
    if (_dialect == 'sqlite') return 'datetime';
    return useTz ? 'timestamptz' : 'timestamp';
  }

  String _binaryType() {
    if (_dialect == 'sqlite' || _isMysqlDialect) return 'blob';
    if (_isRedshiftDialect) return 'varchar(max)';
    return 'bytea'; // pg, cockroachdb
  }

  String _uuidType() {
    if (_dialect == 'sqlite' || _isMysqlDialect) return 'char(36)';
    if (_isRedshiftDialect) return 'char(36)';
    return 'uuid'; // pg, cockroachdb
  }

  String _jsonType() {
    if (_isMysqlDialect) return 'json';
    if (_isRedshiftDialect) return 'varchar(max)';
    // sqlite, pg, cockroachdb all use `json`
    return 'json';
  }

  String _jsonbType() {
    if (_dialect == 'sqlite' || _isMysqlDialect) return 'json';
    if (_isRedshiftDialect) return 'varchar(max)';
    return 'jsonb'; // pg, cockroachdb
  }

  String _floatType() {
    if (_dialect == 'sqlite') return 'float';
    if (_isMysqlDialect) return 'float';
    // pg, cockroachdb, redshift all use `real` (verified against real knex.js
    // 3.3.0 — pg AND redshift AND cockroachdb's clients all emit `real` for
    // `table.float`, NOT `float` or `float(p,s)`). Note: when the caller
    // passes precision/scale args (knex.js's `table.float('x', 5, 2)`), the
    // mysql2 client emits `float(5, 2)` and the other dialects still emit
    // `real`/`float` (ignoring the args). knex-dart's `float(column)` API
    // doesn't expose precision/scale — see the `schema/column-float::mysql`
    // parity allowlist entry for the cosmetic divergence.
    return 'real';
  }

  String _enumType(String column, List<String> values) {
    // Escape single quotes in enum values to prevent broken SQL / injection
    // (e.g. a value like `O'Brien` must become `'O''Brien'`).
    String quote(String v) => "'${v.replaceAll("'", "''")}'";
    if (_isMysqlDialect) {
      return 'enum(${values.map(quote).join(', ')})';
    }
    // Redshift has no CHECK-constraint or ENUM-type support — knex.js's
    // redshift client emits `varchar(255)` as the type (verified against
    // real knex.js 3.3.0). Without this branch, knex-dart emitted
    // `text check (...)`, which Redshift rejects at parse time (no
    // inline CHECK on CREATE/ALTER).
    if (_isRedshiftDialect) return 'varchar(255)';
    // pg, sqlite, cockroachdb use text + CHECK constraint
    return 'text check ("$column" in (${values.map(quote).join(', ')}))';
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
    final type = _timestampType(useTz);
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

  /// Drop multiple columns.
  ///
  /// knex.js emits a single combined `alter table t drop column X, drop
  /// column Y` statement (or `drop X, drop Y` for MySQL), NOT one statement
  /// per column — verified against real knex.js 3.3.0 for pg/mysql/sqlite/
  /// redshift. Previously this looped and pushed N separate `dropColumn`
  /// statements, producing N `alter table ... drop column X` statements
  /// instead of the combined form the harness expected.
  void dropColumns(List<String> columns) {
    _alterStatements.add({
      'method': 'dropColumns',
      'args': [columns],
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
