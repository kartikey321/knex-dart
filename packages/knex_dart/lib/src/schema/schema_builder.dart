import '../client/client.dart';
import 'table_builder.dart';

/// Schema builder for DDL operations.
///
/// Records a sequence of DDL operations (createTable, dropTable, etc.)
/// and compiles them to SQL via [SchemaCompiler].
///
class SchemaBuilder {
  final Client _client;
  final List<Map<String, dynamic>> _sequence = [];
  String? _schema;

  SchemaBuilder(this._client);

  Client get client => _client;
  List<Map<String, dynamic>> get sequence => _sequence;
  String? get schema => _schema;

  /// Set the schema namespace (e.g. 'public' in Postgres)
  SchemaBuilder withSchema(String schemaName) {
    _schema = schemaName;
    return this;
  }

  /// Create a table with a callback that receives a [TableBuilder].
  SchemaBuilder createTable(
    String tableName,
    void Function(TableBuilder) callback,
  ) {
    _sequence.add({
      'method': 'createTable',
      'args': [tableName, callback],
    });
    return this;
  }

  /// Create a table only if it doesn't already exist.
  SchemaBuilder createTableIfNotExists(
    String tableName,
    void Function(TableBuilder) callback,
  ) {
    _sequence.add({
      'method': 'createTableIfNotExists',
      'args': [tableName, callback],
    });
    return this;
  }

  /// Create a table from another existing table structure.
  ///
  /// Mirrors Knex.js where an optional callback can add extra columns.
  SchemaBuilder createTableLike(
    String tableName,
    String tableNameLike, [
    void Function(TableBuilder)? callback,
  ]) {
    _sequence.add({
      'method': 'createTableLike',
      'args': callback == null
          ? [tableName, tableNameLike]
          : [tableName, tableNameLike, callback],
    });
    return this;
  }

  /// Create a SQL view from a SELECT definition.
  SchemaBuilder createView(String viewName, dynamic definition) {
    _sequence.add({
      'method': 'createView',
      'args': [viewName, definition],
    });
    return this;
  }

  /// Create or replace a SQL view from a SELECT definition.
  SchemaBuilder createViewOrReplace(String viewName, dynamic definition) {
    _sequence.add({
      'method': 'createViewOrReplace',
      'args': [viewName, definition],
    });
    return this;
  }

  /// Create a materialized view from a SELECT definition.
  SchemaBuilder createMaterializedView(String viewName, dynamic definition) {
    _sequence.add({
      'method': 'createMaterializedView',
      'args': [viewName, definition],
    });
    return this;
  }

  /// Refresh a materialized view.
  SchemaBuilder refreshMaterializedView(
    String viewName, [
    bool concurrently = false,
  ]) {
    _sequence.add({
      'method': 'refreshMaterializedView',
      'args': [viewName, concurrently],
    });
    return this;
  }

  /// Drop a view.
  SchemaBuilder dropView(String viewName) {
    _sequence.add({
      'method': 'dropView',
      'args': [viewName],
    });
    return this;
  }

  /// Drop a view if it exists.
  SchemaBuilder dropViewIfExists(String viewName) {
    _sequence.add({
      'method': 'dropViewIfExists',
      'args': [viewName],
    });
    return this;
  }

  /// Drop a materialized view.
  SchemaBuilder dropMaterializedView(String viewName) {
    _sequence.add({
      'method': 'dropMaterializedView',
      'args': [viewName],
    });
    return this;
  }

  /// Drop a materialized view if it exists.
  SchemaBuilder dropMaterializedViewIfExists(String viewName) {
    _sequence.add({
      'method': 'dropMaterializedViewIfExists',
      'args': [viewName],
    });
    return this;
  }

  /// Create a schema namespace.
  SchemaBuilder createSchema(String schemaName) {
    _sequence.add({
      'method': 'createSchema',
      'args': [schemaName],
    });
    return this;
  }

  /// Create a schema namespace if it does not exist.
  SchemaBuilder createSchemaIfNotExists(String schemaName) {
    _sequence.add({
      'method': 'createSchemaIfNotExists',
      'args': [schemaName],
    });
    return this;
  }

  /// Drop a schema namespace.
  SchemaBuilder dropSchema(String schemaName, [bool cascade = false]) {
    _sequence.add({
      'method': 'dropSchema',
      'args': [schemaName, cascade],
    });
    return this;
  }

  /// Drop a schema namespace if it exists.
  SchemaBuilder dropSchemaIfExists(String schemaName, [bool cascade = false]) {
    _sequence.add({
      'method': 'dropSchemaIfExists',
      'args': [schemaName, cascade],
    });
    return this;
  }

  /// Create a database extension.
  SchemaBuilder createExtension(String extensionName) {
    _sequence.add({
      'method': 'createExtension',
      'args': [extensionName],
    });
    return this;
  }

  /// Create a database extension if it does not exist.
  SchemaBuilder createExtensionIfNotExists(String extensionName) {
    _sequence.add({
      'method': 'createExtensionIfNotExists',
      'args': [extensionName],
    });
    return this;
  }

