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

  // simolus3/sqlite3.dart tags every sqlite3 package release as
  // "sqlite3-$version" — checked every release back to 2.7.7, no exceptions
  // — so this is the only URL that has ever been correct. No "latest" or
  // alternate-tag-format fallback: either could silently download a
  // sqlite3.wasm that doesn't match the version pub actually resolved
  // (declared in pubspec.yaml), testing a different binary than intended.
  // Fail loudly instead if this doesn't match.
  final url =
      'https://github.com/simolus3/sqlite3.dart/releases/download/'
      'sqlite3-$version/sqlite3.wasm';

  final client = HttpClient();
  try {
    print('Downloading $url ...');
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) {
      await response.drain<void>();
      stderr.writeln(
        'Could not download sqlite3.wasm for version $version: '
        'HTTP ${response.statusCode} from $url.',
      );
      exitCode = 1;
      return;
    }
    final sink = outFile.openWrite();
    await response.pipe(sink);
    print(
      'Saved sqlite3.wasm (${_mb(outFile.lengthSync())}) to ${outFile.path}',
    );
  } finally {
    client.close(force: true);
  }
}

String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
