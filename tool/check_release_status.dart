#!/usr/bin/env dart
// Usage: dart run tool/check_release_status.dart [--offline]
//
// For every publishable package in the workspace, reports what's actually
// pending release — grounded in tool/release_state.json (written only by
// CI right after a publish it watched succeed — see
// tool/record_release_state.dart) and commit history, not just a
// pubspec-version-vs-pub.dev-version diff.
//
// That comparison alone is unreliable in both directions:
//   - A package's pubspec version can sit unchanged for many merged PRs that
//     touched lib/, silently accumulating unreleased fixes with nothing
//     flagging it (this happened here: several drivers had real behavior
//     changes land on main with no version bump).
//   - A package can show as "published" on pub.dev with NO corresponding git
//     tag in this repo at all (this happened here too: knex_dart_otel is on
//     pub.dev at 0.1.1 but `git tag -l 'knex_dart_otel-v*'` finds nothing —
//     it was published outside the normal tag-push flow, or the tag was
//     deleted). A version-string diff can't see that; checking real release
//     history can.
//
// release_state.json is trusted ahead of git tags for "what was last
// released", because tags are a convention a human can forget to push even
// after a successful manual `dart pub publish` — the state file is written
// only by the CI job that just watched a publish succeed, so it can't drift
// from reality the way tag history can. Tags are still cross-checked and
// any disagreement between them and the state file is flagged.
//
// This tool asks, per package:
//   1. What does release_state.json say was last published, and from which
//      commit?
//   2. What commits touched this package's directory since that commit?
//   3. Of those, how many touched lib/bin/pubspec.yaml (release-relevant) vs
//      only test/ (informational — usually doesn't need a version bump)?
//   4. Does the current pubspec version already reflect a bump past that?
//   5. Does the latest git tag for this package agree with release_state.json?
//   6. (unless --offline) does pub.dev's actual published version agree with
//      what release_state.json thinks was last published?
//
// Run this any time you're deciding what to release — especially after
// merging multiple PRs that touched different packages, where it's easy to
// lose track of which packages actually need a bump.

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

class PackageInfo {
  final String name;
  final String dir;
  final Version version;
  PackageInfo(this.name, this.dir, this.version);
}

Future<void> main(List<String> args) async {
  final offline = args.contains('--offline');
  final packages = <PackageInfo>[];

  for (final dir in _packageDirs) {
    final pubspecFile = File('$dir/pubspec.yaml');
    if (!pubspecFile.existsSync()) {
      stderr.writeln('WARNING: $dir/pubspec.yaml not found, skipping');
      continue;
    }
    final doc = loadYaml(pubspecFile.readAsStringSync()) as YamlMap;
    if (doc['publish_to'] == 'none') continue;
    packages.add(PackageInfo(
      doc['name'] as String,
      dir,
      Version.parse(doc['version'] as String),
    ));
  }

  final stateFile = File(_stateFile);
  final releaseState = stateFile.existsSync()
      ? jsonDecode(stateFile.readAsStringSync()) as Map<String, dynamic>
      : <String, dynamic>{};
  if (releaseState.isEmpty) {
    stderr.writeln('WARNING: $_stateFile missing or empty — falling back to '
        'git tags alone for every package below (less reliable, see the '
        'file header for why).');
  }

  print('Checking release status for ${packages.length} publishable '
      'packages${offline ? " (offline mode)" : ""}...\n');

  var needsAttention = 0;
  for (final pkg in packages) {
    final entry = releaseState[pkg.name] as Map<String, dynamic>?;
    final flagged = await _checkPackage(pkg, entry, offline: offline);
    if (flagged) needsAttention++;
  }

  print('─' * 78);
  if (needsAttention == 0) {
    print('All packages accounted for — nothing unexpected.');
  } else {
    print('$needsAttention package(s) flagged above — see ⚠️  lines.');
  }
}

Future<List<String>> _run(List<String> gitArgs) async {
  final result = await Process.run('git', gitArgs);
  return (result.stdout as String)
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
}

