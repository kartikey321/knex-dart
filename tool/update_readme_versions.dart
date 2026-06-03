#!/usr/bin/env dart
// Usage: dart run tool/update_readme_versions.dart
//
// Reads every workspace pubspec.yaml and rewrites version constraints in
// README files to match.  Run this after bumping any package version.

import 'dart:io';

// ── Config ────────────────────────────────────────────────────────────────────

const _readmeFiles = [
  'README.md',
  'packages/knex_dart/README.md',
];

const _packageDirs = [
  'packages/knex_dart',
  'packages/knex_dart_capabilities',
  'packages/knex_dart_lint',
  'drivers/knex_dart_postgres',
  'drivers/knex_dart_mysql',
  'drivers/knex_dart_sqlite',
  'drivers/knex_dart_duckdb',
  'drivers/knex_dart_mssql',
  'drivers/knex_dart_turso',
  'drivers/knex_dart_d1',
  'drivers/knex_dart_bigquery',
  'drivers/knex_dart_snowflake',
  'integrations/knex_dart_otel',
];

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Reads `version: X.Y.Z` from a pubspec.yaml.
String? _readVersion(String dir, String rootDir) {
  final f = File('$rootDir/$dir/pubspec.yaml');
  if (!f.existsSync()) return null;
  for (final line in f.readAsLinesSync()) {
    final m = RegExp(r'^version:\s*(\S+)').firstMatch(line);
    if (m != null) return m.group(1)!;
  }
  return null;
}

/// Reads `name: package_name` from a pubspec.yaml.
String? _readName(String dir, String rootDir) {
  final f = File('$rootDir/$dir/pubspec.yaml');
  if (!f.existsSync()) return null;
  for (final line in f.readAsLinesSync()) {
    final m = RegExp(r'^name:\s*(\S+)').firstMatch(line);
    if (m != null) return m.group(1)!;
  }
  return null;
}

/// Rewrites `package_name: ^old` → `package_name: ^new` in a single line,
/// handling both plain and commented-out lines.
///
///   knex_dart_postgres: ^0.2.0   # comment
///   # knex_dart_mysql: ^0.2.0    # comment
String _updateLine(String line, String pkg, String newVersion) {
  // Pattern: optional leading whitespace + optional # + whitespace +
  //          package_name + : + optional space + ^old_version
  final re = RegExp(
    r'^(\s*#?\s*)(' + RegExp.escape(pkg) + r')(\s*:\s*\^)(\d+\.\d+\.\d+)',
  );
  return line.replaceFirstMapped(re, (m) {
    return '${m.group(1)}${m.group(2)}${m.group(3)}$newVersion';
  });
}

// ── Main ─────────────────────────────────────────────────────────────────────

Future<void> main(List<String> args) async {
  final rootDir = args.isNotEmpty ? args[0] : Directory.current.path;

  // 1. Build name → version map from all workspace pubspec.yaml files.
  final versions = <String, String>{};
  for (final dir in _packageDirs) {
    final name = _readName(dir, rootDir);
    final ver = _readVersion(dir, rootDir);
    if (name != null && ver != null) versions[name] = ver;
  }

  stdout.writeln('Package versions read from pubspec.yaml:');
  versions.forEach((k, v) => stdout.writeln('  $k: $v'));
  stdout.writeln();

  // 2. Rewrite each README.
  var totalUpdated = 0;

  for (final path in _readmeFiles) {
    final file = File('$rootDir/$path');
    if (!file.existsSync()) continue;

    final original = file.readAsStringSync();
    var updated = original;

    for (final entry in versions.entries) {
      final before = updated;
      final lines = updated.split('\n');
      final newLines = lines.map((l) => _updateLine(l, entry.key, entry.value)).toList();
      updated = newLines.join('\n');
      if (updated != before) {
        stdout.writeln('  $path: ${entry.key} → ^${entry.value}');
        totalUpdated++;
      }
    }

    if (updated != original) file.writeAsStringSync(updated);
  }

  if (totalUpdated == 0) {
    stdout.writeln('All README versions already up to date.');
  } else {
    stdout.writeln('\n$totalUpdated version constraint(s) updated.');
  }
}
