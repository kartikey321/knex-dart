#!/usr/bin/env dart
// Usage: dart run tool/check_doc_snippets.dart
//
// Validates all ```dart code blocks in docs and READMEs:
//   Layer 0 — README version drift check (pubspec.yaml is the source of truth)
//   Layer 1 — forbidden-pattern scan (all snippets)
//   Layer 2 — dart analyze on snippets that carry import statements

import 'dart:async';
import 'dart:io';

import 'package:knex_dart/src/util/doc_snippet_runtime.dart';

// ── Config ────────────────────────────────────────────────────────────────────

final _docGlobs = [
  'docs/site/content',
  'packages/knex_dart',
  ...[
    'knex_dart_postgres',
    'knex_dart_mysql',
    'knex_dart_sqlite',
    'knex_dart_duckdb',
    'knex_dart_mssql',
    'knex_dart_turso',
    'knex_dart_d1',
    'knex_dart_bigquery',
    'knex_dart_snowflake',
  ].map((d) => 'drivers/$d'),
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
    RegExp(
      r'KnexQuery\.forDialect\([^)]+\)\s*\.(select|insert|update|delete|rawQuery|rawSql)\s*\(',
    ),
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
  final lineRe = RegExp(r'^\s*#?\s*(knex_dart\w*)\s*:\s*\^(\d+\.\d+\.\d+)');

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
  final int startLine; // 1-based line of the first code line inside the fence
  final String code;
  final bool nocheck;
  final DocRunDirective? runDirective;
  Snippet(
    this.file,
    this.startLine,
    this.code, {
    this.nocheck = false,
    this.runDirective,
  });
}

class DocRunDirective {
  final String scope;
  final String? expectStdout;
  final String? expectStdoutContains;
  final String? expectStderrContains;
  final int expectExit;

  /// 1-based line number of the `<!-- doc:run ... -->` comment in the source file.
  final int directiveLineNo;

  const DocRunDirective({
    required this.scope,
    required this.directiveLineNo,
    this.expectStdout,
    this.expectStdoutContains,
    this.expectStderrContains,
    this.expectExit = 0,
  });
}

class _ProcessResultWithTimeout {
  final int exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;

  const _ProcessResultWithTimeout({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.timedOut,
  });
}

const _snippetRunTimeout = Duration(seconds: 45);

Future<_ProcessResultWithTimeout> _runProcessWithTimeout(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  Duration timeout = _snippetRunTimeout,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
  final stdoutFuture = process.stdout.transform(systemEncoding.decoder).join();
  final stderrFuture = process.stderr.transform(systemEncoding.decoder).join();
  var timedOut = false;

  late int exitCode;
  try {
    exitCode = await process.exitCode.timeout(timeout);
  } on TimeoutException {
    timedOut = true;
    process.kill(ProcessSignal.sigkill);
    exitCode = await process.exitCode;
  }

  return _ProcessResultWithTimeout(
    exitCode: exitCode,
    stdout: await stdoutFuture,
    stderr: await stderrFuture,
    timedOut: timedOut,
  );
}

Map<String, String> _parseDirectiveArgs(String text) {
  final args = <String, String>{};
  final matches = RegExp(
    r"""(\w+)=("([^"]*)"|'([^']*)'|(\S+))""",
  ).allMatches(text);
  for (final m in matches) {
    args[m.group(1)!] = m.group(3) ?? m.group(4) ?? m.group(5) ?? '';
  }
  return args;
}

/// Unescape `\n` and `\"` sequences stored inside directive attribute values.
String _unescapeDirectiveValue(String s) =>
    s.replaceAll(r'\"', '"').replaceAll(r'\n', '\n');

/// Escape a string for embedding inside a `"..."` directive attribute value.
String _escapeForDirective(String s) =>
    s.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n');

