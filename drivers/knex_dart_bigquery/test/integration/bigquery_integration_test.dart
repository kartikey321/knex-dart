/// Integration tests for knex_dart_bigquery against the BigQuery emulator.
///
/// Requires the emulator running locally:
///   docker compose up bigquery -d
///
/// Or set BIGQUERY_EMULATOR_HOST to point at a running emulator.
@Tags(['bigquery'])
library;

import 'package:universal_io/io.dart';

import 'package:knex_dart_bigquery/knex_dart_bigquery.dart';
import 'package:test/test.dart';

// ─── Connection config ────────────────────────────────────────────────────────

String get _emulatorHost =>
    Platform.environment['BIGQUERY_EMULATOR_HOST'] ?? 'http://localhost:9050';
String get _project =>
    Platform.environment['BIGQUERY_PROJECT'] ?? 'knex-test';
String get _dataset =>
    Platform.environment['BIGQUERY_DATASET'] ?? 'knex_dataset';

// ─── Helpers ─────────────────────────────────────────────────────────────────

Future<BigQueryClient?> _tryOpen() async {
  try {
    final client = BigQueryClient(
      projectId: _project,
      token: 'emulator', // emulator ignores auth
      emulatorHost: _emulatorHost,
    );
    await client.raw('SELECT 1');
    return client;
  } catch (e) {
    return null;
  }
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  BigQueryClient? client;
  String? skipReason;

  setUpAll(() async {
    final candidate = await _tryOpen();
    if (candidate == null) {
      skipReason =
          'BigQuery emulator not reachable at $_emulatorHost — '
          'start via `docker compose up bigquery -d`';
      return;
    }

    // Create dataset and table in emulator
    try {
      await candidate.raw(
        'CREATE SCHEMA IF NOT EXISTS `$_project.$_dataset`',
      );
      await candidate.raw('''
        CREATE TABLE IF NOT EXISTS `$_project.$_dataset.users` (
          id INT64,
          name STRING,
          score FLOAT64
        )
      ''');
    } catch (_) {}
    client = candidate;
  });

  tearDownAll(() async {
    client?.close();
    client = null;
  });

  setUp(() async {
    if (skipReason != null || client == null) return;
    // Clean table before each test
    try {
      await client!.raw(
        'DELETE FROM `$_project.$_dataset.users` WHERE TRUE',
      );
    } catch (_) {}
  });

  group('BigQuery (emulator) — basic queries', () {
    test('INSERT and SELECT round-trip', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await client!.raw(
        'INSERT INTO `$_project.$_dataset.users` (id, name, score) VALUES (?, ?, ?)',
        [1, 'Alice', 9.5],
      );

      final rows = await client!.raw(
        'SELECT * FROM `$_project.$_dataset.users` WHERE id = ?',
        [1],
      );
      expect(rows, hasLength(1));
      expect(rows.first['name'], 'Alice');
    });

    test('aggregate — AVG score', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await client!.raw(
        'INSERT INTO `$_project.$_dataset.users` (id, name, score) '
        'VALUES (1,?,?),(2,?,?)',
        ['Alice', 80.0, 'Bob', 60.0],
      );

      final rows = await client!.raw(
        'SELECT AVG(score) as avg_score FROM `$_project.$_dataset.users`',
      );
      expect((rows.first['avg_score'] as num), closeTo(70.0, 0.01));
    });

    test('returns empty list for zero rows', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      final rows = await client!.raw(
        'SELECT * FROM `$_project.$_dataset.users` WHERE id = ?',
        [9999],
      );
      expect(rows, isEmpty);
    });
  });
}
