/// Compiles test/browser/opfs_worker.dart to JS so it can be loaded as a
/// real dedicated `Worker` from the browser test suite.
///
/// `dart test` only compiles the *_test.dart entrypoints it runs; it has no
/// notion of a second, worker-only Dart entrypoint that a test spawns at
/// runtime via the `Worker` constructor. So — analogous to
/// drivers/knex_dart_duckdb/tool/download_wasm.dart vendoring the DuckDB WASM
/// binary — this is a one-time prep step whose output
/// (lib/web_assets/opfs_worker.dart.js) is gitignored and rebuilt on each
/// machine/CI runner:
///
///   dart run tool/build_browser_worker.dart
///
/// Run this (and tool/download_wasm.dart) before:
///   dart test test/browser/ --platform=chrome
library;

import 'dart:io';

Future<void> main() async {
  final outDir = Directory('lib/web_assets');
  if (!outDir.existsSync()) outDir.createSync(recursive: true);

  const entrypoint = 'test/browser/opfs_worker.dart';
  const output = 'lib/web_assets/opfs_worker.dart.js';

  print('Compiling $entrypoint -> $output ...');
  final result = await Process.run('dart', [
    'compile',
    'js',
    entrypoint,
    '-o',
    output,
  ]);
  stdout.write(result.stdout);
  stderr.write(result.stderr);

  if (result.exitCode != 0) {
    stderr.writeln('dart compile js failed (exit code ${result.exitCode}).');
    exitCode = result.exitCode;
    return;
  }
  print('Wrote $output');
}
