#!/usr/bin/env dart
// Usage: dart run tool/check_doc_snippets.dart
//
// Validates all ```dart code blocks in docs and READMEs:
//   Layer 0 — README version drift check (pubspec.yaml is the source of truth)
//   Layer 1 — forbidden-pattern scan (all snippets)
//   Layer 2 — dart analyze on snippets that carry import statements

import 'dart:io';

// ── Config ────────────────────────────────────────────────────────────────────

final _docGlobs = [
  'docs/site/content',
  'packages/knex_dart',
  ...['knex_dart_postgres', 'knex_dart_mysql', 'knex_dart_sqlite',
      'knex_dart_duckdb', 'knex_dart_mssql', 'knex_dart_turso',
      'knex_dart_d1', 'knex_dart_bigquery', 'knex_dart_snowflake']
      .map((d) => 'drivers/$d'),
  'integrations/knex_dart_otel',
];

// Patterns that indicate a broken/stale API call.
// Each entry: (regex pattern, human-readable message)
final _forbidden = [
  (
    RegExp(r'\bdb\.raw\s*\('),
    'db.raw() does not exist on KnexQuery — '
        'use db.queryBuilder().client.raw() or a live driver method',
  ),
  (
    RegExp(r'\btrx\.raw\s*\('),
    'trx.raw() does not exist on transaction arg — '
        'use trx.queryBuilder().client.raw()',
  ),
  (
    RegExp(r'KnexQuery\.forDialect\([^)]+\)\s*\.(select|insert|update|delete|rawQuery|rawSql)\s*\('),
    'KnexQuery.forDialect() returns a builder factory, not a live driver — '
        'cannot call select/insert/update/delete/rawQuery/rawSql on it directly',
  ),
];

// Workspace-local path deps for the temp analysis package.
// knex_dart_duckdb is excluded: dart_duckdb is a Flutter plugin, so pure
// `dart analyze` cannot resolve it. Snippets importing it are skipped.
final _pathDeps = {
  'knex_dart': 'packages/knex_dart',
  'knex_dart_capabilities': 'packages/knex_dart_capabilities',
  'knex_dart_lint': 'packages/knex_dart_lint',
  'knex_dart_postgres': 'drivers/knex_dart_postgres',
  'knex_dart_mysql': 'drivers/knex_dart_mysql',
  'knex_dart_sqlite': 'drivers/knex_dart_sqlite',
  'knex_dart_mssql': 'drivers/knex_dart_mssql',
  'knex_dart_turso': 'drivers/knex_dart_turso',
  'knex_dart_d1': 'drivers/knex_dart_d1',
  'knex_dart_bigquery': 'drivers/knex_dart_bigquery',
  'knex_dart_snowflake': 'drivers/knex_dart_snowflake',
  'knex_dart_otel': 'integrations/knex_dart_otel',
};

// Packages requiring Flutter SDK — snippets importing these are skipped in
// Layer 2 (dart analyze cannot resolve Flutter-only deps).
const _flutterOnlyPackages = {'knex_dart_duckdb'};

// README files that show installation version constraints.
const _readmeFiles = ['README.md', 'packages/knex_dart/README.md'];

// Workspace packages whose versions must be reflected in READMEs.
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

// ── Layer 0: README version drift check ──────────────────────────────────────

String? _pubspecField(String dir, String field, String rootDir) {
  final f = File('$rootDir/$dir/pubspec.yaml');
  if (!f.existsSync()) return null;
  for (final line in f.readAsLinesSync()) {
    final m = RegExp('^$field:\\s*(\\S+)').firstMatch(line);
    if (m != null) return m.group(1);
  }
  return null;
}

List<String> _versionDriftCheck(String rootDir) {
  // Build name → version from all workspace pubspec.yaml files.
  final versions = <String, String>{};
  for (final dir in _packageDirs) {
    final name = _pubspecField(dir, 'name', rootDir);
    final ver = _pubspecField(dir, 'version', rootDir);
    if (name != null && ver != null) versions[name] = ver;
  }

  final errors = <String>[];
  // Pattern: optional leading spaces + optional # + spaces +
  //          package_name + : ^ + version
  final lineRe = RegExp(
    r'^\s*#?\s*(knex_dart\w*)\s*:\s*\^(\d+\.\d+\.\d+)',
  );

  for (final path in _readmeFiles) {
    final file = File('$rootDir/$path');
    if (!file.existsSync()) continue;
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final m = lineRe.firstMatch(lines[i]);
      if (m == null) continue;
      final pkg = m.group(1)!;
      final readmeVer = m.group(2)!;
      final pubspecVer = versions[pkg];
      if (pubspecVer == null) continue; // unknown package, skip
      if (readmeVer != pubspecVer) {
        errors.add(
          '$path:${i + 1}: $pkg version mismatch — '
          'README shows ^$readmeVer but pubspec.yaml is $pubspecVer. '
          'Run: dart run tool/update_readme_versions.dart',
        );
      }
    }
  }
  return errors;
}

// ── Snippet extraction ────────────────────────────────────────────────────────

