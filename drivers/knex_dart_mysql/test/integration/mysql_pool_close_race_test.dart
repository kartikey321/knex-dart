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
///
/// Tagged `serial` as well as `mysql`: the assertion below compares the set of
/// connections belonging to this test's user before and after the race, and a
/// connection opened by one of the other integration files mid-window would
/// look exactly like a leak. CI runs this tag in its own `-j1` step so nothing
/// else is talking to the server while it measures.
@Tags(['mysql', 'serial'])
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

/// The ids of the connections this test's MySQL user currently holds.
///
/// Identities, not a count. A count cannot answer the question this test asks:
/// `Threads_connected` is global, so unrelated connections closing moves it
/// down and unrelated connections opening moves it up, and neither has
/// anything to do with whether *the victim's* connection leaked. Comparing
/// counts therefore fails on innocent behaviour in one direction and, worse,
/// passes while leaking in the other — a baseline of 5 that drops to 3 because
/// three other connections closed hides a leaked fourth.
///
/// A set difference cannot be masked that way: a connection that leaked is an
/// id present afterwards that was not present before, however many unrelated
/// ids disappeared in the meantime.
Future<Set<int>> _connectionIds(MySQLClient monitor) async {
  final rows = await monitor.raw(
    'SELECT ID, USER FROM information_schema.PROCESSLIST',
  );
  return {
    for (final row in rows)
      if (row['USER'].toString() == _user) int.parse(row['ID'].toString()),
  };
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
      // already in this set.
      final before = await _connectionIds(monitor!);

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
      // for the id to disappear.
      var leaked = (await _connectionIds(monitor!)).difference(before);
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (leaked.isNotEmpty && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        leaked = (await _connectionIds(monitor!)).difference(before);
      }

      expect(
        leaked,
        isEmpty,
        reason:
            'a connection created while close() was in flight was handed out '
            'instead of destroyed, leaving a server-side thread behind',
      );
    });
  });
}
