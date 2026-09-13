/// Integration tests for the connection-level options added on top of
/// PostgresClient.connect()/KnexPostgres.connect()/cockroachdb()/redshift():
/// applicationName, queryTimeout, timeZone.
///
/// Each is verified against a real Postgres connection — not just that the
/// call compiles/succeeds, but that the server actually received and
/// applied the setting (via `current_setting(...)`) or that the option's
/// real runtime behavior changed as expected (queryTimeout).
@Tags(['postgres'])
library;

import 'package:universal_io/io.dart';

import 'package:knex_dart_postgres/knex_dart_postgres.dart';
import 'package:test/test.dart';

void main() {
  final host = Platform.environment['PG_HOST'] ?? 'localhost';
  final port = int.parse(Platform.environment['PG_PORT'] ?? '5432');
  final database = Platform.environment['PG_DATABASE'] ?? 'knex_test';
  final username = Platform.environment['PG_USER'] ?? 'test';
  final password = Platform.environment['PG_PASSWORD'] ?? 'test';

  group('applicationName', () {
    test('PostgresClient.connect: set value is visible via '
        "current_setting('application_name')", () async {
      final client = await PostgresClient.connect(
        host: host,
        port: port,
        database: database,
        username: username,
        password: password,
        applicationName: 'knex_dart_test_app',
      );
      addTearDown(client.close);

      final rows = await client.rawSql(
        "select current_setting('application_name') as name",
      );
      expect(rows.single['name'], 'knex_dart_test_app');
    });

    test('PostgresClient.connect: omitted value leaves the server default '
        '(empty string — the `postgres` package sends no application_name '
        'startup parameter when unset)', () async {
      final client = await PostgresClient.connect(
        host: host,
        port: port,
        database: database,
        username: username,
        password: password,
      );
      addTearDown(client.close);

      final rows = await client.rawSql(
        "select current_setting('application_name') as name",
      );
      expect(rows.single['name'], '');
    });

    test('KnexPostgres.connect: set value reaches the server', () async {
      final db = await KnexPostgres.connect(
        host: host,
        port: port,
        database: database,
        username: username,
        password: password,
        applicationName: 'knex_dart_test_app_wrapper',
      );
      addTearDown(db.close);

      final rows = await db.rawSql(
        "select current_setting('application_name') as name",
      );
      expect(rows.single['name'], 'knex_dart_test_app_wrapper');
    });

    // cockroachdb()/redshift() are thin dialect-labeled wrappers around the
    // exact same PostgresClient.connect() call already verified above —
    // pointed at this same local Postgres server (there's no real
    // CockroachDB/Redshift in this test environment) purely to confirm
    // applicationName threads through those two call sites too, not to
    // exercise anything CockroachDB/Redshift-specific.
    test('KnexPostgres.cockroachdb: set value reaches the server', () async {
      final db = await KnexPostgres.cockroachdb(
        host: host,
        port: port,
        database: database,
        username: username,
        password: password,
        applicationName: 'knex_dart_test_app_cockroachdb',
      );
      addTearDown(db.close);

      final rows = await db.rawSql(
        "select current_setting('application_name') as name",
      );
      expect(rows.single['name'], 'knex_dart_test_app_cockroachdb');
    });

    test('KnexPostgres.redshift: set value reaches the server', () async {
      final db = await KnexPostgres.redshift(
        host: host,
        port: port,
        database: database,
        username: username,
        password: password,
        useSSL: false, // local test server has no TLS configured
        applicationName: 'knex_dart_test_app_redshift',
      );
      addTearDown(db.close);

      final rows = await db.rawSql(
        "select current_setting('application_name') as name",
      );
      expect(rows.single['name'], 'knex_dart_test_app_redshift');
    });
  });

  group('timeZone', () {
    test("set value is visible via current_setting('TimeZone')", () async {
      final client = await PostgresClient.connect(
        host: host,
        port: port,
        database: database,
        username: username,
        password: password,
        timeZone: 'America/New_York',
      );
      addTearDown(client.close);

      final rows = await client.rawSql(
        "select current_setting('TimeZone') as tz",
      );
      expect(rows.single['tz'], 'America/New_York');
    });
  });

  group('queryTimeout', () {
    test('a query exceeding queryTimeout is aborted rather than hanging',
        () async {
      final client = await PostgresClient.connect(
        host: host,
        port: port,
        database: database,
        username: username,
        password: password,
        queryTimeout: const Duration(milliseconds: 500),
      );
      addTearDown(client.close);

      // The postgres package enforces queryTimeout by issuing a server-side
      // cancel request, which Postgres reports as error 57014 ("canceling
      // statement due to user request") — not a client-side timeout error.
      await expectLater(
        client.rawSql('select pg_sleep(2)'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('57014'),
          ),
        ),
      );
    });

    test('a query well within queryTimeout completes normally', () async {
      final client = await PostgresClient.connect(
        host: host,
        port: port,
        database: database,
        username: username,
        password: password,
        queryTimeout: const Duration(seconds: 5),
      );
      addTearDown(client.close);

      final rows = await client.rawSql('select 1 as one');
      expect(rows.single['one'], 1);
    });
  });
}
