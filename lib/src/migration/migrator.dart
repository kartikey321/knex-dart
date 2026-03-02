import '../client/knex_config.dart';
import '../knex.dart';
import '../schema/json_schema_adapter.dart';
import '../schema/schema_ast.dart';
import '../util/knex_exception.dart';
import 'migration.dart';
import 'migration_source.dart';

class Migrator {
  final Knex _knex;
  final List<MigrationUnit> _migrations;
  final List<MigrationSource> _sources;
  final MigrationConfig _config;

  Migrator(
    this._knex, {
    List<MigrationUnit> migrations = const [],
    List<MigrationSource> sources = const [],
    MigrationConfig? config,
  }) : _migrations = List.unmodifiable(migrations),
       _sources = List.unmodifiable(sources),
       _config = config ?? const MigrationConfig();

  /// Returns a copy of this migrator with [migrations].
  Migrator withMigrations(List<MigrationUnit> migrations) {
    return Migrator(
      _knex,
      migrations: migrations,
      sources: _sources,
      config: _config,
    );
  }

  /// Returns a copy of this migrator with [sources].
  Migrator withSources(List<MigrationSource> sources) {
    return Migrator(
      _knex,
      migrations: _migrations,
      sources: sources,
      config: _config,
    );
  }

  /// Explicit code-first entrypoint.
  ///
  /// Replaces currently configured migration units with [migrations].
  Migrator fromCode(List<MigrationUnit> migrations) {
    return withMigrations(migrations);
  }

  /// Explicit SQL-directory entrypoint.
  ///
  /// Adds one filesystem source that loads `*.up.sql` / `*.down.sql` files.
  Migrator fromSqlDir(String directoryPath) {
    return withSources([
      ..._sources,
      SqlDirectoryMigrationSource(directoryPath),
    ]);
  }

  /// Use the migration directory from [MigrationConfig] as the SQL source.
  ///
  /// Equivalent to `fromSqlDir(config.directory)`. Mirrors the knex.js default
  /// where `knex.migrate.latest()` reads from the configured directory
  /// (default `./migrations`).
  Migrator fromConfig() => fromSqlDir(_config.directory);

  /// Explicit schema-input entrypoint.
  ///
  /// Converts [input] through a schema adapter and appends one
  /// [SchemaAstMigration] unit.
  ///
  /// When neither [adapter] nor [registry] is provided, [JsonSchemaAdapter]
  /// is registered automatically so that JSON Schema maps work out of the box:
  /// ```dart
  /// knex.migrate.fromSchema(name: '001_users', input: myJsonSchema).latest();
  /// ```
  Migrator fromSchema({
    required String name,
    required dynamic input,
    SchemaAdapterRegistry? registry,
    ExternalSchemaAdapter? adapter,
    bool ifNotExists = false,
    bool dropOnDown = false,
  }) {
    final resolvedRegistry = registry ?? SchemaAdapterRegistry();
    if (adapter != null) {
      resolvedRegistry.registerExternal(adapter);
    } else if (registry == null) {
      // No explicit adapter or registry supplied — register the built-in JSON
      // Schema adapter so callers don't have to import it manually.
      resolvedRegistry.registerExternal(JsonSchemaAdapter());
    }
    final ast = resolvedRegistry.parse(input);
    final unit = SchemaAstMigration(
      name: name,
      schema: ast,
      ifNotExists: ifNotExists,
      dropOnDown: dropOnDown,
    );
    return withMigrations([..._migrations, unit]);
  }

  /// Run all pending migrations in one new batch.
  Future<void> latest() async {
    final migrations = await _resolveMigrations();
    await _ensureTable();
    final applied = await _appliedRows();
    final appliedNames = applied.map((r) => r.name).toSet();
    final pending = migrations.where((m) => !appliedNames.contains(m.name));
    if (pending.isEmpty) return;

    final batch = _currentBatch(applied) + 1;
    for (final migration in pending) {
      await _runWithOptionalTx(
        () async {
          await migration.up(_knex);
          await _insertApplied(migration.name, batch);
        },
        migration.name,
        direction: 'up',
      );
    }
  }