class Snippet {
  final String file;
  final int startLine; // 1-based line of the opening ```dart in the .md file
  final String code;
  Snippet(this.file, this.startLine, this.code);
}

List<Snippet> _extractSnippets(String rootDir) {
  final results = <Snippet>[];

  void scanFile(String path) {
    final lines = File(path).readAsLinesSync();
    var inBlock = false;
    var blockStart = 0;
    final blockLines = <String>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!inBlock && line.trimLeft().startsWith('```dart')) {
        inBlock = true;
        blockStart = i + 1; // 1-based
        blockLines.clear();
      } else if (inBlock && line.trim() == '```') {
        inBlock = false;
        results.add(Snippet(path, blockStart, blockLines.join('\n')));
      } else if (inBlock) {
        blockLines.add(line);
      }
    }
  }

  for (final glob in _docGlobs) {
    final dir = Directory('$rootDir/$glob');
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.md')) {
        scanFile(entity.path);
      }
    }
    // Also scan root README.md of the directory itself
    final readme = File('$rootDir/$glob/README.md');
    if (!dir.existsSync() && readme.existsSync()) scanFile(readme.path);
  }

  // Repo root README
  final rootReadme = File('$rootDir/README.md');
  if (rootReadme.existsSync()) scanFile(rootReadme.path);

  return results;
}

// ── Layer 1: forbidden-pattern scan ──────────────────────────────────────────

List<String> _patternCheck(List<Snippet> snippets) {
  final errors = <String>[];
  for (final s in snippets) {
    final codeLines = s.code.split('\n');
    for (var i = 0; i < codeLines.length; i++) {
      final line = codeLines[i];
      for (final (pattern, message) in _forbidden) {
        if (pattern.hasMatch(line)) {
          errors.add('${s.file}:${s.startLine + i}: $message');
        }
      }
    }
  }
  return errors;
}

// ── Layer 2: dart analyze on snippets with imports ───────────────────────────

String _buildWrapper(String code) {
  final codeLines = code.split('\n');
  final imports = <String>[];
  final topLevel = <String>[];
  final body = <String>[];

  // Simple classifier: import lines → imports; function/class defs → topLevel;
  // everything else → body (goes inside main()).
  var inTopLevelBlock = false;
  var braceDepth = 0;

  for (final line in codeLines) {
    final trimmed = line.trim();

    if (trimmed.startsWith('import ') || trimmed.startsWith('export ')) {
      imports.add(line);
      continue;
    }

    // Detect top-level declarations: void/Future/Stream functions, classes,
    // typedefs, enums, extensions — keep them outside main().
    final isTopLevelDecl = RegExp(
      r'^(void |Future|Stream|class |typedef |enum |extension |abstract )',
    ).hasMatch(trimmed);

    if (isTopLevelDecl && !inTopLevelBlock) {
      inTopLevelBlock = true;
      braceDepth = 0;
    }

    if (inTopLevelBlock) {
      topLevel.add(line);
      braceDepth += '{'.allMatches(line).length;
      braceDepth -= '}'.allMatches(line).length;
      if (braceDepth <= 0 && trimmed.endsWith('}')) {
        inTopLevelBlock = false;
      }
    } else {
      body.add(line);
    }
  }

  final buf = StringBuffer();
  buf.writeln(
    '// ignore_for_file: unused_local_variable, unused_import, dead_code,',
  );
  buf.writeln(
    '// ignore_for_file: unawaited_futures, avoid_print, unused_element',
  );
  for (final imp in imports) {
    buf.writeln(imp);
  }
  buf.writeln();
  for (final tl in topLevel) {
    buf.writeln(tl);
  }
  if (body.isNotEmpty) {
    buf.writeln('Future<void> main() async {');
    for (final b in body) {
      buf.writeln('  $b');
    }
    buf.writeln('}');
  } else {
    buf.writeln('Future<void> main() async {}');
  }

  return buf.toString();
}

String _buildTempPubspec(String rootDir) {
  final buf = StringBuffer()
    ..writeln('name: doc_snippet_check')
    ..writeln('publish_to: none')
    ..writeln('environment:')
    ..writeln('  sdk: ^3.0.0')
    ..writeln('dependencies:')
    ..writeln('  dartastic_opentelemetry_api: ^0.9.0');

  for (final entry in _pathDeps.entries) {
    buf.writeln('  ${entry.key}:');
    buf.writeln('    path: $rootDir/${entry.value}');
  }

  // Override all knex packages to local paths so transitive deps resolve
  // to the workspace versions rather than conflicting hosted versions.
  buf.writeln('dependency_overrides:');
  for (final entry in _pathDeps.entries) {
    buf.writeln('  ${entry.key}:');
    buf.writeln('    path: $rootDir/${entry.value}');
  }

  return buf.toString();
}

