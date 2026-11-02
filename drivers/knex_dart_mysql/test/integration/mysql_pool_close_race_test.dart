/// Live-MySQL regression test for a pool race: `close()` landing while a
/// connection is still being created.
///
/// `TarnPool._createAndAcquire()` used to hand out (and never destroy) a
/// connection whose `create()` resolved after `close()` had already
/// returned — `close()` had nothing to wait for because `_free`/`_used`
/// were both empty at that moment. The deterministic reproduction against
/// fake connections lives in `test/pool/pool_concurrency_test.dart`; this
/// test proves the same property end-to-end against a real server, where a
/// leaked connection is observable as an extra server-side thread.
@Tags(['mysql'])
library;

import 'dart:async';

import 'package:knex_dart/knex_dart.dart';
import 'package:knex_dart_mysql/knex_dart_mysql.dart';
import 'package:test/test.dart';
import 'package:universal_io/io.dart';

String get _host => Platform.environment['MYSQL_HOST'] ?? 'localhost';
int get _port => int.parse(Platform.environment['MYSQL_PORT'] ?? '3306');
String get _user => Platform.environment['MYSQL_USER'] ?? 'test';
String get _password => Platform.environment['MYSQL_PASSWORD'] ?? 'test';
String get _database => Platform.environment['MYSQL_DATABASE'] ?? 'knex_test';

Future<MySQLClient> _connect() => MySQLClient.connect(
  host: _host,
  port: _port,
  user: _user,
  password: _password,
  database: _database,
  poolConfig: const PoolConfig(min: 0, max: 2),
);

/// The server's **global** `Threads_connected`.
///
/// Not scoped to this test: it counts every connection to the MySQL server,
/// including the ones belonging to the other five integration files this job
/// runs concurrently against the same server. That is why the assertion below
/// bounds this value from above rather than requiring equality — see the
/// comment there.
Future<int> _threadsConnected(MySQLClient monitor) async {
  final rows = await monitor.raw("SHOW STATUS LIKE 'Threads_connected'");
  return int.parse(rows.single['Value'].toString());
}

void main() {
  group('MySQLClient close() racing an in-flight connection create', () {
    MySQLClient? monitor;
    String? skipReason;

    setUpAll(() async {
      try {
        monitor = await _connect();
        await monitor!.raw('SELECT 1');
      } catch (e) {
        skipReason = 'MySQL not reachable at $_host:$_port: $e';
      }
    });

    tearDownAll(() async {
      await monitor?.close();
    });

    test('a query racing close() fails with StateError and leaks no '
        'server-side connection', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      // The monitor is warm (it just ran SELECT 1), so its own connection is
      // already counted in the baseline.
      final baseline = await _threadsConnected(monitor!);

      final victim = await _connect(); // min: 0 => no connection yet
      // raw() runs synchronously up to `await _pool.acquire()`, which starts
      // an async create() on the empty pool. close() is then called before
      // any network I/O for that create() can complete.
      final query = victim.raw('SELECT 1');
      final queryOutcome = expectLater(query, throwsA(isA<StateError>()));
      final closing = victim.close();

      await queryOutcome;
      await closing;

      // The create() finished after close() returned. It must have been
      // destroyed by the pool. Destruction is asynchronous, so poll briefly
      // for the server to report the thread gone.
      //
      // Bounded from above, not compared for equality. `Threads_connected` is
      // a global server counter and the other integration files in this job
      // run concurrently against the same server, so the count can legitimately
      // *fall* below the baseline when one of them finishes and closes its
      // pool. Requiring equality failed on exactly that — `Expected: <5>,
      // Actual: <1>` — reporting a leak when connections had merely gone away.
      // The leak this test exists to catch can only push the count *up*, so an
      // upper bound is both sufficient and immune to unrelated disconnects.
      var threads = await _threadsConnected(monitor!);
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (threads > baseline && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        threads = await _threadsConnected(monitor!);
      }

      expect(
        threads,
        lessThanOrEqualTo(baseline),
        reason:
            'a connection created while close() was in flight was handed out '
            'instead of destroyed, leaking a server-side thread',
      );
    });
  });
}
