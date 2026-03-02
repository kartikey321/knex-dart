import 'dart:io';

import '../knex.dart';
import '../util/knex_exception.dart';
import 'migration.dart';

/// Source abstraction for loading migration units.
///
/// Examples:
/// - in-memory code registrations
/// - filesystem SQL directories
/// - external schema adapters projected into migration units
abstract class MigrationSource {
  Future<List<MigrationUnit>> load(Knex knex);
}

/// Simple source backed by an in-memory list of migration units.
class CodeMigrationSource implements MigrationSource {
  final List<MigrationUnit> migrations;

  const CodeMigrationSource(this.migrations);

  @override
  Future<List<MigrationUnit>> load(Knex knex) async {
    return List<MigrationUnit>.unmodifiable(migrations);
  }
}

/// Filesystem-backed SQL migration source.
///
/// Naming convention:
/// - `name.up.sql` (required) -> migration up step
/// - `name.down.sql` (optional) -> migration down step
///
/// The migration id is `name`, and units are loaded in lexicographic id order.
class SqlDirectoryMigrationSource implements MigrationSource {
  final String directoryPath;

  const SqlDirectoryMigrationSource(this.directoryPath);

  @override
  Future<List<MigrationUnit>> load(Knex knex) async {
    final directory = Directory(directoryPath);
    if (!await directory.exists()) {
      throw KnexMigrationException(
        'Migration directory does not exist: $directoryPath',
      );
    }

    final files = await directory.list(followLinks: false).toList();
    final upByName = <String, File>{};
    final downByName = <String, File>{};

    for (final entity in files) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.isEmpty
          ? ''
          : entity.uri.pathSegments.last;
      if (name.endsWith('.up.sql')) {
        upByName[name.substring(0, name.length - '.up.sql'.length)] = entity;
      } else if (name.endsWith('.down.sql')) {
        downByName[name.substring(0, name.length - '.down.sql'.length)] =
            entity;
      }
    }

    final names = upByName.keys.toList()..sort();
    final units = <MigrationUnit>[];
    for (final name in names) {
      final upSql = await _readFile(upByName[name]!);
      final downFile = downByName[name];
      final downSql = downFile == null ? null : await _readFile(downFile);
      units.add(
        SqlMigration(
          name: name,
          upSql: [upSql],
          downSql: downSql == null ? const [] : [downSql],
        ),
      );
    }
    return units;
  }

  Future<String> _readFile(File file) async {
    try {
      return await file.readAsString();
    } catch (e, st) {
      throw KnexMigrationException(
        'Failed reading migration file: ${file.path}',
        cause: e,
        stackTrace: st,
      );
    }
  }
}
