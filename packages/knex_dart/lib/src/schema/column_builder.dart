import 'dart:convert';

import 'package:knex_dart/src/raw.dart';

/// A fluent builder for a column definition in a CREATE TABLE or ALTER TABLE statement.
///
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

  /// Whether this column was declared via `.json()`/`.jsonb()`. Tracked
  /// independently of [type] because some dialects (e.g. Redshift) map the
  /// JSON logical type to a SQL type name — `varchar(max)` — that doesn't
  /// literally say "json"; a `type`-string check would silently stop
  /// JSON-encoding Map/List defaults for those dialects.
  final bool isJson;

  bool _nullable = true;
  dynamic _defaultValue;
  bool _hasDefault = false;
  bool _isPrimary = false;
  String? _primaryConstraintName;
  bool _isUnique = false;
  bool _isUnsigned = false;
  String? _referencesColumn;
  String? _referencesTable;
  String? _onDelete;
  String? _onUpdate;

  ColumnBuilder(this.name, this.type, {this.isJson = false});

  // ============================================================================
  // PUBLIC GETTERS (for SchemaCompiler access)
  // ============================================================================
  bool get isUnique => _isUnique;
  bool get isPrimary => _isPrimary;
  String? get primaryConstraintName => _primaryConstraintName;
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
    _primaryConstraintName = constraintName;
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

    // `unsigned` is MySQL-family grammar only (postgres/sqlite silently
    // ignore it — verified against real knex.js). Use the family-aware
    // `_mysqlLike` set so mariadb (which emits driver-name `'mariadb'`,
    // not `'mysql2'`) is dispatched correctly — previously this used a
    // bare `dialect == 'mysql' || dialect == 'mysql2'` check that silently
    // dropped the `unsigned` modifier on mariadb.
    if (_isUnsigned && _mysqlLike.contains(dialect)) {
      parts.add('unsigned');
    }

    if (!_nullable) {
      parts.add('not null');
    } else if (dialect == 'mssql') {
      parts.add('null');
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
        parts.add('default ${_sqlString(_defaultValue as String, dialect)}');
      } else if (isJson && (_defaultValue is Map || _defaultValue is List)) {
        final value = _sqlString(jsonEncode(_defaultValue), dialect);
        // MySQL 8 requires a JSON literal default to be an expression. knex.js
        // therefore emits DEFAULT ('{}') rather than DEFAULT '{}'.
        final isMySql = _mysqlLike.contains(dialect);
        parts.add('default ${isMySql ? '($value)' : value}');
      } else {
        parts.add('default ${_sqlString(_defaultValue.toString(), dialect)}');
      }
    }

    return parts.join(' ');
  }

  static const _postgresLike = {
    'pg',
    'postgres',
    'postgresql',
    'cockroachdb',
    'redshift',
  };
  static const _mysqlLike = {'mysql', 'mysql2', 'mariadb'};

  /// C-style escape map matching knex.js's generic `escapeString` (used by
  /// its MySQL client, and the fallback for any dialect without a
  /// dialect-specific `_escapeBinding`, e.g. Redshift/CockroachDB share
  /// Postgres's; sqlite/mssql/duckdb/bigquery/snowflake fall back to plain
  /// quote-doubling in knex.js, so they get that below instead).
  static const _mysqlEscapes = {
    '\x00': r'\0',
    '\b': r'\b',
    '\t': r'\t',
    '\n': r'\n',
    '\r': r'\r',
    '\x1a': r'\Z',
    '"': r'\"',
    "'": r"\'",
    '\\': r'\\',
  };

  /// Quote a string for use as a SQL literal, with dialect-aware escaping
  /// matching knex.js's per-client `_escapeBinding`:
  /// - Postgres-family: doubles `'` and `\`, prefixing `E` only when the
  ///   value actually contains a backslash (`Client_PG.escapeString`).
  /// - MySQL-family: full C-style escape sequences, including backslash
  ///   (knex.js's generic `escapeString`, used by its MySQL client).
  /// - Everything else: plain `'` doubling only, no backslash handling —
  ///   matches knex.js's base `Client.prototype._escapeBinding`, which is
  ///   what sqlite/mssql/duckdb/bigquery/snowflake fall back to (none of
  ///   them override it).
  String _sqlString(String value, String dialect) {
    if (_postgresLike.contains(dialect)) {
      var hasBackslash = false;
      final buffer = StringBuffer("'");
      for (final rune in value.runes) {
        final ch = String.fromCharCode(rune);
        if (ch == "'") {
          buffer.write("''");
        } else if (ch == '\\') {
          buffer.write(r'\\');
          hasBackslash = true;
        } else {
          buffer.write(ch);
        }
      }
      buffer.write("'");
      final escaped = buffer.toString();
      return hasBackslash ? 'E$escaped' : escaped;
    }
    if (_mysqlLike.contains(dialect)) {
      final buffer = StringBuffer("'");
      for (final rune in value.runes) {
        final ch = String.fromCharCode(rune);
        buffer.write(_mysqlEscapes[ch] ?? ch);
      }
      buffer.write("'");
      return buffer.toString();
    }
    return "'${value.replaceAll("'", "''")}'";
  }
}