  /// Drop a database extension.
  SchemaBuilder dropExtension(String extensionName) {
    _sequence.add({
      'method': 'dropExtension',
      'args': [extensionName],
    });
    return this;
  }

  /// Drop a database extension if it exists.
  SchemaBuilder dropExtensionIfExists(String extensionName) {
    _sequence.add({
      'method': 'dropExtensionIfExists',
      'args': [extensionName],
    });
    return this;
  }

  /// Drop a table.
  SchemaBuilder dropTable(String tableName) {
    _sequence.add({
      'method': 'dropTable',
      'args': [tableName],
    });
    return this;
  }

  /// Drop a table if it exists.
  SchemaBuilder dropTableIfExists(String tableName) {
    _sequence.add({
      'method': 'dropTableIfExists',
      'args': [tableName],
    });
    return this;
  }

  /// Rename a table.
  SchemaBuilder renameTable(String from, String to) {
    _sequence.add({
      'method': 'renameTable',
      'args': [from, to],
    });
    return this;
  }

  /// Rename a view.
  SchemaBuilder renameView(String from, String to) {
    _sequence.add({
      'method': 'renameView',
      'args': [from, to],
    });
    return this;
  }

  /// Alter a table (add/drop columns, indices, etc.).
  SchemaBuilder alterTable(
    String tableName,
    void Function(TableBuilder) callback,
  ) {
    _sequence.add({
      'method': 'alterTable',
      'args': [tableName, callback],
    });
    return this;
  }

  SchemaBuilder table(String tableName, void Function(TableBuilder) callback) {
    return alterTable(tableName, callback);
  }

  /// Alias for alterView to match Knex.js API.
  SchemaBuilder view(String viewName, dynamic definition) {
    return alterView(viewName, definition);
  }

  /// Alter a view definition (implemented as create or replace view).
  SchemaBuilder alterView(String viewName, dynamic definition) {
    _sequence.add({
      'method': 'alterView',
      'args': [viewName, definition],
    });
    return this;
  }

  /// Add a raw SQL statement to the schema sequence.
  SchemaBuilder raw(String sql, [List<dynamic>? bindings]) {
    _sequence.add({
      'method': 'raw',
      'args': [sql, bindings ?? const []],
    });
    return this;
  }

  /// Compile all DDL operations to SQL.
  List<Map<String, dynamic>> toSQL() {
    return _client.schemaCompiler(this).toSQL();
  }

  /// Check whether a table exists.
  ///
  /// Mirrors Knex.js behavior with dialect-specific lookup queries.
  Future<bool> hasTable(String tableName) async {
    final resolved = _resolveSchemaAndTable(tableName);
    final driver = _client.driverName.toLowerCase();
    final p1 = _client.parameterPlaceholder(1);
    final p2 = _client.parameterPlaceholder(2);

    late final String sql;
    late final List<dynamic> bindings;

    if (_isSqliteLike(driver)) {
      final sqliteMaster = resolved.schema != null
          ? '"${_escapeIdent(resolved.schema!)}".sqlite_master'
          : 'sqlite_master';
      sql =
          "select * from $sqliteMaster where type = 'table' and name = ? limit 1";
      bindings = [resolved.table];
    } else if (_isPostgresLike(driver)) {
      sql =
          'select * from information_schema.tables where table_name = $p1'
          '${resolved.schema != null ? ' and table_schema = $p2' : ' and table_schema = current_schema()'}';
      bindings = resolved.schema != null
          ? [resolved.table, resolved.schema]
          : [resolved.table];
    } else if (_isMySqlLike(driver)) {
      sql =
          'select * from information_schema.tables where table_name = ?'
          '${resolved.schema != null ? ' and table_schema = ?' : ' and table_schema = database()'}';
      bindings = resolved.schema != null
          ? [resolved.table, resolved.schema]
          : [resolved.table];
    } else if (driver == 'mssql') {
      sql =
          'select * from information_schema.tables where table_name = ?'
          '${resolved.schema != null ? ' and table_schema = ?' : ''}';
      bindings = resolved.schema != null
          ? [resolved.table, resolved.schema]
          : [resolved.table];
    } else {
      // Generic fallback (works for DuckDB and other SQL dialects exposing
      // INFORMATION_SCHEMA).
      sql =
          'select * from information_schema.tables where table_name = ?'
          '${resolved.schema != null ? ' and table_schema = ?' : ''}';
      bindings = resolved.schema != null
          ? [resolved.table, resolved.schema]
          : [resolved.table];
    }

    final result = await _client.rawQuery(sql, bindings);
    return _extractRows(result).isNotEmpty;
  }