DocRunDirective? _parseRunDirective(
  String line,
  int lineNo, {
  bool allowBare = false,
}) {
  final trimmed = line.trim();
  if (!trimmed.startsWith('<!--') || !trimmed.endsWith('-->')) return null;
  if (!trimmed.contains('doc:run')) return null;

  final args = _parseDirectiveArgs(trimmed);
  final scope = args['scope'];
  if (scope == null || scope.isEmpty) {
    throw FormatException('doc:run directive is missing required scope=...');
  }

  final expectStdoutRaw = args['expect_stdout'];
  final expectStdout = expectStdoutRaw == null
      ? null
      : _unescapeDirectiveValue(expectStdoutRaw);
  final expectStdoutContains = args['expect_stdout_contains'];
  final expectStderrContains = args['expect_stderr_contains'];
  final expectExitRaw = args['expect_exit'];
  final expectExit = expectExitRaw == null ? 0 : int.parse(expectExitRaw);

  if (!allowBare &&
      expectStdout == null &&
      expectStdoutContains == null &&
      expectStderrContains == null &&
      expectExitRaw == null) {
    throw FormatException(
      'doc:run directive must declare at least one expectation '
      '(or run with --mode=snapshot to auto-generate).',
    );
  }

  return DocRunDirective(
    scope: scope,
    directiveLineNo: lineNo,
    expectStdout: expectStdout,
    expectStdoutContains: expectStdoutContains,
    expectStderrContains: expectStderrContains,
    expectExit: expectExit,
  );
}

List<Snippet> _extractSnippets(
  String rootDir, {
  bool allowBareDirectives = false,
}) {
  final results = <Snippet>[];
  final errors = <String>[];

  void scanFile(String path) {
    final lines = File(path).readAsLinesSync();
    var inBlock = false;
    var blockStart = 0;
    final blockLines = <String>[];
    String? pendingDirectiveLine;
    int? pendingDirectiveLineNo;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();
      if (!inBlock && trimmed.startsWith('<!--') && trimmed.endsWith('-->')) {
        pendingDirectiveLine = line;
        pendingDirectiveLineNo = i + 1;
        continue;
      }
      if (!inBlock && line.trimLeft().startsWith('```dart')) {
        inBlock = true;
        blockStart = i + 2; // 1-based: first code line (fence is i+1)
        blockLines.clear();
      } else if (inBlock && line.trim() == '```') {
        inBlock = false;
        final directiveLine = pendingDirectiveLine;
        final directiveLineNo = pendingDirectiveLineNo;
        final nocheck = directiveLine?.contains('doc:nocheck') ?? false;
        DocRunDirective? runDirective;
        if (directiveLine != null && directiveLine.contains('doc:run')) {
          try {
            runDirective = _parseRunDirective(
              directiveLine,
              directiveLineNo ?? blockStart,
              allowBare: allowBareDirectives,
            );
          } on FormatException catch (e) {
            errors.add('$path:${directiveLineNo ?? blockStart}: ${e.message}');
          }
        }
        results.add(
          Snippet(
            path,
            blockStart,
            blockLines.join('\n'),
            nocheck: nocheck,
            runDirective: runDirective,
          ),
        );
        pendingDirectiveLine = null;
        pendingDirectiveLineNo = null;
      } else if (inBlock) {
        blockLines.add(line);
      } else {
        pendingDirectiveLine = null;
        pendingDirectiveLineNo = null;
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

  if (errors.isNotEmpty) {
    throw FormatException(errors.join('\n'));
  }

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
    if (s.nocheck || s.code.contains('// doc:nocheck')) return false;
    for (final pkg in _flutterOnlyPackages) {
      if (s.code.contains("'package:$pkg/")) return false;
    }
    return true;
  }).toList();

  if (withImports.isEmpty) return [];

  // Build temp package
  final tmpDir = Directory.systemTemp.createTempSync('knex_dart_doc_check_');
  final libDir = Directory('${tmpDir.path}/lib')..createSync();

  File(
    '${tmpDir.path}/pubspec.yaml',
  ).writeAsStringSync(_buildTempPubspec(rootDir));

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
    final wrapped =
        '// SOURCE: ${s.file}:${s.startLine}\n'
        '${buildDocSnippetProgram(s.code, target: DocSnippetTarget.local)}';
    File(
      '${libDir.path}/snippet_${i.toString().padLeft(4, '0')}.dart',
    ).writeAsStringSync(wrapped);
  }

  // dart pub get
  final pubGet = await Process.run('dart', [
    'pub',
    'get',
  ], workingDirectory: tmpDir.path);
  if (pubGet.exitCode != 0) {
    tmpDir.deleteSync(recursive: true);
    return [
      'ERROR: dart pub get failed in temp analysis package:\n${pubGet.stderr}',
    ];
  }

  // dart analyze
  final analyze = await Process.run('dart', [
    'analyze',
    '--fatal-warnings',
    'lib/',
  ], workingDirectory: tmpDir.path);

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

