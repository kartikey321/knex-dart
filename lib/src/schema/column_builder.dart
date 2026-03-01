import 'package:knex_dart/src/raw.dart';

/// A fluent builder for a column definition in a CREATE TABLE or ALTER TABLE statement.
///
/// All methods return `this` for chaining, mirroring the Knex.js chainable column API.
///
/// Example:
/// ```dart
/// table.string('email', 255)
///      .notNullable()
///      .unique()
///      .defaultTo('user@example.com');
/// ```
class ColumnBuilder {
  final String name;
  final String type; // SQL type string (e.g. 'varchar(255)', 'integer')

  bool _nullable = true;
  dynamic _defaultValue;
  bool _hasDefault = false;
  bool _isPrimary = false;
  bool _isUnique = false;
  bool _isUnsigned = false;
  String? _referencesColumn;
  String? _referencesTable;
  String? _onDelete;
  String? _onUpdate;

  ColumnBuilder(this.name, this.type);

  // ============================================================================
  // PUBLIC GETTERS (for SchemaCompiler access)
  // ============================================================================
  bool get isUnique => _isUnique;
  bool get isPrimary => _isPrimary;
  String? get referencesColumn => _referencesColumn;
  String? get referencesTable => _referencesTable;
  String? get onDeleteAction => _onDelete;
  String? get onUpdateAction => _onUpdate;

  // ============================================================================
  // CHAINABLE MODIFIERS
  // ============================================================================

  /// Mark column as NOT NULL.
  ColumnBuilder notNullable() {
    _nullable = false;
    return this;
  }

  /// Mark column as NULL (default).
  ColumnBuilder nullable() {
    _nullable = true;
    return this;
  }

  /// Set a default value. Supports Raw for expressions like CURRENT_TIMESTAMP.
  ColumnBuilder defaultTo(dynamic value) {
    _defaultValue = value;
    _hasDefault = true;
    return this;
  }

  /// Mark column as UNIQUE.
  ColumnBuilder unique({String? indexName}) {
    _isUnique = true;
    return this;
  }

  /// Mark column as PRIMARY KEY.
  ColumnBuilder primary({String? constraintName}) {
    _isPrimary = true;
    return this;
  }

  /// Mark numeric column as UNSIGNED.
  ColumnBuilder unsigned() {
    _isUnsigned = true;
    return this;
  }

  /// Set a foreign key reference to column in another table.
  ColumnBuilder references(String column) {
    _referencesColumn = column;
    return this;
  }

  /// Set the table for the foreign key reference.
  ColumnBuilder inTable(String table) {
    _referencesTable = table;
    return this;
  }

  /// Set the ON DELETE action for the foreign key.
  ColumnBuilder onDelete(String action) {
    _onDelete = action.toUpperCase();
    return this;
  }

  /// Set the ON UPDATE action for the foreign key.
  ColumnBuilder onUpdate(String action) {
    _onUpdate = action.toUpperCase();
    return this;
  }

  // ============================================================================
  // SQL COMPILATION
  // ============================================================================

  /// Compile to DDL SQL fragment (column definition only).
  String toSQL({String dialect = 'pg', String Function(String)? wrap}) {
    final wrapFn = wrap ?? (String v) => '"$v"';
    final parts = <String>['${wrapFn(name)} $type'];

    if (_isUnsigned && (dialect == 'mysql' || dialect == 'mysql2')) {
      parts.add('unsigned');
    }

    if (!_nullable) {
      parts.add('not null');
    }

    if (_hasDefault) {
      if (_defaultValue == null) {
        parts.add('default null');
      } else if (_defaultValue is Raw) {
        final rawSql = (_defaultValue as Raw).toSQL();
        parts.add('default ${rawSql.sql}');
      } else if (_defaultValue is bool) {
        parts.add("default '${_defaultValue ? '1' : '0'}'");
      } else if (_defaultValue is num) {
        parts.add('default $_defaultValue');
      } else if (_defaultValue is String) {
        parts.add("default '$_defaultValue'");
      } else {
        parts.add('default $_defaultValue');
      }
    }

    return parts.join(' ');
  }
}