Future<List<String>> _analyzeSnippets(
  List<Snippet> snippets,
  String rootDir,
) async {
  final withImports = snippets.where((s) {
    if (!s.code.contains('import ')) return false;
    // Skip snippets marked as intentionally incomplete or using Flutter deps.
    if (s.code.contains('// doc:nocheck')) return false;
    for (final pkg in _flutterOnlyPackages) {
      if (s.code.contains("'package:$pkg/")) return false;
    }
    return true;
  }).toList();

  if (withImports.isEmpty) return [];

  // Build temp package
  final tmpDir = Directory.systemTemp.createTempSync('knex_dart_doc_check_');
  final libDir = Directory('${tmpDir.path}/lib')..createSync();

  File('${tmpDir.path}/pubspec.yaml')
      .writeAsStringSync(_buildTempPubspec(rootDir));

  // analysis_options: suppress wrapping-artifact errors, keep real API errors.
  // duplicate_definition: some doc snippets show two alternatives in one block.
  // missing_required_argument: truncated snippets (intentionally cut off).
  // expected_token / missing_identifier: same — incomplete snippet fragments.
  // undefined_function / undefined_identifier: user-supplied callback stubs
  //   in examples (e.g. handleEvent, writeSummary, serviceAccountJson).
  File('${tmpDir.path}/analysis_options.yaml').writeAsStringSync('''
analyzer:
  errors:
    unused_import: ignore
    unused_local_variable: ignore
    dead_code: ignore
    unawaited_futures: ignore
    unnecessary_import: ignore
    duplicate_definition: ignore
    missing_required_argument: ignore
    expected_token: ignore
    missing_identifier: ignore
    undefined_function: ignore
    undefined_identifier: ignore
''');

  // Index: snippet index → Snippet (for error mapping)
  final index = <int, Snippet>{};

  for (var i = 0; i < withImports.length; i++) {
    final s = withImports[i];
    index[i] = s;
    // Embed source location so errors in the raw analyzer output are traceable.
    final wrapped = '// SOURCE: ${s.file}:${s.startLine}\n${_buildWrapper(s.code)}';
    File('${libDir.path}/snippet_${i.toString().padLeft(4, '0')}.dart')
        .writeAsStringSync(wrapped);
  }

  // dart pub get
  final pubGet = await Process.run(
    'dart',
    ['pub', 'get'],
    workingDirectory: tmpDir.path,
  );
  if (pubGet.exitCode != 0) {
    tmpDir.deleteSync(recursive: true);
    return [
      'ERROR: dart pub get failed in temp analysis package:\n${pubGet.stderr}',
    ];
  }

  // dart analyze
  final analyze = await Process.run(
    'dart',
    ['analyze', '--fatal-warnings', 'lib/'],
    workingDirectory: tmpDir.path,
  );

  final errors = <String>[];

  if (analyze.exitCode != 0) {
    // Parse analyzer output and map snippet file names back to original docs
    final output = '${analyze.stdout}\n${analyze.stderr}';
    for (final line in output.split('\n')) {
      // dart analyze output format:
      //   error - path/snippet_0001.dart:12:5 - message - error_code
      final m = RegExp(
        r'^\s*(error|warning)\s+-\s+\S*snippet_(\d+)\.dart:(\d+):\d+\s+-\s+(.+?)\s+-\s+\w+\s*$',
      ).firstMatch(line);
      if (m == null) continue;

      final severity = m.group(1)!;
      final snippetIdx = int.parse(m.group(2)!);
      final dartLine = int.parse(m.group(3)!);
      final message = m.group(4)!;

      final original = index[snippetIdx];
      if (original == null) continue;

      errors.add(
        '${original.file}:${original.startLine} [$severity] $message '
        '(wrapper line $dartLine)',
      );
    }

    // If we got no structured errors but exit was non-zero, surface raw output
    if (errors.isEmpty) {
      errors.add('dart analyze failed:\n${analyze.stdout}\n${analyze.stderr}');
    }
  }

  tmpDir.deleteSync(recursive: true);
  return errors;
}

// ── Main ─────────────────────────────────────────────────────────────────────

Future<void> main(List<String> args) async {
  final rootDir = args.isNotEmpty ? args[0] : Directory.current.path;

  stdout.writeln('Scanning doc snippets in $rootDir…');

  final snippets = _extractSnippets(rootDir);
  stdout.writeln('  Found ${snippets.length} dart snippets');

  // Layer 0: README version drift
  final versionErrors = _versionDriftCheck(rootDir);

  // Layer 1: pattern check
  final patternErrors = _patternCheck(snippets);

  // Layer 2: dart analyze on snippets with imports
  final withImports = snippets.where((s) => s.code.contains('import ')).length;
  stdout.writeln('  Analyzing $withImports snippets with imports…');
  final analyzeErrors = await _analyzeSnippets(snippets, rootDir);

  final allErrors = [...versionErrors, ...patternErrors, ...analyzeErrors];

  if (allErrors.isEmpty) {
    stdout.writeln('✓ All doc snippets OK.');
    exit(0);
  }

  stderr.writeln('\n✗ ${allErrors.length} doc snippet issue(s) found:\n');
  for (final e in allErrors) {
    stderr.writeln('  $e');
  }
  exit(1);
}