Future<List<String>> _runSnippets(
  List<Snippet> snippets,
  String rootDir, {
  required String scope,
}) async {
  final runnable = snippets.where((s) {
    final directive = s.runDirective;
    if (directive == null) return false;
    return directive.scope == scope;
  }).toList();

  if (runnable.isEmpty) return [];

  final tmpDir = Directory.systemTemp.createTempSync('knex_dart_doc_run_');
  final libDir = Directory('${tmpDir.path}/lib')..createSync();

  File(
    '${tmpDir.path}/pubspec.yaml',
  ).writeAsStringSync(_buildTempPubspec(rootDir));
  File('${tmpDir.path}/analysis_options.yaml').writeAsStringSync('''
analyzer:
  errors:
    unused_import: ignore
    unused_local_variable: ignore
    dead_code: ignore
    unawaited_futures: ignore
    unnecessary_import: ignore
''');

  final fileForSnippet = <Snippet, String>{};
  for (var i = 0; i < runnable.length; i++) {
    final s = runnable[i];
    final fileName = 'snippet_${i.toString().padLeft(4, '0')}.dart';
    fileForSnippet[s] = fileName;
    final wrapped =
        '// SOURCE: ${s.file}:${s.startLine}\n'
        '${buildDocSnippetProgram(s.code, target: DocSnippetTarget.local)}';
    File('${libDir.path}/$fileName').writeAsStringSync(wrapped);
  }

  final pubGet = await Process.run('dart', [
    'pub',
    'get',
  ], workingDirectory: tmpDir.path);
  if (pubGet.exitCode != 0) {
    tmpDir.deleteSync(recursive: true);
    return [
      'ERROR: dart pub get failed in temp runtime package:\n${pubGet.stderr}',
    ];
  }

  final errors = <String>[];
  for (final snippet in runnable) {
    final directive = snippet.runDirective!;
    final fileName = fileForSnippet[snippet]!;
    stdout.writeln(
      '  Running $scope snippet ${snippet.file}:${snippet.startLine}',
    );
    final run = await _runProcessWithTimeout('dart', [
      'run',
      'lib/$fileName',
    ], workingDirectory: tmpDir.path);
    final stdoutText = run.stdout.trimRight();
    final stderrText = run.stderr.trimRight();

    if (run.timedOut) {
      errors.add(
        '${snippet.file}:${snippet.startLine}: snippet timed out after '
        '${_snippetRunTimeout.inSeconds}s.\n'
        'stdout:\n$stdoutText\nstderr:\n$stderrText',
      );
      continue;
    }

    if (run.exitCode != directive.expectExit) {
      errors.add(
        '${snippet.file}:${snippet.startLine}: expected exit code '
        '${directive.expectExit}, got ${run.exitCode}.\n'
        'stdout:\n$stdoutText\nstderr:\n$stderrText',
      );
      continue;
    }

    if (directive.expectStdout != null &&
        stdoutText != directive.expectStdout) {
      errors.add(
        '${snippet.file}:${snippet.startLine}: stdout mismatch.\n'
        'expected:\n${directive.expectStdout}\nactual:\n$stdoutText',
      );
    }

    if (directive.expectStdoutContains != null &&
        !stdoutText.contains(directive.expectStdoutContains!)) {
      errors.add(
        '${snippet.file}:${snippet.startLine}: stdout did not contain '
        '"${directive.expectStdoutContains}".\nactual:\n$stdoutText',
      );
    }

    if (directive.expectStderrContains != null &&
        !stderrText.contains(directive.expectStderrContains!)) {
      errors.add(
        '${snippet.file}:${snippet.startLine}: stderr did not contain '
        '"${directive.expectStderrContains}".\nactual:\n$stderrText',
      );
    }
  }

  tmpDir.deleteSync(recursive: true);
  return errors;
}