Future<bool> _checkPackage(
  PackageInfo pkg,
  Map<String, dynamic>? stateEntry, {
  required bool offline,
}) async {
  final stateVersion = stateEntry?['lastPublishedVersion'] != null
      ? Version.parse(stateEntry!['lastPublishedVersion'] as String)
      : null;
  final stateCommit = stateEntry?['lastPublishedCommit'] as String?;

  // Cross-check against git tags regardless — disagreement is a signal.
  final tags = await _run(['tag', '-l', '${pkg.name}-v*']);
  Version? lastTagVersion;
  String? lastTag;
  for (final t in tags) {
    final verStr = t.substring('${pkg.name}-v'.length);
    try {
      final v = Version.parse(verStr);
      if (lastTagVersion == null || v > lastTagVersion) {
        lastTagVersion = v;
        lastTag = t;
      }
    } catch (_) {
      // not a semver-shaped tag suffix; ignore
    }
  }

  // Prefer the state file's commit as the anchor for "what changed since
  // release"; fall back to the tag if the package predates state tracking.
  final anchor = stateCommit ?? lastTag;
  final range = anchor != null ? '$anchor..HEAD' : 'HEAD';
  final allCommits = await _run(['log', '--oneline', range, '--', pkg.dir]);
  final nonTestCommits = await _run([
    'log', '--oneline', range, '--',
    pkg.dir, ':!${pkg.dir}/test', ':!${pkg.dir}/test/**',
  ]);

  Version? pubDevVersion;
  var pubDevLookupFailed = false;
  if (!offline) {
    try {
      final client = HttpClient();
      final req = await client
          .getUrl(Uri.parse('https://pub.dev/api/packages/${pkg.name}'))
          .timeout(const Duration(seconds: 8));
      final resp = await req.close().timeout(const Duration(seconds: 8));
      final body = await resp.transform(utf8.decoder).join();
      client.close();
      if (resp.statusCode == 200) {
        final json = jsonDecode(body) as Map<String, dynamic>;
        final latest = json['latest'] as Map<String, dynamic>?;
        if (latest != null) {
          pubDevVersion = Version.parse(latest['version'] as String);
        }
      }
    } catch (_) {
      pubDevLookupFailed = true;
    }
  }

  final buf = StringBuffer();
  var flagged = false;
  buf.writeln('${pkg.name}  (${pkg.dir})');
  buf.writeln('  pubspec version:      ${pkg.version}');
  buf.writeln('  release_state.json:   '
      '${stateVersion?.toString() ?? "(no entry)"}'
      '${stateCommit != null ? " @ ${stateCommit.substring(0, 7)}" : ""}');
  buf.writeln('  last release tag:     ${lastTag ?? "(none found in this repo)"}');
  buf.writeln('  pub.dev published:    '
      '${offline ? "(skipped, --offline)" : pubDevLookupFailed ? "(lookup failed — network?)" : pubDevVersion?.toString() ?? "(not published)"}');
  buf.writeln('  commits since anchor: ${allCommits.length} total, '
      '${nonTestCommits.length} touching lib/bin/pubspec (non-test)');

  if (stateVersion == null) {
    flagged = true;
    buf.writeln('  ⚠️  NOT IN release_state.json — this package predates '
        'state tracking or was never recorded. Run tool/record_release_state.dart '
        'or add it to the bootstrap once its actual last-published state is known.');
  } else if (lastTag != null && lastTagVersion != stateVersion) {
    flagged = true;
    buf.writeln('  ⚠️  release_state.json ($stateVersion) disagrees with the '
        'latest git tag ($lastTagVersion) — one of them is wrong; '
        'investigate before trusting either.');
  }

  if (!offline &&
      !pubDevLookupFailed &&
      pubDevVersion != null &&
      stateVersion != null &&
      pubDevVersion != stateVersion) {
    flagged = true;
    buf.writeln('  ⚠️  MISMATCH: release_state.json says $stateVersion was '
        'last published, but pub.dev currently has $pubDevVersion. Either a '
        'publish happened outside CI (state file wasn\'t updated), or a '
        'publish is in flight — check before relying on this.');
  }

  final bumpedPastRelease = stateVersion == null || pkg.version > stateVersion;

  if (nonTestCommits.isNotEmpty && !bumpedPastRelease) {
    flagged = true;
    buf.writeln('  ⚠️  NEEDS A VERSION BUMP — ${nonTestCommits.length} '
        'commit(s) touched lib/bin/pubspec.yaml since '
        '${anchor ?? "the beginning of history"} but the version was never '
        'bumped:');
    for (final c in nonTestCommits.take(8)) {
      buf.writeln('        $c');
    }
    if (nonTestCommits.length > 8) {
      buf.writeln('        ... and ${nonTestCommits.length - 8} more');
    }
  } else if (bumpedPastRelease && stateVersion != null) {
    buf.writeln('  ✓ Bumped to ${pkg.version} — ready to tag & release: '
        'git tag ${pkg.name}-v${pkg.version} && git push origin '
        '${pkg.name}-v${pkg.version}');
  } else if (allCommits.length > nonTestCommits.length &&
      nonTestCommits.isEmpty) {
    buf.writeln('  ✓ Only test-only changes since last release — no version '
        'bump needed unless you want one anyway.');
  } else {
    buf.writeln('  ✓ Up to date, nothing pending.');
  }

  print(buf.toString());
  return flagged;
}
