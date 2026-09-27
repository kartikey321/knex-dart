/// Regression tests for the mssql_connection → mssql (pure Dart) driver
/// swap (see https://github.com/kartikey321/knex-dart/pull/29).
@Tags(['mssql'])
library;

import 'package:universal_io/io.dart';
import 'package:knex_dart_mssql/knex_dart_mssql.dart';
import 'package:test/test.dart';

String get _host => Platform.environment['MSSQL_HOST'] ?? 'localhost';
String get _port => Platform.environment['MSSQL_PORT'] ?? '1433';
String get _database => Platform.environment['MSSQL_DATABASE'] ?? 'knex_test';
String get _user => Platform.environment['MSSQL_USER'] ?? 'sa';
String get _password => Platform.environment['MSSQL_PASSWORD'] ?? 'Knex_Test1!';

Future<KnexMssql?> _tryConnect() async {
  try {
    final db = await KnexMssql.connect(
      host: _host,
      port: _port,
      database: _database,
      username: _user,
      password: _password,
    );
    await db.rawSql('SELECT 1');
    return db;
  } catch (e) {
    print('MSSQL connect failed: $e');
    return null;
  }
}

void main() {
  group('MSSQL driver swap regressions', () {
    KnexMssql? db;
    String? skipReason;

    setUpAll(() async {
      final candidate = await _tryConnect();
      if (candidate == null) {
        skipReason =
            'SQL Server not reachable at $_host:$_port — start via `docker compose up mssql -d`';
        return;
      }
      db = candidate;
    });

    tearDownAll(() => db?.close());

    test(
      'a literal ? in raw SQL with no bindings is sent unchanged, not '
      'treated as a placeholder',
      () async {
        if (skipReason != null) return markTestSkipped(skipReason!);

        // Regression: _execute() used to unconditionally rewrite every `?`
        // in the SQL text as a placeholder, even with an empty bindings
        // list — crashing with a RangeError on a query with no real
        // placeholders at all but a literal `?` character.
        final rows = await db!.rawSql("SELECT '?' AS marker");
        expect(rows, hasLength(1));
        expect(rows.single['marker'], '?');
      },
    );

    test(
      'two independent KnexMssql.connect() calls do not share a connection',
      () async {
        if (skipReason != null) return markTestSkipped(skipReason!);

        final dbB = await _tryConnect();
        if (dbB == null) return markTestSkipped(skipReason ?? 'unreachable');

        // Closing A must not affect B — proving the two connections are
        // independent, unlike the old driver's process-wide singleton.
        await db!.close();
        final rows = await dbB.rawSql('SELECT 1 AS one');
        expect(rows.single['one'], 1);
        await dbB.close();

        // Reconnect for subsequent tests / tearDownAll.
        db = await _tryConnect();
      },
    );
  });
}
