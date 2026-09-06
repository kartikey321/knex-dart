/// Downloads the sqlite3 WASM binary to lib/web_assets/ for local browser
/// testing (mirrors drivers/knex_dart_duckdb/tool/download_wasm.dart).
///
/// Run once before running Chrome tests:
///   dart run tool/download_wasm.dart
///
/// The file is gitignored — it needs to be downloaded on each machine/CI
/// runner. The version is inferred from the resolved `sqlite3` package (via
/// .dart_tool/package_config.json) so this always matches whatever version
/// pub actually resolved, rather than a hardcoded constant that can drift out
/// of sync with pubspec.yaml's `sqlite3: ^3.0.0` constraint.
library;

import 'dart:convert';
import 'dart:io';

Future<String> _resolveSqlite3Version() async {
  // This package resolves via the melos/pub workspace (`resolution:
  // workspace` in pubspec.yaml), so .dart_tool/package_config.json usually
  // lives at the workspace root rather than in this package's own directory
  // — check both, preferring the local one if present.
  var packageConfig = File('.dart_tool/package_config.json');
  if (!packageConfig.existsSync()) {
    packageConfig = File('../../.dart_tool/package_config.json');
  }
  if (!packageConfig.existsSync()) {
    throw StateError(
      'package_config.json not found (checked .dart_tool/ and '
      '../../.dart_tool/) — run `dart pub get` first.',
    );
  }
  final json =
      jsonDecode(await packageConfig.readAsString()) as Map<String, dynamic>;
  final packages = json['packages'] as List<dynamic>;
  final sqlite3Package = packages.cast<Map<String, dynamic>>().firstWhere(
    (p) => p['name'] == 'sqlite3',
    orElse: () => throw StateError(
      'sqlite3 package not found in package_config.json.',
    ),
  );
  var rootUri = sqlite3Package['rootUri'] as String;
  rootUri = rootUri.replaceFirst(RegExp(r'^file://'), '');
  final dirName = rootUri.split('/').where((s) => s.isNotEmpty).last;
  final match = RegExp(r'^sqlite3-(.+)$').firstMatch(dirName);
  if (match == null) {
    throw StateError('Could not infer sqlite3 version from "$rootUri".');
  }
  return match.group(1)!;
}

Future<void> main() async {
  final version = await _resolveSqlite3Version();
  print('Resolved sqlite3 version: $version');

  final outDir = Directory('lib/web_assets');
  if (!outDir.existsSync()) outDir.createSync(recursive: true);
  final outFile = File('${outDir.path}/sqlite3.wasm');

  final candidateUrls = [
    'https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-$version/sqlite3.wasm',
    'https://github.com/simolus3/sqlite3.dart/releases/download/v$version/sqlite3.wasm',
    'https://github.com/simolus3/sqlite3.dart/releases/download/$version/sqlite3.wasm',
    'https://github.com/simolus3/sqlite3.dart/releases/latest/download/sqlite3.wasm',
  ];

  final client = HttpClient();
  try {
    for (final url in candidateUrls) {
      print('Trying $url ...');
      try {
        final request = await client.getUrl(Uri.parse(url));
        final response = await request.close();
        if (response.statusCode != 200) {
          print('  -> HTTP ${response.statusCode}, trying next candidate.');
          await response.drain<void>();
          continue;
        }
        final sink = outFile.openWrite();
        await response.pipe(sink);
        print('Saved sqlite3.wasm (${_mb(outFile.lengthSync())}) to '
            '${outFile.path}');
        return;
      } on Object catch (e) {
        print('  -> failed: $e');
      }
    }
    stderr.writeln(
      'Could not download sqlite3.wasm from any candidate URL for version '
      '$version.',
    );
    exitCode = 1;
  } finally {
    client.close(force: true);
  }
}

String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
