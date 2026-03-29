/// Downloads DuckDB WASM assets to lib/web_assets/ for local browser testing.
///
/// Run once before running Chrome tests:
///   dart run tool/download_wasm.dart
///
/// Files are gitignored — they need to be downloaded on each machine/CI runner.
library;

import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> consolidate(HttpClientResponse res) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in res) {
    builder.add(chunk);
  }
  return builder.toBytes();
}

const _version = '1.29.1-dev222.0';
const _base = 'https://cdn.jsdelivr.net/npm/@duckdb/duckdb-wasm@$_version/dist';

// Only the large binary assets are vendored locally.
// The duckdb-wasm and apache-arrow JS modules (~250 KB combined) are small
// enough to load from CDN via <script type="module"> at test time.
const _assets = {
  'duckdb-eh.wasm': '$_base/duckdb-eh.wasm',
  'duckdb-browser-eh.worker.js': '$_base/duckdb-browser-eh.worker.js',
};

Future<void> main() async {
  final outDir = Directory('lib/web_assets');
  if (!outDir.existsSync()) outDir.createSync(recursive: true);

  final client = HttpClient();
  try {
    for (final entry in _assets.entries) {
      final file = File('${outDir.path}/${entry.key}');
      final url = entry.value;

      // Check Content-Length to skip if already downloaded correctly.
      final headReq = await client.headUrl(Uri.parse(url));
      final headRes = await headReq.close();
      final contentLength =
          int.tryParse(headRes.headers.value('content-length') ?? '') ?? -1;

      if (file.existsSync() &&
          contentLength > 0 &&
          file.lengthSync() == contentLength) {
        print('✓ ${entry.key} already up-to-date (${_mb(contentLength)})');
        continue;
      }

      print('↓ ${entry.key} (${_mb(contentLength)}) ...');

      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();

      if (res.statusCode != 200) {
        stderr.writeln('FAILED (HTTP ${res.statusCode})');
        exitCode = 1;
        continue;
      }

      final bytes = await consolidate(res);
      file.writeAsBytesSync(bytes);
      print('✓ ${entry.key} (${_mb(bytes.length)})');
    }
  } finally {
    client.close();
  }

  print('\nDone. Run: dart test --platform=chrome test/duckdb_test.dart');
}

String _mb(int bytes) =>
    bytes < 0 ? '?' : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
