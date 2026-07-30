#!/usr/bin/env dart
// Usage: dart run tool/record_release_state.dart --package <name|all> [--commit <sha>] [--dry-run]
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
// --package must be the exact package name the triggering tag resolved to
// (steps.resolve.outputs.package in ci.yml), or `all` for the bulk
// knex_dart_all-v* tag. This is NOT inferred from "which local pubspec
// versions are ahead of the recorded state" — a Codex/CodeRabbit review
// caught that a version-delta heuristic alone is unsound in a monorepo with
// independent per-package versioning: package A can have its version bumped
// in an already-merged commit without being tagged/published yet, and if
// package B's tag triggers this job, a delta-only check would falsely mark
// A as published too (wrong commit, wrong timestamp, wrong source). Only
// the CI-resolved package (or every package, for `all`) actually got
// published this run, so that's the only thing eligible for updating,
// even though a version-ahead check still gates whether an eligible
// package's entry needs touching at all.
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

  String? scopePackage;
  final packageIdx = args.indexOf('--package');
  if (packageIdx != -1 && packageIdx + 1 < args.length) {
    scopePackage = args[packageIdx + 1];
  }
  if (scopePackage == null) {
    stderr.writeln('ERROR: --package <name|all> is required — this must be '
        'exactly steps.resolve.outputs.package from the triggering tag. '
        'Refusing to infer "what got published" from version deltas alone: '
        'a package can have an unrelated pending version bump sitting on '
        'main that this run did NOT publish.');
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
    if (scopePackage != 'all' && name != scopePackage) continue;
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
    print('${scopePackage == 'all' ? 'No' : '"$scopePackage"\'s'} version '
        "didn't increase relative to the recorded state — nothing to "
        'record. This is unexpected right after that package\'s publish '
        'step succeeded; double check --package matches what was actually '
        'resolved and published this run.');
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
