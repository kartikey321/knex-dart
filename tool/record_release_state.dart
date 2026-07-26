#!/usr/bin/env dart
// Usage: dart run tool/record_release_state.dart [--commit <sha>] [--dry-run]
//
// Run this ONLY as a CI step, immediately after `melos publish` succeeds in
// the tag-triggered publish job (see .github/workflows/ci.yml). It updates
// tool/release_state.json — the source of truth for "what was actually last
// published and from which commit" — which check_release_status.dart trusts
// ahead of git tags (tags are a convention a human can forget to push even
// after a successful manual `dart pub publish`; this file is written only by
// CI, right after a publish it just watched succeed, so it can't drift from
// reality the way tag history can — see knex_dart_otel, which is on pub.dev
// with no matching git tag at all).
//
// For every workspace package, compares the current pubspec.yaml version
// against tool/release_state.json's recorded lastPublishedVersion. Any
// package whose local version is now higher is assumed to be one this CI run
// just published (this step only runs after the publish step succeeded), and
// gets its entry updated with the current commit/timestamp. This correctly
// handles both a single-package tag (knex_dart-v1.3.1) and the bulk
// knex_dart_all-v* tag, without needing to parse `melos publish` output.
//
// --commit defaults to $GITHUB_SHA. --dry-run prints what would change
// without writing the file (for local testing).

import 'dart:convert';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

const _packageDirs = [
  'packages/knex_dart',
  'packages/knex_dart_capabilities',
  'packages/knex_dart_lint',
  'drivers/knex_dart_postgres',
  'drivers/knex_dart_mysql',
  'drivers/knex_dart_sqlite',
  'drivers/knex_dart_turso',
  'drivers/knex_dart_d1',
  'drivers/knex_dart_duckdb',
  'drivers/knex_dart_snowflake',
  'drivers/knex_dart_bigquery',
  'drivers/knex_dart_mssql',
  'integrations/knex_dart_otel',
];

const _stateFile = 'tool/release_state.json';

Future<void> main(List<String> args) async {
  final dryRun = args.contains('--dry-run');
  String? commit;
  final commitIdx = args.indexOf('--commit');
  if (commitIdx != -1 && commitIdx + 1 < args.length) {
    commit = args[commitIdx + 1];
  }
  commit ??= Platform.environment['GITHUB_SHA'];
  if (commit == null) {
    stderr.writeln('ERROR: no commit provided (--commit or \$GITHUB_SHA) '
        'and this should never run outside CI — refusing to guess.');
    exit(1);
  }
  final refName = Platform.environment['GITHUB_REF_NAME'] ?? '(unknown ref)';

  final file = File(_stateFile);
  final state = file.existsSync()
      ? jsonDecode(file.readAsStringSync()) as Map<String, dynamic>
      : <String, dynamic>{};

  var updated = 0;
  final now = DateTime.now().toUtc().toIso8601String();

  for (final dir in _packageDirs) {
    final pubspecFile = File('$dir/pubspec.yaml');
    if (!pubspecFile.existsSync()) continue;
    final doc = loadYaml(pubspecFile.readAsStringSync()) as YamlMap;
    final name = doc['name'] as String;
    final localVersion = Version.parse(doc['version'] as String);

    final existing = state[name] as Map<String, dynamic>?;
    final recordedVersion = existing != null &&
            existing['lastPublishedVersion'] != null
        ? Version.parse(existing['lastPublishedVersion'] as String)
        : null;

    final isNewRelease =
        recordedVersion == null || localVersion > recordedVersion;
    if (!isNewRelease) continue;

    print('${dryRun ? "[dry-run] would update" : "Updating"} $name: '
        '${recordedVersion ?? "(none)"} -> $localVersion '
        '(commit ${commit.substring(0, 7)}, tag $refName)');
    updated++;

    if (!dryRun) {
      state[name] = {
        'lastPublishedVersion': localVersion.toString(),
        'lastPublishedCommit': commit,
        'lastPublishedAt': now,
        'source': 'ci:tag:$refName',
      };
    }
  }

  if (updated == 0) {
    print('No package versions increased since the last recorded state — '
        'nothing to record. (This is unexpected right after a publish step; '
        'double check which package(s) this run actually published.)');
    return;
  }

  if (dryRun) {
    print('\n--dry-run: not writing $_stateFile');
    return;
  }

  final encoder = JsonEncoder.withIndent('  ');
  final sortedState = Map.fromEntries(
    state.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
  file.writeAsStringSync('${encoder.convert(sortedState)}\n');
  print('\nWrote $_stateFile ($updated package(s) updated).');
}
