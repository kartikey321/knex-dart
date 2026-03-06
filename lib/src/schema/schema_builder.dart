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

  /// Compile all DDL operations to SQL.
  List<Map<String, dynamic>> toSQL() {
    return _client.schemaCompiler(this).toSQL();
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
}
