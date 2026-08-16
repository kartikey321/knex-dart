import '../client/client.dart';
import '../query/query_builder.dart';
import '../query/sql_string.dart';
import '../raw.dart';
import 'schema_builder.dart';
import 'table_builder.dart';

/// Compiles SchemaBuilder DDL operations into SQL statements.
///
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
        case 'createTableLike':
          _createTableLike(
            args[0] as String,
            args[1] as String,
            args.length > 2 ? args[2] as void Function(TableBuilder) : null,
          );
          break;
        case 'createView':
          _createView(args[0] as String, args[1]);
          break;
        case 'createViewOrReplace':
          _createViewOrReplace(args[0] as String, args[1]);
          break;
        case 'createMaterializedView':
          _createMaterializedView(args[0] as String, args[1]);
          break;
        case 'refreshMaterializedView':
          _refreshMaterializedView(args[0] as String, args[1] as bool);
          break;
        case 'dropView':
          _dropView(args[0] as String);
          break;
        case 'dropViewIfExists':
          _dropViewIfExists(args[0] as String);
          break;
        case 'dropMaterializedView':
          _dropMaterializedView(args[0] as String);
          break;
        case 'dropMaterializedViewIfExists':
          _dropMaterializedViewIfExists(args[0] as String);
          break;
        case 'createSchema':
          _createSchema(args[0] as String);
          break;
        case 'createSchemaIfNotExists':
          _createSchemaIfNotExists(args[0] as String);
          break;
        case 'dropSchema':
          _dropSchema(args[0] as String, args[1] as bool);
          break;
        case 'dropSchemaIfExists':
          _dropSchemaIfExists(args[0] as String, args[1] as bool);
          break;
        case 'createExtension':
          _createExtension(args[0] as String);
          break;
        case 'createExtensionIfNotExists':
          _createExtensionIfNotExists(args[0] as String);
          break;
        case 'dropExtension':
          _dropExtension(args[0] as String);
          break;
        case 'dropExtensionIfExists':
          _dropExtensionIfExists(args[0] as String);
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
        case 'renameView':
          _renameView(args[0] as String, args[1] as String);
          break;
        case 'alterTable':
          _alterTable(
            args[0] as String,
            args[1] as void Function(TableBuilder),
          );
          break;
        case 'alterView':
          _alterView(args[0] as String, args[1]);
          break;
        case 'raw':
          _raw(args[0] as String, List<dynamic>.from(args[1] as List));
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

  /// Create a table with schema copied from another table.
  void _createTableLike(
    String tableName,
    String tableNameLike, [
    void Function(TableBuilder)? callback,
  ]) {
    final tableRef = _prefixedTableName(tableName);
    final sourceRef = _prefixedTableName(tableNameLike);
    final driver = client.driverName.toLowerCase();

    if (_isPostgresLike(driver)) {
      // Redshift: `create table t (like src)` — no `including all` suffix.
      // Redshift's `LIKE` form already copies column defs, distribution, and
      // sort keys; the `INCLUDING ALL` clause is a Postgres-only extension
      // (knex.js's redshift client omits it — verified against real knex.js
      // 3.3.0). Cockroachdb supports it and knex.js's cockroachdb client
      // emits it match postgres.
      final likeSuffix = driver == 'redshift' ? '' : ' including all';
      if (callback == null) {
        _pushQuery('create table $tableRef (like $sourceRef$likeSuffix)');
        return;
      }

      final tb = TableBuilder(client, 'create', tableName);
      callback(tb);
      final extraColumns = tb.columns
          .map((c) => c.toSQL(dialect: client.driverName, wrap: _wrap))
          .toList();
      final extraSql =
          extraColumns.isEmpty ? '' : ', ${extraColumns.join(', ')}';

      _pushQuery(
        'create table $tableRef (like $sourceRef$likeSuffix$extraSql)',
      );
      _pushDeferredConstraintsForTable(tableName, tableRef, tb);
      return;
    }
    if (_isMySqlLike(driver)) {
      _pushQuery('create table $tableRef like $sourceRef');
      if (callback != null) {
        _alterTable(tableName, callback);
      }
      return;
    }
    if (_isSqliteLike(driver) || driver == 'duckdb') {
      _pushQuery(
        'create table $tableRef as select * from $sourceRef where 0=1',
      );
      if (callback != null) {
        _alterTable(tableName, callback);
      }
      return;
    }
    if (driver == 'mssql') {
      _pushQuery('SELECT * INTO $tableRef FROM $sourceRef WHERE 0=1');
      if (callback != null) {
        _alterTable(tableName, callback);
      }
      return;
    }
    throw UnsupportedError(
      'createTableLike is not supported for dialect "${client.driverName}"',
    );
  }

  void _createView(String viewName, dynamic definition) {
    final compiled = _compileSelectable(definition, operation: 'createView');
    // View DDL cannot accept parameters at parse time — Postgres/MySQL/SQLite
    // all reject `create view ... where col = $1` (or `?`). knex.js inlines
    // bound values directly into the view's SQL string at compile time
    // (verified against real knex.js 3.3.0: `create view "v" as select *
    // from "users" where "active" = true` — no bindings, the literal `true`
    // is baked into the SQL). Without this, knex-dart emitted
    // `... where "active" = $1` with a separate `[true]` bindings list,
    // which Postgres/MySQL/SQLite all reject at execution time.
    final inlinedSql = _inlineBindings(compiled.sql, compiled.bindings);
    _pushQuery('create view ${_prefixedTableName(viewName)} as $inlinedSql');
  }

  void _createViewOrReplace(String viewName, dynamic definition) {
    final compiled = _compileSelectable(
      definition,
      operation: 'createViewOrReplace',
    );
    final driver = client.driverName.toLowerCase();
    // Same view-DDL-can't-take-bindings reason as _createView — inline them.
    final inlinedSql = _inlineBindings(compiled.sql, compiled.bindings);
    if (_isSqliteLike(driver)) {
      _pushQuery('drop view if exists ${_prefixedTableName(viewName)}');
      _pushQuery('create view ${_prefixedTableName(viewName)} as $inlinedSql');
      return;
    }
    if (driver == 'mssql') {
      // MSSQL has no `CREATE OR REPLACE VIEW` — `CREATE OR ALTER VIEW` is
      // its equivalent (verified against real knex.js 3.3.0).
      _pushQuery(
        'CREATE OR ALTER VIEW ${_prefixedTableName(viewName)} AS $inlinedSql',
      );
      return;
    }
    _pushQuery(
      'create or replace view ${_prefixedTableName(viewName)} as $inlinedSql',
    );
  }

  void _createMaterializedView(String viewName, dynamic definition) {
    _ensurePostgresOnly('createMaterializedView');
    final compiled = _compileSelectable(
      definition,
      operation: 'createMaterializedView',
    );
    // Same view-DDL binding-inlining reason as _createView — see the
    // comment there. Materialized views in Postgres are equally unable to
    // accept parameters at parse time.
    final inlinedSql = _inlineBindings(compiled.sql, compiled.bindings);
    _pushQuery(
      'create materialized view ${_prefixedTableName(viewName)} as $inlinedSql',
    );
  }

  void _refreshMaterializedView(String viewName, bool concurrently) {
    _ensurePostgresOnly('refreshMaterializedView');
    _pushQuery(
      'refresh materialized view${concurrently ? ' concurrently' : ''} ${_prefixedTableName(viewName)}',
    );
  }

  void _dropView(String viewName) {
    _pushQuery('drop view ${_prefixedTableName(viewName)}');
  }

  void _dropViewIfExists(String viewName) {
    final driver = client.driverName.toLowerCase();
    if (driver == 'mssql') {
      final name = _prefixedTableName(viewName);
      _pushQuery("if object_id('$name', 'V') is not null DROP VIEW $name");
      return;
    }
    _pushQuery('drop view if exists ${_prefixedTableName(viewName)}');
  }

  void _dropMaterializedView(String viewName) {
    _ensurePostgresOnly('dropMaterializedView');
    _pushQuery('drop materialized view ${_prefixedTableName(viewName)}');
  }

  void _dropMaterializedViewIfExists(String viewName) {
    _ensurePostgresOnly('dropMaterializedViewIfExists');
    _pushQuery(
      'drop materialized view if exists ${_prefixedTableName(viewName)}',
    );
  }

  void _createSchema(String schemaName) {
    _ensurePostgresOnly('createSchema');
    _pushQuery('create schema ${_wrap(schemaName)}');
  }

  void _createSchemaIfNotExists(String schemaName) {
    _ensurePostgresOnly('createSchemaIfNotExists');
    _pushQuery('create schema if not exists ${_wrap(schemaName)}');
  }

  void _dropSchema(String schemaName, bool cascade) {
    _ensurePostgresOnly('dropSchema');
    _pushQuery('drop schema ${_wrap(schemaName)}${cascade ? ' cascade' : ''}');
  }

  void _dropSchemaIfExists(String schemaName, bool cascade) {
    _ensurePostgresOnly('dropSchemaIfExists');
    _pushQuery(
      'drop schema if exists ${_wrap(schemaName)}${cascade ? ' cascade' : ''}',
    );
  }

  void _createExtension(String extensionName) {
    _ensurePostgresOnly('createExtension');
    _pushQuery('create extension ${_wrap(extensionName)}');
  }

  void _createExtensionIfNotExists(String extensionName) {
    _ensurePostgresOnly('createExtensionIfNotExists');
    _pushQuery('create extension if not exists ${_wrap(extensionName)}');
  }

  void _dropExtension(String extensionName) {
    _ensurePostgresOnly('dropExtension');
    _pushQuery('drop extension ${_wrap(extensionName)}');
  }

  void _dropExtensionIfExists(String extensionName) {
    _ensurePostgresOnly('dropExtensionIfExists');
    _pushQuery('drop extension if exists ${_wrap(extensionName)}');
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
      columnDefs.add(
        col.toSQL(dialect: client.driverName, wrap: _wrap, tableName: tableName),
      );

      // Collect unique/FK constraints for separate ALTER TABLE statements
      if (col.isUnique) {
        deferredConstraints.add({
          'type': 'unique',
          'column': col.name,
          'table': tableName,
          'indexName': col.uniqueIndexName,
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

    // Fold a table-level PRIMARY KEY inline into the CREATE TABLE (knex.js
    // parity). This is required for SQLite, which cannot add a primary key via
    // ALTER TABLE after creation; it is also valid for Postgres/MySQL.
    var primaryInline = '';
    // ColumnBuilder.primary() is the fluent counterpart to table.primary().
    // It must participate in the CREATE TABLE primary-key clause rather than
    // being silently discarded after the column definition is compiled.
    final primaryColumn = tb.columns.where((col) => col.isPrimary).firstOrNull;
    if (primaryColumn != null && !primaryColumn.type.contains('primary key')) {
      final colStr = _wrap(primaryColumn.name);
      // MySQL/SQLite only omit the `constraint "name"` prefix when the
      // caller didn't supply one (verified against real knex.js 3.3.0:
      // `.primary()` bare omits it, but `.primary('name')` includes it
      // identically to Postgres). Previously this omitted the name
      // unconditionally on these dialects, silently dropping an explicitly
      // requested constraint name.
      final omitsConstraintName = (_isSqliteLike(client.driverName) ||
              _isMySqlLike(client.driverName)) &&
          primaryColumn.primaryConstraintName == null;
      final constraintName =
          primaryColumn.primaryConstraintName ?? '${tableName}_pkey';
      primaryInline = omitsConstraintName
          ? ', primary key ($colStr)'
          : ', constraint ${_wrap(constraintName)} primary key ($colStr)';
    }
    for (final stmt in tb.alterStatements) {
      if (stmt['method'] == 'primary') {
        final args = stmt['args'] as List;
        final cols = args[0] is List ? args[0] as List : [args[0]];
        final colStr = cols.map((c) => _wrap(c)).join(', ');
        final constraintName = args.length > 1 && args[1] != null
            ? args[1] as String
            : '${tableName}_pkey';
        primaryInline =
            ', constraint ${_wrap(constraintName)} primary key ($colStr)';
        break; // a table has at most one primary key
      }
    }

    // Fold FOREIGN KEY constraints inline for SQLite (knex.js parity). SQLite
    // cannot ALTER TABLE ADD CONSTRAINT after creation, so a deferred ALTER
    // (as used for Postgres/MySQL below) would either be invalid SQL or —
    // the previous bug here — silently dropped altogether.
    final foreignInline = StringBuffer();
    if (_isSqliteLike(client.driverName)) {
      void writeInlineForeign(
        dynamic col,
        dynamic refTable,
        dynamic refCol,
        dynamic onDelete,
        dynamic onUpdate,
      ) {
        if (refTable == null || refCol == null) return;
        foreignInline.write(
          ', foreign key (${_wrap(col)}) references ${_wrap(refTable)} (${_wrap(refCol)})',
        );
        if (onDelete != null) foreignInline.write(' on delete $onDelete');
        if (onUpdate != null) foreignInline.write(' on update $onUpdate');
      }

      for (final c in deferredConstraints) {
        if (c['type'] == 'foreign') {
          writeInlineForeign(
            c['column'],
            c['referencesTable'],
            c['referencesColumn'],
            c['onDelete'],
            c['onUpdate'],
          );
        }
      }
      for (final stmt in tb.alterStatements) {
        if (stmt['method'] == 'foreign') {
          final data = (stmt['args'] as List)[0] as Map<String, dynamic>;
          writeInlineForeign(
            data['column'],
            data['inTable'],
            data['references'],
            data['onDelete'],
            data['onUpdate'],
          );
        }
      }
    }

    // Fold FOREIGN KEY constraints inline for MSSQL too — same reasoning as
    // SQLite above, but MSSQL's inline form (like its deferred ALTER TABLE
    // form elsewhere in this file) always names the constraint, unlike
    // SQLite's bare `foreign key (...)`. Verified against real knex.js
    // 3.3.0's test/unit/schema-builder/mssql.js "adds foreign key with
    // onUpdate and onDelete": `CREATE TABLE [person] (..., CONSTRAINT
    // [person_user_id_foreign] FOREIGN KEY ([user_id]) REFERENCES [users]
    // ([id]) ON DELETE SET NULL, ...)` — a deferred `ALTER TABLE ADD
    // CONSTRAINT` (as used for Postgres/MySQL below) is never emitted for
    // MSSQL createTable.
    if (client.driverName == 'mssql') {
      void writeInlineForeignMssql(
        dynamic col,
        dynamic refTable,
        dynamic refCol,
        dynamic onDelete,
        dynamic onUpdate,
      ) {
        if (refTable == null || refCol == null) return;
        final constraintName = '${tableName}_${col}_foreign';
        foreignInline.write(
          ', constraint ${_wrap(constraintName)} foreign key (${_wrap(col)}) references ${_wrap(refTable)} (${_wrap(refCol)})',
        );
        if (onDelete != null) foreignInline.write(' on delete $onDelete');
        if (onUpdate != null) foreignInline.write(' on update $onUpdate');
      }

      for (final c in deferredConstraints) {
        if (c['type'] == 'foreign') {
          writeInlineForeignMssql(
            c['column'],
            c['referencesTable'],
            c['referencesColumn'],
            c['onDelete'],
            c['onUpdate'],
          );
        }
      }
      for (final stmt in tb.alterStatements) {
        if (stmt['method'] == 'foreign') {
          final data = (stmt['args'] as List)[0] as Map<String, dynamic>;
          writeInlineForeignMssql(
            data['column'],
            data['inTable'],
            data['references'],
            data['onDelete'],
            data['onUpdate'],
          );
        }
      }
    }

    // Main CREATE TABLE statement. `table.comment(...)` previously set
    // TableBuilder.single['comment'] but nothing ever read it, silently
    // dropping the comment on every dialect. MySQL folds it inline into the
    // CREATE TABLE statement itself (` comment = '...'`); Postgres-family
    // emits a separate `comment on table ...` statement right after (both
    // verified against real knex.js 3.3.0); SQLite has no table-comment
    // support and knex.js silently drops it there too.
    final tableRef = _prefixedTableName(tableName);
    final comment = tb.single['comment'] as String?;
    final isMySql = _isMySqlLike(client.driverName);
    final commentSuffix =
        comment != null && isMySql ? " comment = '${_escapeComment(comment)}'" : '';
    final tableBody =
        '$tableRef (${columnDefs.join(', ')}$primaryInline$foreignInline)$commentSuffix';
    final sql = prefix == 'create table if not exists' && client.driverName == 'mssql'
        // MSSQL has no `CREATE TABLE IF NOT EXISTS` — knex.js instead guards
        // with `IF OBJECT_ID(...) IS NULL CREATE TABLE ...` (verified
        // against real knex.js 3.3.0), same existence-check idiom as
        // _dropTableIfExists's mssql branch.
        ? "if object_id('$tableRef', 'U') is null CREATE TABLE $tableBody"
        : '$prefix $tableBody';
    _pushQuery(sql);

    if (comment != null && _isPostgresLike(client.driverName)) {
      _pushQuery("comment on table $tableRef is '${_escapeComment(comment)}'");
    } else if (comment != null &&
        comment.isNotEmpty &&
        client.driverName == 'mssql') {
      // MSSQL treats an empty comment as a no-op (verified against real
      // knex.js 3.3.0: `t.comment('')` compiles to zero statements there,
      // unlike Postgres/MySQL which both still emit theirs for an empty
      // string).
      _pushQuery(_mssqlCommentStatement(tableName, comment));
    }

    _pushDeferredConstraintsForTable(
      tableName,
      tableRef,
      tb,
      precomputed: deferredConstraints,
      skipPrimary: true,
    );
  }

  /// Escapes a table comment for use as a SQL string literal, dialect-aware
  /// like ColumnBuilder._sqlString: MySQL-family strings treat `\` as an
  /// escape character (NO_BACKSLASH_ESCAPES is off by default), so an
  /// unescaped backslash right before the closing quote would escape the
  /// quote itself and break out of the literal. Everywhere else, plain `'`
  /// doubling is sufficient.
  String _escapeComment(String value) {
    if (_isMySqlLike(client.driverName)) {
      return value.replaceAll('\\', r'\\').replaceAll("'", r"\'");
    }
    return value.replaceAll("'", "''");
  }

  /// MSSQL has no `COMMENT ON TABLE`/inline `COMMENT =` clause — table
  /// comments are stored as an "extended property" via
  /// sp_addextendedproperty (first time) or sp_updateextendedproperty
  /// (property already exists), guarded by an existence check. Verified
  /// against real knex.js 3.3.0, including its `withSchema()` handling
  /// (defaults to 'dbo' when no schema was set).
  String _mssqlCommentStatement(String tableName, String comment) {
    final schemaName = builder.schema ?? 'dbo';
    final escapedComment = _escapeComment(comment);
    return "IF EXISTS(SELECT * FROM sys.fn_listextendedproperty(N'MS_Description', "
        "N'Schema', N'$schemaName', N'Table', N'$tableName', NULL, NULL))\n"
        "  EXEC sys.sp_updateextendedproperty N'MS_Description', N'$escapedComment', "
        "N'Schema', N'$schemaName', N'Table', N'$tableName'\n"
        "ELSE\n"
        "  EXEC sys.sp_addextendedproperty N'MS_Description', N'$escapedComment', "
        "N'Schema', N'$schemaName', N'Table', N'$tableName'";
  }

  /// MSSQL's default `.unique()` shape: a filtered `CREATE UNIQUE INDEX`
  /// (not a `CONSTRAINT ... UNIQUE`) that excludes NULLs, since a standard
  /// MSSQL unique constraint/index otherwise allows at most one NULL row —
  /// this brings MSSQL's null semantics in line with every other dialect's
  /// unique constraint (which allows unlimited NULLs). Verified against real
  /// knex.js 3.3.0's mssql-tablecompiler.js `unique()`: default path (no
  /// `{useConstraint: true}` — which has no Dart-side call to mirror it
  /// with, knex-dart's `unique()` takes no options object) emits `CREATE
  /// UNIQUE INDEX [name] ON [table] ([cols]) WHERE [col1] IS NOT NULL [AND
  /// [col2] IS NOT NULL ...]`.
  String _mssqlUniqueIndexSql(
    String tableRef,
    String constraintName,
    List<dynamic> cols,
  ) {
    final colStr = cols.map((c) => _wrap(c)).join(', ');
    final predicate =
        cols.map((c) => '${_wrap(c)} is not null').join(' and ');
    return 'create unique index ${_wrap(constraintName)} on $tableRef ($colStr) where $predicate';
  }

  /// Drop a table
  void _dropTable(String tableName) {
    _pushQuery('drop table ${_prefixedTableName(tableName)}');
  }

  /// Drop a table if it exists
  void _dropTableIfExists(String tableName) {
    final driver = client.driverName.toLowerCase();
    if (driver == 'mssql') {
      final name = _prefixedTableName(tableName);
      _pushQuery("if object_id('$name', 'U') is not null DROP TABLE $name");
      return;
    }
    _pushQuery('drop table if exists ${_prefixedTableName(tableName)}');
  }

  /// Rename a table
  void _renameTable(String from, String to) {
    final driver = client.driverName.toLowerCase();
    if (_isMySqlLike(driver)) {
      _pushQuery('rename table ${_wrap(from)} to ${_wrap(to)}');
      return;
    }
    if (driver == 'mssql') {
      final fromName = builder.schema != null
          ? '${builder.schema}.$from'
          : from;
      _pushQuery('exec sp_rename ?, ?', [fromName, to]);
      return;
    }
    _pushQuery(
      'alter table ${_prefixedTableName(from)} rename to ${_wrap(to)}',
    );
  }

  /// Rename a view.
  void _renameView(String from, String to) {
    final driver = client.driverName.toLowerCase();
    if (_isPostgresLike(driver)) {
      _pushQuery(
        'alter view ${_prefixedTableName(from)} rename to ${_wrap(to)}',
      );
      return;
    }
    if (_isMySqlLike(driver)) {
      _pushQuery('rename table ${_wrap(from)} to ${_wrap(to)}');
      return;
    }
    if (driver == 'mssql') {
      final fromName = builder.schema != null
          ? '${builder.schema}.$from'
          : from;
      _pushQuery('exec sp_rename ?, ?', [fromName, to]);
      return;
    }
    throw UnsupportedError(
      'renameView is not supported for dialect "${client.driverName}"',
    );
  }

  /// Alter a table
  void _alterTable(String tableName, void Function(TableBuilder) callback) {
    final driver = client.driverName.toLowerCase();
    final tb = TableBuilder(client, 'alter', tableName);
    callback(tb);
    final tableRef = _prefixedTableName(tableName);

    // Handle added columns
    for (final col in tb.columns) {
      // MySQL's `ADD col_def` (no COLUMN keyword) is what knex.js emits, but
      // `ADD COLUMN col_def` is equally valid MySQL syntax — this divergence
      // is a deliberate, already-documented [ACCEPTED] cosmetic difference
      // (see schema/alter-table-add-column::mysql in schema_parity_test.dart's
      // allowlist), not something to chase here.
      final addKeyword = driver == 'mssql' ? 'add' : 'add column';
      _pushQuery(
        'alter table $tableRef $addKeyword ${col.toSQL(dialect: client.driverName, wrap: _wrap, tableName: tableName)}',
      );
    }

    // `table.comment(...)` inside alterTable — see _buildCreateTable's
    // comment handling for the dialect matrix (Postgres: separate
    // `comment on table`; MySQL: separate `alter table ... comment = ...`,
    // not inline this time since there's no CREATE TABLE statement to fold
    // into; MSSQL: sp_addextendedproperty/sp_updateextendedproperty dance,
    // see _mssqlCommentStatement; SQLite: no-op).
    final comment = tb.single['comment'] as String?;
    if (comment != null) {
      if (_isPostgresLike(client.driverName)) {
        _pushQuery("comment on table $tableRef is '${_escapeComment(comment)}'");
      } else if (_isMySqlLike(client.driverName)) {
        _pushQuery("alter table $tableRef comment = '${_escapeComment(comment)}'");
      } else if (client.driverName == 'mssql' && comment.isNotEmpty) {
        _pushQuery(_mssqlCommentStatement(tableName, comment));
      }
    }

    // A fluent `.unique()` declared on a newly-added column is a deferred
    // unique constraint in knex.js (same shape as the deferred foreign-key/
    // primary-key handling below). Previously it was compiled as only ADD
    // COLUMN, silently losing the constraint. Statement-ordering caveat:
    // knex.js interleaves constraint statements in column-declaration order
    // and batches every ADD COLUMN into a single comma-joined statement —
    // both left as-is here (pre-existing, separately tracked gap; see the
    // schema-parity harness's alter-table-add-* [OPEN BUG] entries).
    for (final col in tb.columns) {
      if (!col.isUnique) continue;
      final constraintName = col.uniqueIndexName ?? '${tableName}_${col.name}_unique';
      if (_isSqliteLike(client.driverName)) {
        _pushQuery(
          'create unique index ${_wrap(constraintName)} on $tableRef (${_wrap(col.name)})',
        );
      } else if (_isMySqlLike(client.driverName)) {
        _pushQuery(
          'alter table $tableRef add unique ${_wrap(constraintName)}(${_wrap(col.name)})',
        );
      } else if (client.driverName == 'mssql') {
        _pushQuery(_mssqlUniqueIndexSql(tableRef, constraintName, [col.name]));
      } else {
        _pushQuery(
          'alter table $tableRef add constraint ${_wrap(constraintName)} unique (${_wrap(col.name)})',
        );
      }
    }

    // A reference declared on a newly-added column is a deferred foreign-key
    // constraint in knex.js. Previously it was compiled as only ADD COLUMN,
    // silently losing the constraint.
    for (final col in tb.columns) {
      if (col.referencesColumn == null || col.referencesTable == null) continue;
      if (_isSqliteLike(client.driverName)) {
        throw UnsupportedError(
          'foreign is not supported on an existing SQLite table — '
          'declare it in createTable, or recreate the table instead',
        );
      }
      final constraintName = '${tableName}_${col.name}_foreign';
      var fk =
          'alter table $tableRef add constraint ${_wrap(constraintName)} foreign key (${_wrap(col.name)}) references ${_wrap(col.referencesTable!)} (${_wrap(col.referencesColumn!)})';
      if (col.onDeleteAction != null) fk += ' on delete ${col.onDeleteAction}';
      if (col.onUpdateAction != null) fk += ' on update ${col.onUpdateAction}';
      _pushQuery(fk);
    }

    // A column-level .primary() declared on a newly-added column is a
    // deferred primary-key constraint in knex.js (same shape as the
    // deferred foreign-key handling above). Previously it was compiled as
    // only ADD COLUMN, silently losing the constraint.
    for (final col in tb.columns) {
      if (!col.isPrimary) continue;
      if (_isSqliteLike(client.driverName)) {
        throw UnsupportedError(
          'primary is not supported on an existing SQLite table — '
          'declare it in createTable, or recreate the table instead',
        );
      }
      final constraintName = col.primaryConstraintName ?? '${tableName}_pkey';
      final colStr = _wrap(col.name);
      if (_isMySqlLike(client.driverName)) {
        _pushQuery(
          'alter table $tableRef add primary key ${_wrap(constraintName)}($colStr)',
        );
      } else {
        _pushQuery(
          'alter table $tableRef add constraint ${_wrap(constraintName)} primary key ($colStr)',
        );
      }
    }

    // Handle alter statements
    for (final stmt in tb.alterStatements) {
      final method = stmt['method'] as String;
      final args = stmt['args'] as List;

      switch (method) {
        case 'dropColumn':
          _pushQuery('alter table $tableRef drop column ${_wrap(args[0])}');
          break;
        case 'dropColumns':
          // knex.js emits a single combined `alter table t drop column X,
          // drop column Y` statement (or `drop X, drop Y` for MySQL-family)
          // — verified against real knex.js 3.3.0 for pg/mysql/sqlite/
          // redshift. SQLite's own ALTER TABLE grammar only allows one
          // operation per statement anyway (a comma-joined multi-drop is a
          // syntax error there), and knex.js reroutes through a PRAGMA-based
          // table rebuild instead (see the `alter-table-drop-column::sqlite`
          // ACCEPTED entry) — not implemented here for the same reason, so
          // SQLite falls back to one valid statement per column.
          if (_isSqliteLike(client.driverName)) {
            for (final col in args) {
              _pushQuery('alter table $tableRef drop column ${_wrap(col)}');
            }
          } else if (_isMySqlLike(client.driverName)) {
            final dropParts = args.map((col) => 'drop ${_wrap(col)}').join(', ');
            _pushQuery('alter table $tableRef $dropParts');
          } else {
            final dropParts =
                args.map((col) => 'drop column ${_wrap(col)}').join(', ');
            _pushQuery('alter table $tableRef $dropParts');
          }
          break;
        case 'renameColumn':
          if (client.driverName == 'mssql') {
            // MSSQL uses sp_rename with bindings to avoid injection. The
            // object-name binding is `<wrapped, schema-prefixed table
            // name>.<raw column name>` — matching knex.js's
            // `this.tableName() + '.' + from` exactly (tableName() already
            // wraps with brackets and includes the schema prefix; see
            // _prefixedTableName). The literal `'COLUMN'` type-of-object
            // argument is NOT a bound parameter in knex.js — it's baked
            // directly into the SQL text (verified against real knex.js
            // 3.3.0's mssql-tablecompiler.js `renameColumn`, and
            // test/unit/schema-builder/mssql.js's "rename column of view"
            // case, which asserts exactly 2 bindings and a literal
            // `'COLUMN'` in the sql string). Previously this bound it as a
            // 3rd `?` placeholder — wrong statement shape, not just cosmetic.
            final objectName = '${_prefixedTableName(tableName)}.${args[0]}';
            _pushQuery("exec sp_rename ?, ?, 'COLUMN'", [
              objectName,
              args[1],
            ]);
          } else if (client.driverName == 'mysql' ||
              client.driverName == 'mysql2' ||
              client.driverName == 'mariadb') {
            // MySQL 8+ / MariaDB require the COLUMN keyword.
            _pushQuery(
              'alter table $tableRef rename column ${_wrap(args[0])} to ${_wrap(args[1])}',
            );
          } else {
            // PostgreSQL, SQLite 3.25+, DuckDB — no COLUMN keyword needed.
            _pushQuery(
              'alter table $tableRef rename ${_wrap(args[0])} to ${_wrap(args[1])}',
            );
          }
          break;
        case 'unique':
          final cols = args[0] is List ? args[0] as List : [args[0]];
          final colStr = cols.map((c) => _wrap(c)).join(', ');
          final constraintName = args.length > 1 && args[1] != null
              ? args[1] as String
              : '${tableName}_${cols.join('_')}_unique';
          if (_isSqliteLike(client.driverName)) {
            _pushQuery(
              'create unique index ${_wrap(constraintName)} on $tableRef ($colStr)',
            );
          } else if (_isMySqlLike(client.driverName)) {
            _pushQuery(
              'alter table $tableRef add unique ${_wrap(constraintName)}($colStr)',
            );
          } else if (client.driverName == 'mssql') {
            _pushQuery(_mssqlUniqueIndexSql(tableRef, constraintName, cols));
          } else {
            _pushQuery(
              'alter table $tableRef add constraint ${_wrap(constraintName)} unique ($colStr)',
            );
          }
          break;
        case 'index':
          if (client.driverName == 'redshift') {
            throw UnsupportedError(
              'index creation is not supported on Redshift',
            );
          }
          final cols = args[0] is List ? args[0] as List : [args[0]];
          final colStr = cols.map((c) => _wrap(c)).join(', ');
          final indexName = args.length > 1 && args[1] != null
              ? args[1]
              : '${tableName}_${cols.join('_')}_index';
          _pushQuery('create index ${_wrap(indexName)} on $tableRef ($colStr)');
          break;
        case 'fulltext':
          final cols = args[0] is List ? args[0] as List : [args[0]];
          final colStr = cols.map((c) => _wrap(c)).join(', ');
          final indexName = args.length > 1 && args[1] != null ? args[1] : null;
          if (client.driverName == 'mysql' ||
              client.driverName == 'mysql2' ||
              client.driverName == 'mariadb') {
            final indexPart = indexName != null ? ' ${_wrap(indexName)}' : '';
            _pushQuery(
              'alter table $tableRef add fulltext$indexPart ($colStr)',
            );
          } else {
            throw UnsupportedError(
              'fulltext index is only supported for mysql/mariadb dialects',
            );
          }
          break;
        case 'dropIndex':
          if (client.driverName == 'redshift') {
            throw UnsupportedError(
              'index deletion is not supported on Redshift',
            );
          }
          // When no explicit name is given, derive it from the columns using
          // the same scheme as index creation (knex.js parity), instead of
          // silently doing nothing.
          final cols = args[0] is List ? args[0] as List : [args[0]];
          final indexName = args.length > 1 && args[1] != null
              ? args[1]
              : '${tableName}_${cols.join('_')}_index';
          if (client.driverName == 'mysql' ||
              client.driverName == 'mysql2' ||
              client.driverName == 'mariadb' ||
              client.driverName == 'mssql') {
            // MySQL and MSSQL both require ON <table> to identify the index
            // (verified against real knex.js 3.3.0 for mssql, including
            // withSchema() qualifying the table, not the index name).
            _pushQuery('drop index ${_wrap(indexName)} on $tableRef');
          } else if (_isPostgresLike(client.driverName)) {
            // Postgres-family DROP INDEX qualifies the index name itself
            // with the schema (not the table) — `"schema"."index_name"`,
            // matching knex.js. SQLite-family ignores withSchema() here
            // entirely (verified against real knex.js 3.3.0), so only
            // postgres-family gets the prefix.
            _pushQuery('drop index ${_prefixedTableName(indexName as String)}');
          } else {
            _pushQuery('drop index ${_wrap(indexName)}');
          }
          break;
        case 'dropForeign':
          if (_isSqliteLike(client.driverName)) {
            throw UnsupportedError(
              'dropForeign is not supported on an existing SQLite table — '
              'recreate the table instead',
            );
          }
          final cols = args[0] is List ? args[0] as List : [args[0]];
          final constraintName = args.length > 1 && args[1] != null
              ? args[1]
              : '${tableName}_${cols.join('_')}_foreign';
          if (client.driverName == 'mysql' ||
              client.driverName == 'mysql2' ||
              client.driverName == 'mariadb') {
            _pushQuery(
              'alter table $tableRef drop foreign key ${_wrap(constraintName)}',
            );
          } else {
            _pushQuery(
              'alter table $tableRef drop constraint ${_wrap(constraintName)}',
            );
          }
          break;
        case 'foreign':
          // Fluent foreign key from table.foreign('col').references('id').inTable('t')
          if (_isSqliteLike(client.driverName)) {
            throw UnsupportedError(
              'foreign is not supported on an existing SQLite table — '
              'declare it in createTable, or recreate the table instead',
            );
          }
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
          // SQLite: same one-operation-per-statement limitation as
          // dropColumns above — comma-joining is a syntax error there.
          if (_isSqliteLike(client.driverName)) {
            for (final col in args) {
              _pushQuery('alter table $tableRef drop column ${_wrap(col)}');
            }
          } else if (_isMySqlLike(client.driverName)) {
            // Includes mariadb (which uses the same `drop X` spelling as mysql).
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
        case 'primary':
          if (_isSqliteLike(client.driverName)) {
            throw UnsupportedError(
              'primary is not supported on an existing SQLite table — '
              'declare it in createTable, or recreate the table instead',
            );
          }
          final cols = args[0] is List ? args[0] as List : [args[0]];
          final colStr = cols.map((c) => _wrap(c)).join(', ');
          final constraintName = args.length > 1 && args[1] != null
              ? args[1] as String
              : '${tableName}_pkey';
          if (_isMySqlLike(client.driverName)) {
            _pushQuery(
              'alter table $tableRef add primary key ${_wrap(constraintName)}($colStr)',
            );
          } else {
            _pushQuery(
              'alter table $tableRef add constraint ${_wrap(constraintName)} primary key ($colStr)',
            );
          }
          break;
        case 'dropPrimary':
          if (client.driverName == 'mysql' ||
              client.driverName == 'mysql2' ||
              client.driverName == 'mariadb') {
            _pushQuery('alter table $tableRef drop primary key');
          } else if (_isSqliteLike(client.driverName)) {
            throw UnsupportedError(
              'dropPrimary is not supported on an existing SQLite table — '
              'recreate the table instead',
            );
          } else {
            final constraintName = args.isNotEmpty && args[0] != null
                ? args[0]
                : '${tableName}_pkey';
            _pushQuery(
              'alter table $tableRef drop constraint ${_wrap(constraintName)}',
            );
          }
          break;
        case 'dropUnique':
          final cols = args[0] is List ? args[0] as List : [args[0]];
          final constraintName = args.length > 1 && args[1] != null
              ? args[1]
              : '${tableName}_${(cols).join('_')}_unique';
          if (_isSqliteLike(client.driverName)) {
            _pushQuery('drop index ${_wrap(constraintName)}');
          } else if (client.driverName == 'mysql' ||
              client.driverName == 'mysql2' ||
              client.driverName == 'mariadb') {
            _pushQuery(
              'alter table $tableRef drop index ${_wrap(constraintName)}',
            );
          } else if (client.driverName == 'mssql') {
            // MSSQL creates unique constraints as indexes (CREATE UNIQUE
            // INDEX, see the 'unique' case above), so they're dropped like
            // any other index — DROP INDEX ... ON <table>, not ALTER TABLE
            // ... DROP CONSTRAINT (verified against real knex.js 3.3.0,
            // including withSchema() qualifying the table name).
            _pushQuery(
              'drop index ${_wrap(constraintName)} on $tableRef',
            );
          } else {
            _pushQuery(
              'alter table $tableRef drop constraint ${_wrap(constraintName)}',
            );
          }
          break;
        case 'setNullable':
          if (_isSqliteLike(client.driverName)) {
            throw UnsupportedError(
              'setNullable is not supported for SQLite — recreate the table instead',
            );
          }
          _pushQuery(
            'alter table $tableRef alter column ${_wrap(args[0])} drop not null',
          );
          break;
        case 'dropNullable':
          if (_isSqliteLike(client.driverName)) {
            throw UnsupportedError(
              'dropNullable is not supported for SQLite — recreate the table instead',
            );
          }
          _pushQuery(
            'alter table $tableRef alter column ${_wrap(args[0])} set not null',
          );
          break;
      }
    }
  }

  /// Alter a view definition (compiled as CREATE OR REPLACE VIEW).
  void _alterView(String viewName, dynamic definition) {
    final compiled = _compileSelectable(definition, operation: 'alterView');
    final driver = client.driverName.toLowerCase();
    if (_isSqliteLike(driver)) {
      _pushQuery('drop view if exists ${_prefixedTableName(viewName)}');
      _pushQuery(
        'create view ${_prefixedTableName(viewName)} as ${compiled.sql}',
        compiled.bindings,
      );
      return;
    }
    _pushQuery(
      'create or replace view ${_prefixedTableName(viewName)} as ${compiled.sql}',
      compiled.bindings,
    );
  }

  void _raw(String sql, List<dynamic> bindings) {
    _pushQuery(sql, bindings);
  }

  /// Inline bindings back into a SQL string as escaped literals. Used only
  /// for view-DDL compile paths (`_createView`/`_createViewOrReplace`/
  /// `_createMaterializedView`) — Postgres/MySQL/SQLite view DDL cannot
  /// accept parameters at parse time, so knex.js inlines the values at
  /// compile time (verified against real knex.js 3.3.0:
  /// `create view "v" as select * from "users" where "active" = true` —
  /// no bindings, the literal `true` is baked into the SQL string). This
  /// mirrors that by replacing `?` and `$N` placeholders (the dialect's
  /// parameter shape) with the dialect-escaped value, in binding order.
  ///
  /// Escaping follows the same family rules as `column_builder.dart`'s
  /// `_sqlString`:
  /// - Postgres-family: doubles `'` and `\`, prefixing `E` only when the
  ///   value actually contains a backslash.
  /// - MySQL-family: full C-style escape sequences including backslash.
  /// - SQLite-family and everything else: plain `'` doubling only.
  /// Booleans become `'1'`/`'0'` (MySQL/SQLite convention) — TODO:
  /// pg-native `true`/`false`. Numbers and `null` are emitted bare.
  String _inlineBindings(String sql, List<dynamic> bindings) {
    if (bindings.isEmpty) return sql;
    final driver = client.driverName;
    final isPg = _postgresLikeSet.contains(driver);
    final isMysql = _mysqlLikeSet.contains(driver);
    String escapeValue(dynamic v) {
      if (v == null) return 'null';
      if (v is bool) {
        // knex.js inlines `true`/`false` (bare SQL booleans) for a boolean
        // binding across ALL dialects' view DDL — verified against real
        // knex.js 3.3.0 for pg, mysql2, sqlite3, cockroachdb, redshift
        // (all emit `... where "active" = true`, never `'1'`/`'0'`).
        // Without this, knex-dart emitted `'1'` for mysql/sqlite-family
        // matching the boolean-column-storage convention — wrong here
        // because the bound value is the literal `true` (boolean-typed),
        // not a `1`/`0` integer masquerading as boolean.
        return v ? 'true' : 'false';
      }
      if (v is num) return v.toString();
      if (v is String) {
        if (isPg) {
          var hasBackslash = false;
          final buf = StringBuffer("'");
          for (final rune in v.runes) {
            final ch = String.fromCharCode(rune);
            if (ch == "'") {
              buf.write("''");
            } else if (ch == '\\') {
              buf.write(r'\\');
              hasBackslash = true;
            } else {
              buf.write(ch);
            }
          }
          buf.write("'");
          final escaped = buf.toString();
          return hasBackslash ? 'E$escaped' : escaped;
        }
        if (isMysql) {
          final buf = StringBuffer("'");
          for (final rune in v.runes) {
            final ch = String.fromCharCode(rune);
            buf.write(_mysqlEscapesInline[ch] ?? ch);
          }
          buf.write("'");
          return buf.toString();
        }
        // sqlite and everything else: plain `'` doubling
        return "'${v.replaceAll("'", "''")}'";
      }
      // Fall back to .toString() for any other type — same as the
      // `formatValue` default in `knex_query.dart`.
      return v.toString();
    }

    // Replace placeholders in order. Postgres placeholders are `$N`
    // (1-indexed); mysql/sqlite are `?`. Replace each occurrence with the
    // next binding's escaped literal.
    var result = sql;
    var bi = 0;
    // Postgres `\$N` — match the N-th placeholder, swap for bindings[N-1].
    if (isPg) {
      result = result.replaceAllMapped(
        RegExp(r'\$(\d+)'),
        (m) => bi < bindings.length ? escapeValue(bindings[bi++]) : m[0]!,
      );
      return result;
    }
    // mysql/sqlite `?` — replace each occurrence with the next binding.
    result = result.replaceAllMapped(
      RegExp(r'\?'),
      (m) => bi < bindings.length ? escapeValue(bindings[bi++]) : m[0]!,
    );
    return result;
  }

  static const _postgresLikeSet = {
    'pg',
    'postgres',
    'postgresql',
    'cockroachdb',
    'redshift',
  };
  static const _mysqlLikeSet = {'mysql', 'mysql2', 'mariadb'};
  static const _mysqlEscapesInline = {
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

  ({String sql, List<dynamic> bindings}) _compileSelectable(
    dynamic value, {
    required String operation,
  }) {
    if (value is String) {
      return (sql: value, bindings: const []);
    }
    if (value is Raw) {
      final sql = value.toSQL();
      return (sql: sql.sql, bindings: List<dynamic>.from(sql.bindings));
    }
    if (value is QueryBuilder) {
      final sql = value.toSQL();
      return (sql: sql.sql, bindings: List<dynamic>.from(sql.bindings));
    }
    if (value is SqlString) {
      return (sql: value.sql, bindings: List<dynamic>.from(value.bindings));
    }
    throw ArgumentError(
      '$operation requires a SQL definition as String, Raw, QueryBuilder, or SqlString',
    );
  }

  bool _isPostgresLike(String driver) =>
      driver == 'pg' ||
      driver == 'postgres' ||
      driver == 'postgresql' ||
      driver == 'cockroachdb' ||
      driver == 'redshift';

  bool _isMySqlLike(String driver) =>
      driver == 'mysql' || driver == 'mysql2' || driver == 'mariadb';

  bool _isSqliteLike(String driver) =>
      driver == 'sqlite' ||
      driver == 'sqlite3' ||
      driver == 'turso' ||
      driver == 'd1';

  void _pushDeferredConstraintsForTable(
    String tableName,
    String tableRef,
    TableBuilder tb, {
    List<Map<String, dynamic>>? precomputed,
    bool skipPrimary = false,
  }) {
    final deferredConstraints = precomputed ?? <Map<String, dynamic>>[];
    if (precomputed == null) {
      for (final col in tb.columns) {
        if (col.isUnique) {
          deferredConstraints.add({
            'type': 'unique',
            'column': col.name,
            'table': tableName,
            'indexName': col.uniqueIndexName,
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
    }

    for (final constraint in deferredConstraints) {
      if (constraint['type'] == 'unique') {
        final col = constraint['column'];
        final constraintName =
            (constraint['indexName'] as String?) ?? '${tableName}_${col}_unique';
        if (_isSqliteLike(client.driverName)) {
          _pushQuery(
            'create unique index ${_wrap(constraintName)} on $tableRef (${_wrap(col)})',
          );
        } else if (_isMySqlLike(client.driverName)) {
          // MySQL's ADD UNIQUE has its own shape — no `constraint` keyword,
          // no space before the column list — verified against real knex.js
          // 3.3.0: `alter table t add unique t_email_unique(email)`.
          _pushQuery(
            'alter table $tableRef add unique ${_wrap(constraintName)}(${_wrap(col)})',
          );
        } else if (client.driverName == 'mssql') {
          _pushQuery(_mssqlUniqueIndexSql(tableRef, constraintName, [col]));
        } else {
          _pushQuery(
            'alter table $tableRef add constraint ${_wrap(constraintName)} unique (${_wrap(col)})',
          );
        }
      } else if (constraint['type'] == 'foreign') {
        if (_isSqliteLike(client.driverName) || client.driverName == 'mssql') {
          // SQLite cannot ALTER TABLE ADD CONSTRAINT for foreign keys at all.
          // MSSQL *can*, but knex.js instead folds every createTable foreign
          // key inline into the CREATE TABLE statement itself (see
          // _buildCreateTable's mssql-specific foreignInline block above) —
          // this deferred path is never reached for mssql createTable.
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

    for (final stmt in tb.alterStatements) {
      final method = stmt['method'] as String;
      final args = stmt['args'] as List;

      if (method == 'foreign') {
        if (_isSqliteLike(client.driverName) || client.driverName == 'mssql') {
          // Create-time only (this loop never runs for a real alterTable —
          // see _alterTable's own 'foreign' case, which throws instead).
          // SQLite can't ALTER TABLE ADD CONSTRAINT for foreign keys at all;
          // MSSQL can, but knex.js instead folds every createTable foreign
          // key inline (fluent .foreign() included) into the CREATE TABLE
          // statement itself — see _buildCreateTable's mssql-specific
          // foreignInline block, which already handles this same
          // tb.alterStatements 'foreign' case. Without this skip, mssql
          // foreign keys were emitted twice: once inline, once here.
          continue;
        }
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
      } else if (method == 'index') {
        if (client.driverName == 'redshift') {
          throw UnsupportedError(
            'index creation is not supported on Redshift',
          );
        }
        final cols = args[0] is List ? args[0] as List : [args[0]];
        final colStr = cols.map((c) => _wrap(c)).join(', ');
        final indexName = args.length > 1 && args[1] != null
            ? args[1] as String
            : '${tableName}_${cols.join('_')}_index';
        _pushQuery('create index ${_wrap(indexName)} on $tableRef ($colStr)');
      } else if (method == 'unique') {
        final cols = args[0] is List ? args[0] as List : [args[0]];
        final colStr = cols.map((c) => _wrap(c)).join(', ');
        final constraintName = args.length > 1 && args[1] != null
            ? args[1] as String
            : '${tableName}_${cols.join('_')}_unique';
        if (_isSqliteLike(client.driverName)) {
          _pushQuery(
            'create unique index ${_wrap(constraintName)} on $tableRef ($colStr)',
          );
        } else if (client.driverName == 'mssql') {
          _pushQuery(_mssqlUniqueIndexSql(tableRef, constraintName, cols));
        } else {
          _pushQuery(
            'alter table $tableRef add constraint ${_wrap(constraintName)} unique ($colStr)',
          );
        }
      } else if (method == 'primary' && !skipPrimary) {
        // Only reached for create-table-like paths (Postgres) that cannot fold
        // the key inline; normal createTable folds it into the CREATE statement.
        final cols = args[0] is List ? args[0] as List : [args[0]];
        final colStr = cols.map((c) => _wrap(c)).join(', ');
        final constraintName = args.length > 1 && args[1] != null
            ? args[1] as String
            : '${tableName}_pkey';
        _pushQuery(
          'alter table $tableRef add constraint ${_wrap(constraintName)} primary key ($colStr)',
        );
      }
    }
  }

  void _ensurePostgresOnly(String operation) {
    final driver = client.driverName.toLowerCase();
    if (!_isPostgresLike(driver)) {
      throw UnsupportedError(
        '$operation is not supported for dialect "${client.driverName}"',
      );
    }
  }

  void _pushQuery(String sql, [List<dynamic> bindings = const []]) {
    sequence.add({'sql': sql, 'bindings': bindings});
  }
}
