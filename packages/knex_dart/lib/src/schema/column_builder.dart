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
  /// Whether `.nullable()` was explicitly called (vs. the implicit default
  /// nullable state). knex.js's `nullable` column modifier only fires when
  /// the caller explicitly invoked `.nullable()`/`.notNullable()` (it checks
  /// a `modified` set, not the resolved boolean) — mirrored here so the
  /// mssql-only explicit `null` suffix in [toSQL] doesn't fire on every
  /// bare, never-touched column (verified against real knex.js 3.3.0's
  /// `nvarchar(255)` with no suffix for a bare `t.string('foo')`).
  bool _nullableExplicit = false;
  dynamic _defaultValue;
  bool _hasDefault = false;
  bool _isPrimary = false;
  String? _primaryConstraintName;
  bool _isUnique = false;
  String? _uniqueIndexName;
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
  String? get uniqueIndexName => _uniqueIndexName;
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
    _nullableExplicit = true;
    return this;
  }

  /// Set a default value. Supports Raw for expressions like CURRENT_TIMESTAMP.
  ColumnBuilder defaultTo(dynamic value) {
    _defaultValue = value;
    _hasDefault = true;
    return this;
  }

  /// Mark column as UNIQUE. [indexName] overrides the default
  /// `<table>_<column>_unique` constraint/index name.
  ColumnBuilder unique({String? indexName}) {
    _isUnique = true;
    _uniqueIndexName = indexName;
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

  /// Set a foreign key reference to column in another table. Accepts either
  /// a bare column name (paired with a following `.inTable(...)` call) or
  /// knex.js's `'table.column'` dotted shorthand, which sets both the
  /// referenced table and column in one call. An explicit `.inTable(...)`
  /// after the dotted form still overrides the table, matching knex.js.
  ColumnBuilder references(String column) {
    final dot = column.lastIndexOf('.');
    if (dot == -1) {
      _referencesColumn = column;
    } else {
      _referencesTable = column.substring(0, dot);
      _referencesColumn = column.substring(dot + 1);
    }
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
  ///
  /// [tableName] is only used for MSSQL, which names every DEFAULT as its
  /// own constraint (`CONSTRAINT [table_col_default] DEFAULT ...` instead of
  /// a bare `DEFAULT ...`) — verified against real knex.js 3.3.0's
  /// mssql-columncompiler.js `defaultTo()`. It's optional/nullable because
  /// every other dialect ignores it.
  String toSQL({
    String dialect = 'pg',
    String Function(String)? wrap,
    String? tableName,
  }) {
    final wrapFn = wrap ?? (String v) => '"$v"';
    final parts = <String>['${wrapFn(name)} $type'];

    if (_isUnsigned &&
        (dialect == 'mysql' || dialect == 'mysql2' || dialect == 'mariadb')) {
      parts.add('unsigned');
    }

    if (!_nullable) {
      parts.add('not null');
    } else if (dialect == 'mssql' && _nullableExplicit) {
      // knex.js only emits the modifier when the caller explicitly called
      // .nullable() (it checks a "was this modifier touched" set, not the
      // resolved boolean) — a bare, never-touched column stays implicitly
      // nullable with no suffix. See _nullableExplicit's doc comment.
      parts.add('null');
    }

    if (_hasDefault) {
      final valueSql = _formatDefaultValue(dialect);
      if (dialect == 'mssql' && tableName != null) {
        final constraintName = '${tableName}_${name}_default'.toLowerCase();
        parts.add('CONSTRAINT ${wrapFn(constraintName)} DEFAULT $valueSql');
      } else {
        parts.add('default $valueSql');
      }
    }

    return parts.join(' ');
  }

  /// Formats [_defaultValue] as a bare SQL value expression, WITHOUT the
  /// leading `default`/`DEFAULT` keyword — callers prepend that themselves
  /// (differently per dialect; see [toSQL]'s MSSQL `CONSTRAINT ... DEFAULT`
  /// wrapping).
  String _formatDefaultValue(String dialect) {
    if (_defaultValue == null) {
      return 'null';
    } else if (_defaultValue is Raw) {
      final rawSql = (_defaultValue as Raw).toSQL();
      return rawSql.sql;
    } else if (_defaultValue is bool) {
      return "'${_defaultValue ? '1' : '0'}'";
    } else if (_defaultValue is num) {
      return '$_defaultValue';
    } else if (_defaultValue is String) {
      return _sqlString(_defaultValue as String, dialect);
    } else if (isJson && (_defaultValue is Map || _defaultValue is List)) {
      final value = _sqlString(jsonEncode(_defaultValue), dialect);
      // MySQL 8 requires a JSON literal default to be an expression. knex.js
      // therefore emits DEFAULT ('{}') rather than DEFAULT '{}'.
      final isMySql =
          dialect == 'mysql' || dialect == 'mysql2' || dialect == 'mariadb';
      return isMySql ? '($value)' : value;
    } else {
      return _sqlString(_defaultValue.toString(), dialect);
    }
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
