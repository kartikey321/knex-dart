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
    if (_dialect == 'mssql') {
      // MSSQL has no SERIAL type either; IDENTITY(1,1) is the equivalent.
      // Verified against real knex.js 3.3.0's mssql-columncompiler.js:
      // `increments()` -> 'int identity(1,1) not null' + ' primary key'
      // when the column can carry an inline PK (the common case; the
      // `{primaryKey: false}` escape hatch has no Dart-side call to mirror
      // it with — TableBuilder.increments() takes no options argument).
      return 'int identity(1,1) not null primary key';
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
    if (_dialect == 'mssql') {
      // See _incrementsType's mssql case — same reasoning, bigint width.
      return 'bigint identity(1,1) not null primary key';
    }
    return 'bigserial primary key'; // pg, cockroachdb
  }

  String _stringType(int length) {
    switch (_dialect) {
      case 'sqlite':
      case 'sqlite3':
        return 'varchar($length)';
      case 'mssql':
        // MSSQL's varchar() column compiler emits nvarchar (Unicode),
        // not varchar — verified against real knex.js 3.3.0.
        return 'nvarchar($length)';
      default:
        return 'varchar($length)';
    }
  }

  String _booleanType() {
    // knex.js 3.x: ALL clients (pg, mysql2/mariadb, sqlite3, cockroachdb,
    // redshift) emit `boolean` for `table.boolean(col)` — verified directly
    // against the checked-out knex.js 3.3.0 source. Previously knex-dart
    // emitted `tinyint(1)` for mysql/mariadb, a legacy spelling knex.js
    // dropped (MariaDB 10.0+ has `BOOLEAN` as a true alias for `TINYINT(1)`;
    // Postgres/SQLite both treat `BOOLEAN` as a real type).
    if (_dialect == 'mssql') {
      // MSSQL has no native BOOLEAN type; BIT is the equivalent (verified
      // against real knex.js 3.3.0's mssql-columncompiler.js `bit()`).
      return 'bit';
    }
    return 'boolean';
  }

  String _datetimeType() {
    if (_isMysqlDialect) return 'datetime';
    if (_dialect == 'sqlite') return 'datetime';
    if (_dialect == 'mssql') {
      // Verified against real knex.js 3.3.0:
      // `ColumnCompiler_MSSQL.prototype.datetime = 'datetime2'`.
      return 'datetime2';
    }
    return 'timestamptz';
  }

  /// [useTz] is `null` when the caller never explicitly passed a value
  /// (Dart's [TableBuilder.timestamp] default), vs. an explicit
  /// `true`/`false`. This distinction only matters for MSSQL below — every
  /// other branch already treats "not passed" the same as `true`, matching
  /// prior behavior exactly.
  String _timestampType([bool? useTz]) {
    if (_isMysqlDialect) return 'timestamp';
    if (_dialect == 'sqlite') return 'datetime';
    if (_dialect == 'mssql') {
      // MSSQL's own default is useTz=false (datetime2); datetimeoffset
      // only when explicitly requested. Verified against real knex.js
      // 3.3.0's mssql-columncompiler.js: `timestamp({useTz = false})`.
      // Note this default direction is the OPPOSITE of every other
      // dialect here (which default to timezone-aware) — deliberate,
      // matches knex.js's own per-dialect default, not a bug.
      return useTz == true ? 'datetimeoffset' : 'datetime2';
    }
    return (useTz ?? true) ? 'timestamptz' : 'timestamp';
  }

  String _binaryType() {
    if (_dialect == 'sqlite' || _isMysqlDialect) return 'blob';
    if (_isRedshiftDialect) {
      // Redshift has no BLOB/BYTEA type — knex.js's redshift compiler falls
      // back to varchar(max), same as its text()/json()/jsonb() handling
      // (verified against real knex.js 3.3.0).
      return 'varchar(max)';
    }
    if (_dialect == 'mssql') {
      // Bare binary() (no length) -> varbinary(max) — verified against real
      // knex.js 3.3.0's mssql-columncompiler.js `binary(length)`. The
      // length-specifying overload has no Dart-side call to mirror it with
      // (TableBuilder.binary() takes no length argument).
      return 'varbinary(max)';
    }
    return 'bytea'; // pg, cockroachdb
  }

  String _uuidType() {
    if (_dialect == 'sqlite' || _isMysqlDialect) return 'char(36)';
    if (_isRedshiftDialect) {
      // Redshift has no native UUID type either — knex.js's redshift
      // compiler falls back to the same char(36) as MySQL/SQLite (verified
      // against real knex.js 3.3.0), not Postgres's `uuid`.
      return 'char(36)';
    }
    if (_dialect == 'mssql') {
      // Verified against real knex.js 3.3.0's mssql-columncompiler.js:
      // `uuid = ({useBinaryUuid = false}) => useBinaryUuid ? 'binary(16)' :
      // 'uniqueidentifier'`. The useBinaryUuid overload has no Dart-side
      // call to mirror it with (TableBuilder.uuid() takes no options
      // argument).
      return 'uniqueidentifier';
    }
    return 'uuid'; // pg, cockroachdb
  }

  String _jsonType() {
    if (_isMysqlDialect) return 'json';
    if (_isRedshiftDialect) return 'varchar(max)';
    if (_dialect == 'mssql') {
      // MSSQL has no native JSON type; knex.js's mssql column compiler maps
      // both json and jsonb to nvarchar(max) (verified against real knex.js
      // 3.3.0).
      return 'nvarchar(max)';
    }
    // sqlite, pg, cockroachdb all use `json`
    return 'json';
  }

  String _jsonbType() {
    if (_dialect == 'sqlite' || _isMysqlDialect) return 'json';
    if (_isRedshiftDialect) return 'varchar(max)';
    if (_dialect == 'mssql') {
      // See _jsonType's mssql case — jsonb maps to the same nvarchar(max).
      return 'nvarchar(max)';
    }
    return 'jsonb'; // pg, cockroachdb
  }

  String _floatType() {
    if (_dialect == 'sqlite') return 'float';
    if (_isMysqlDialect) {
      // knex.js's base `floating()` column compiler (shared by MySQL, which
      // does not override it) always applies default precision/scale (8, 2)
      // even when the caller passes none — verified against real knex.js
      // 3.3.0: `t.float('foo')` on mysql2 compiles to `float(8, 2)`, not
      // bare `float`.
      return 'float(8, 2)';
    }
    if (_dialect == 'mssql') {
      // MSSQL's floating() column compiler ignores precision/scale entirely
      // and always emits bare `float` (verified against real knex.js
      // 3.3.0's mssql-columncompiler.js `floating()`).
      return 'float';
    }
    // pg, cockroachdb, redshift all use `real` (verified against real
    // knex.js 3.3.0 — pg AND redshift AND cockroachdb's clients all emit
    // `real` for `table.float`, NOT `float` or `float(p,s)`). Note: when the
    // caller passes precision/scale args (knex.js's `table.float('x', 5,
    // 2)`), the mysql2 client emits `float(5, 2)` and the other dialects
    // still emit `real`/`float` (ignoring the args). knex-dart's
    // `float(column)` API doesn't expose precision/scale — see the
    // `schema/column-float::mysql` parity allowlist entry for the cosmetic
    // divergence.
    return 'real';
  }

  /// Double-precision column type, dialect-aware. Verified against real
  /// knex.js 3.3.0: MySQL emits `double`, SQLite aliases it to `float`
  /// (same type-affinity reasoning as `_decimalType` below), everything
  /// else (Postgres-family) keeps `double precision`.
  String _doublePrecisionType() {
    if (_isMysqlDialect) return 'double';
    if (_dialect == 'sqlite') return 'float';
    if (_dialect == 'mssql') {
      // MSSQL's double() column compiler also ignores precision/scale and
      // emits bare `float` — verified against real knex.js 3.3.0's
      // mssql-columncompiler.js `double(precision, scale)`.
      return 'float';
    }
    return 'double precision';
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
    if (_isMysqlDialect) {
      return 'enum(${values.map(quote).join(', ')})';
    }
    // Redshift has no CHECK-constraint or ENUM-type support — knex.js's
    // redshift client emits `varchar(255)` as the type (verified against
    // real knex.js 3.3.0). Without this branch, knex-dart emitted
    // `text check (...)`, which Redshift rejects at parse time (no
    // inline CHECK on CREATE/ALTER).
    if (_isRedshiftDialect) return 'varchar(255)';
    if (_dialect == 'mssql') {
      // MSSQL has no native ENUM type; knex.js's mssql column compiler
      // hardcodes a bare nvarchar(100), dropping the value list entirely
      // (verified against real knex.js 3.3.0:
      // `ColumnCompiler_MSSQL.prototype.enu = 'nvarchar(100)'`). A real
      // CHECK-constraint-backed enum is possible on MSSQL but that's not
      // what knex.js emits here.
      return 'nvarchar(100)';
    }
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
    // Redshift has no TEXT type — knex.js's redshift compiler falls back to
    // varchar(max), same as binary()/json()/jsonb() (verified against real
    // knex.js 3.3.0). MSSQL's text/mediumtext/longtext all alias to
    // nvarchar(max) (verified against real knex.js 3.3.0's
    // mssql-columncompiler.js prototype overrides).
    final type = _dialect == 'redshift'
        ? 'varchar(max)'
        : _dialect == 'mssql'
            ? 'nvarchar(max)'
            : 'text';
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
  /// - `useTz = true` (or omitted) -> `timestamptz` (default)
  /// - `useTz = false` -> `timestamp`
  ///
  /// For MySQL/SQLite, this maps to `datetime` regardless of [useTz].
  ///
  /// For MSSQL, the default direction is reversed from every other
  /// dialect: omitting [useTz] (or passing `false`) maps to `datetime2`;
  /// only an explicit `useTz: true` maps to `datetimeoffset` — matching
  /// knex.js's own mssql-specific default (verified against real knex.js
  /// 3.3.0). [useTz] is nullable here (rather than defaulting to `true`)
  /// so `_timestampType` can distinguish "never specified" from an
  /// explicit `true`, which only matters for that MSSQL branch.
  ColumnBuilder timestamp(String column, [bool? useTz]) {
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
    //
    // MSSQL is also special-cased: knex.js's own `timestamps()` helper
    // calls the `datetime` column method (not `timestamp`) whenever
    // `useTimestamps` isn't explicitly `true` — mssql's `datetime` prototype
    // is a fixed `datetime2` with no useTz knob at all (verified against
    // real knex.js 3.3.0: `lib/schema/tablebuilder.js`'s `timestamps()`
    // picks `this[useTimestamps === true ? 'timestamp' : 'datetime']`, and
    // `timestamps()` is never called here with the JS-side `useTimestamps`
    // meaning — this [useTz] param is knex-dart's own, unrelated,
    // Postgres-only extension). Threading `useTz` straight into
    // `_timestampType` for mssql would wrongly emit `datetimeoffset` for a
    // bare `t.timestamps()` call.
    final type = _isMysqlDialect
        ? 'datetime'
        : _dialect == 'mssql'
            ? 'datetime2'
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
  /// (`drop column X, drop column Y`, or `drop X, drop Y` for MySQL-family)
  /// — verified against real knex.js 3.3.0 for pg/mysql/sqlite/redshift —
  /// not one ALTER TABLE per column. SQLite instead reroutes through a
  /// PRAGMA-based table rebuild, which knex-dart doesn't implement (see the
  /// `alter-table-drop-column::sqlite` ACCEPTED entry); its own ALTER TABLE
  /// grammar only allows one operation per statement anyway, so the combined
  /// form isn't an option there regardless — see schema_compiler.dart's
  /// `dropColumns` case for the per-dialect handling.
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