/// Runs each snippet for [scope] and rewrites the `<!-- doc:run ... -->`
/// directive in the source markdown file to include `expect_stdout="<output>"`.
///
/// Bare directives (no expectations yet) are allowed — this is how they get
/// their initial expected output recorded. Existing `expect_stdout=` values
/// are overwritten with the fresh run output.
Future<List<String>> _snapshotSnippets(
  List<Snippet> snippets,
  String rootDir, {
  required String scope,
}) async {
  final runnable = snippets.where((s) {
    final directive = s.runDirective;
    if (directive == null) return false;
    return directive.scope == scope;
  }).toList();

  if (runnable.isEmpty) {
    stdout.writeln('  No doc:run snippets found for scope=$scope.');
    return [];
  }

  final tmpDir = Directory.systemTemp.createTempSync('knex_dart_doc_snap_');
  final libDir = Directory('${tmpDir.path}/lib')..createSync();

  File(
    '${tmpDir.path}/pubspec.yaml',
  ).writeAsStringSync(_buildTempPubspec(rootDir));
  File('${tmpDir.path}/analysis_options.yaml').writeAsStringSync('''
analyzer:
  errors:
    unused_import: ignore
    unused_local_variable: ignore
    dead_code: ignore
    unawaited_futures: ignore
    unnecessary_import: ignore
''');

  final fileForSnippet = <Snippet, String>{};
  for (var i = 0; i < runnable.length; i++) {
    final s = runnable[i];
    final fileName = 'snippet_${i.toString().padLeft(4, '0')}.dart';
    fileForSnippet[s] = fileName;
    final wrapped =
        '// SOURCE: ${s.file}:${s.startLine}\n'
        '${buildDocSnippetProgram(s.code, target: DocSnippetTarget.local)}';
    File('${libDir.path}/$fileName').writeAsStringSync(wrapped);
  }

  final pubGet = await Process.run('dart', [
    'pub',
    'get',
  ], workingDirectory: tmpDir.path);
  if (pubGet.exitCode != 0) {
    tmpDir.deleteSync(recursive: true);
    return [
      'ERROR: dart pub get failed in temp snapshot package:\n${pubGet.stderr}',
    ];
  }

  final errors = <String>[];

  // Group snippets by source file so we can do one file-rewrite per file.
  final byFile = <String, List<Snippet>>{};
  for (final s in runnable) {
    byFile.putIfAbsent(s.file, () => []).add(s);
  }
  // Track mutations per file: directiveLineNo → new directive text
  final mutations = <String, Map<int, String>>{};

  for (final snippet in runnable) {
    final directive = snippet.runDirective!;
    final fileName = fileForSnippet[snippet]!;
    stdout.writeln(
      '  Snapshotting $scope snippet ${snippet.file}:${snippet.startLine}',
    );
    final run = await _runProcessWithTimeout('dart', [
      'run',
      'lib/$fileName',
    ], workingDirectory: tmpDir.path);

    if (run.timedOut) {
      errors.add(
        '${snippet.file}:${snippet.startLine}: snippet timed out after '
        '${_snippetRunTimeout.inSeconds}s — cannot snapshot.\n'
        'stdout:\n${run.stdout}\nstderr:\n${run.stderr}',
      );
      continue;
    }

    if (run.exitCode != 0) {
      errors.add(
        '${snippet.file}:${snippet.startLine}: snippet exited with code '
        '${run.exitCode} — cannot snapshot.\nstderr:\n${run.stderr}',
      );
      continue;
    }

    final captured = run.stdout.trimRight();
    final escaped = _escapeForDirective(captured);

    // Read the original directive line
    final fileLines = File(snippet.file).readAsLinesSync();
    final lineIdx = directive.directiveLineNo - 1;
    if (lineIdx < 0 || lineIdx >= fileLines.length) {
      errors.add(
        '${snippet.file}: directive line ${directive.directiveLineNo} out of range',
      );
      continue;
    }
    final originalLine = fileLines[lineIdx];

    String updatedLine;
    if (originalLine.contains('expect_stdout=')) {
      // Replace existing value — handles both quoted forms
      updatedLine = originalLine.replaceFirst(
        RegExp(r"""expect_stdout=("([^"]*)"|'([^']*)'|\S+)"""),
        'expect_stdout="$escaped"',
      );
    } else {
      // Insert before the closing -->
      updatedLine = originalLine.replaceFirst(
        ' -->',
        ' expect_stdout="$escaped" -->',
      );
    }

    mutations.putIfAbsent(
      snippet.file,
      () => <int, String>{},
    )[directive.directiveLineNo] = updatedLine;
  }

  tmpDir.deleteSync(recursive: true);

  // Apply all mutations, one file at a time
  for (final entry in mutations.entries) {
    final path = entry.key;
    final lineReplacements = entry.value; // lineNo → new text
    final content = File(path).readAsStringSync();
    final lines = content.split('\n');
    for (final lineEntry in lineReplacements.entries) {
      final idx = lineEntry.key - 1;
      if (idx >= 0 && idx < lines.length) {
        lines[idx] = lineEntry.value;
      }
    }
    File(path).writeAsStringSync(lines.join('\n'));
    stdout.writeln(
      '  Updated ${lineReplacements.length} directive(s) in $path',
    );
  }

  return errors;
}