  /// Roll back migrations from the latest batch only.
  Future<void> rollback() async {
    final migrations = await _resolveMigrations();
    await _ensureTable();
    final applied = await _appliedRows();
    if (applied.isEmpty) return;

    final latestBatch = _currentBatch(applied);
    final inLatestBatch = applied
        .where((r) => r.batch == latestBatch)
        .toList()
        .reversed
        .toList();

    for (final row in inLatestBatch) {
      final migration = migrations.where((m) => m.name == row.name);
      if (migration.isEmpty) {
        throw KnexMigrationException(
          'Cannot rollback "${row.name}": migration definition not registered',
        );
      }
      final m = migration.first;
      await _runWithOptionalTx(
        () async {
          await m.down(_knex);
          await _deleteApplied(m.name);
        },
        m.name,
        direction: 'down',
      );
    }
  }

  /// Returns one status row per registered migration.
  Future<List<Map<String, dynamic>>> status() async {
    final migrations = await _resolveMigrations();
    await _ensureTable();
    final appliedNames = (await _appliedRows()).map((r) => r.name).toSet();
    return migrations
        .map(
          (m) => {
            'name': m.name,
            'status': appliedNames.contains(m.name) ? 'completed' : 'pending',
          },
        )
        .toList(growable: false);
  }

  Future<List<MigrationUnit>> _resolveMigrations() async {
    final all = <MigrationUnit>[..._migrations];
    for (final source in _sources) {
      all.addAll(await source.load(_knex));
    }
    final byName = <String, MigrationUnit>{};
    for (final migration in all) {
      if (byName.containsKey(migration.name)) {
        throw KnexMigrationException(
          'Duplicate migration name "${migration.name}" from configured migrations/sources',
        );
      }
      byName[migration.name] = migration;
    }
    return byName.values.toList(growable: false);
  }

  Future<void> _ensureTable() async {
    final table = _tableRef();
    await _knex.client.rawQuery(
      'CREATE TABLE IF NOT EXISTS $table ('
      'name VARCHAR(255) PRIMARY KEY, '
      'batch INTEGER NOT NULL, '
      'migrated_at BIGINT NOT NULL'
      ')',
      const [],
    );
  }

  Future<List<_AppliedMigration>> _appliedRows() async {
    final table = _tableRef();
    final raw = await _knex.client.rawQuery(
      'SELECT name, batch FROM $table ORDER BY batch ASC, migrated_at ASC, name ASC',
      const [],
    );
    return _rowsFromRaw(raw)
        .map(
          (r) => _AppliedMigration(
            name: r['name']?.toString() ?? '',
            batch: _toInt(r['batch']),
          ),
        )
        .where((r) => r.name.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> _insertApplied(String name, int batch) async {
    final table = _tableRef();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final p = _placeholders(3);
    await _knex.client.rawQuery(
      'INSERT INTO $table (name, batch, migrated_at) VALUES (${p[0]}, ${p[1]}, ${p[2]})',
      [name, batch, ts],
    );
  }

  Future<void> _deleteApplied(String name) async {
    final table = _tableRef();
    final p = _placeholders(1);
    await _knex.client.rawQuery('DELETE FROM $table WHERE name = ${p[0]}', [
      name,
    ]);
  }

  Future<void> _runWithOptionalTx(
    Future<void> Function() action,
    String migrationName, {
    required String direction,
  }) async {
    try {
      if (!_config.disableTransactions) {
        await _knex.client.runInTransaction(action);
      } else {
        await action();
      }
    } catch (e, st) {
      throw KnexMigrationException(
        'Migration "$migrationName" failed during $direction',
        cause: e,
        stackTrace: st,
      );
    }
  }

  String _tableRef() {
    final table = _knex.client.wrapIdentifier(_config.tableName);
    final schema = _config.schemaName;
    if (schema == null || schema.trim().isEmpty) return table;
    return '${_knex.client.wrapIdentifier(schema)}.$table';
  }

  List<String> _placeholders(int count) {
    return List<String>.generate(
      count,
      (i) => _knex.client.parameterPlaceholder(i + 1),
    );
  }

  int _currentBatch(List<_AppliedMigration> rows) {
    if (rows.isEmpty) return 0;
    return rows.map((r) => r.batch).reduce((a, b) => a > b ? a : b);
  }

  List<Map<String, dynamic>> _rowsFromRaw(dynamic raw) {
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((r) => Map<String, dynamic>.from(r))
          .toList();
    }
    return const [];
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}

class _AppliedMigration {
  final String name;
  final int batch;

  const _AppliedMigration({required this.name, required this.batch});
}