  /// Check whether a column exists in a table.
  ///
  /// Mirrors Knex.js behavior with dialect-specific lookup queries.
  Future<bool> hasColumn(String tableName, String columnName) async {
    final resolved = _resolveSchemaAndTable(tableName);
    final driver = _client.driverName.toLowerCase();
    final p1 = _client.parameterPlaceholder(1);
    final p2 = _client.parameterPlaceholder(2);
    final p3 = _client.parameterPlaceholder(3);

    late final String sql;
    late final List<dynamic> bindings;

    if (_isSqliteLike(driver)) {
      final tableRef = resolved.schema != null
          ? '${_wrap(resolved.schema!)}.${_wrap(resolved.table)}'
          : _wrap(resolved.table);
      sql = 'PRAGMA table_info($tableRef)';
      bindings = const [];
      final result = await _client.rawQuery(sql, bindings);
      final rows = _extractRows(result);
      return rows.any((row) {
        final rawName = row['name']?.toString();
        return rawName != null &&
            _normalizeIdent(rawName) == _normalizeIdent(columnName);
      });
    } else if (_isPostgresLike(driver)) {
      sql =
          'select * from information_schema.columns where table_name = $p1 and column_name = $p2'
          '${resolved.schema != null
              ? ' and table_schema = $p3'
              : _isPostgresLike(driver)
              ? ' and table_schema = current_schema()'
              : ''}';
      bindings = resolved.schema != null
          ? [resolved.table, columnName, resolved.schema]
          : [resolved.table, columnName];
    } else if (driver == 'mssql') {
      // Knex.js MSSQL uses sys.columns/object_id lookup.
      sql =
          'select object_id from sys.columns where name = ? and object_id = object_id(?)';
      final tableRef = resolved.schema != null
          ? '${_wrap(resolved.schema!)}.${_wrap(resolved.table)}'
          : _wrap(resolved.table);
      bindings = [columnName, tableRef];
    } else if (_isMySqlLike(driver)) {
      // Knex.js uses SHOW COLUMNS on MySQL-family dialects for hasColumn.
      final tableRef = resolved.schema != null
          ? '${_wrap(resolved.schema!)}.${_wrap(resolved.table)}'
          : _wrap(resolved.table);
      sql = 'show columns from $tableRef';
      bindings = const [];
      final result = await _client.rawQuery(sql, bindings);
      final rows = _extractRows(result);
      return rows.any((row) {
        final rawName = row['Field']?.toString() ?? row['field']?.toString();
        return rawName != null &&
            _normalizeIdent(rawName) == _normalizeIdent(columnName);
      });
    } else {
      // Generic fallback for dialects exposing information_schema.
      sql =
          'select * from information_schema.columns where table_name = ? and column_name = ?'
          '${resolved.schema != null ? ' and table_schema = ?' : ''}';
      bindings = resolved.schema != null
          ? [resolved.table, columnName, resolved.schema]
          : [resolved.table, columnName];
    }

    final result = await _client.rawQuery(sql, bindings);
    return _extractRows(result).isNotEmpty;
  }

  /// Execute all DDL operations against the database.
  ///
  /// Compiles each DDL operation to SQL and executes it in sequence.
  /// Returns the list of SQL statements that were executed.
  Future<List<Map<String, dynamic>>> execute() async {
    final statements = toSQL();
    for (final stmt in statements) {
      final sql = stmt['sql'] as String;
      final bindings = stmt['bindings'] as List<dynamic>? ?? [];
      await _client.rawQuery(sql, bindings);
    }
    return statements;
  }

  ({String table, String? schema}) _resolveSchemaAndTable(String input) {
    final raw = input.trim();
    final configuredSchema = schema;
    if (configuredSchema != null && configuredSchema.isNotEmpty) {
      return (table: _stripIdentifier(raw), schema: configuredSchema);
    }

    final parts = raw.split('.');
    if (parts.length == 2) {
      return (
        table: _stripIdentifier(parts[1]),
        schema: _stripIdentifier(parts[0]),
      );
    }
    return (table: _stripIdentifier(raw), schema: null);
  }

  List<Map<String, dynamic>> _extractRows(dynamic result) {
    if (result is List) {
      return result
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (result is Map && result['rows'] is List) {
      final rows = result['rows'] as List;
      return rows
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    try {
      final rows = (result as dynamic).rows;
      if (rows is List) {
        return rows
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  bool _isSqliteLike(String driver) =>
      driver == 'sqlite' ||
      driver == 'sqlite3' ||
      driver == 'turso' ||
      driver == 'd1';

  bool _isPostgresLike(String driver) =>
      driver == 'pg' ||
      driver == 'postgres' ||
      driver == 'postgresql' ||
      driver == 'cockroachdb' ||
      driver == 'redshift';

  bool _isMySqlLike(String driver) =>
      driver == 'mysql' || driver == 'mysql2' || driver == 'mariadb';

  String _stripIdentifier(String value) {
    final v = value.trim();
    if (v.length >= 2 &&
        ((v.startsWith('"') && v.endsWith('"')) ||
            (v.startsWith('`') && v.endsWith('`')) ||
            (v.startsWith('[') && v.endsWith(']')))) {
      return v.substring(1, v.length - 1);
    }
    return v;
  }

  String _normalizeIdent(String value) => _stripIdentifier(value).toLowerCase();

  String _escapeIdent(String value) => value.replaceAll('"', '""');

  String _wrap(String value) => _client.formatter(this).wrapString(value);
}