// ── Main ─────────────────────────────────────────────────────────────────────

Future<void> main(List<String> args) async {
  String rootDir = Directory.current.path;
  String mode = 'check';
  String? scope;

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg.startsWith('--mode=')) {
      mode = arg.substring('--mode='.length);
    } else if (arg == '--mode' && i + 1 < args.length) {
      mode = args[++i];
    } else if (arg.startsWith('--scope=')) {
      scope = arg.substring('--scope='.length);
    } else if (arg == '--scope' && i + 1 < args.length) {
      scope = args[++i];
    } else if (!arg.startsWith('--')) {
      rootDir = arg;
    }
  }

  stdout.writeln('Scanning doc snippets in $rootDir…');

  // snapshot mode allows bare doc:run directives (no expectations yet).
  final allowBare = mode == 'snapshot';

  late final List<Snippet> snippets;
  try {
    snippets = _extractSnippets(rootDir, allowBareDirectives: allowBare);
  } on FormatException catch (e) {
    stderr.writeln('\n✗ doc snippet directive issue(s) found:\n');
    stderr.writeln(e.message);
    exit(1);
  }
  stdout.writeln('  Found ${snippets.length} dart snippets');

  if (mode == 'run') {
    if (scope == null || scope.isEmpty) {
      stderr.writeln('Missing required --scope for --mode=run');
      exit(1);
    }
    stdout.writeln('  Running doc snippets for scope=$scope…');
    final runErrors = await _runSnippets(snippets, rootDir, scope: scope);
    if (runErrors.isEmpty) {
      stdout.writeln('✓ All runnable doc snippets OK for scope=$scope.');
      exit(0);
    }
    stderr.writeln(
      '\n✗ ${runErrors.length} runnable doc snippet issue(s) found:\n',
    );
    for (final e in runErrors) {
      stderr.writeln('  $e');
    }
    exit(1);
  }

  if (mode == 'snapshot') {
    if (scope == null || scope.isEmpty) {
      stderr.writeln('Missing required --scope for --mode=snapshot');
      exit(1);
    }
    stdout.writeln('  Snapshotting doc snippets for scope=$scope…');
    final snapErrors = await _snapshotSnippets(snippets, rootDir, scope: scope);
    if (snapErrors.isEmpty) {
      stdout.writeln(
        '✓ Snapshot complete for scope=$scope — commit the updated directives.',
      );
      exit(0);
    }
    stderr.writeln('\n✗ ${snapErrors.length} snapshot error(s):\n');
    for (final e in snapErrors) {
      stderr.writeln('  $e');
    }
    exit(1);
  }

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
