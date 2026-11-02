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
String get _database => Platform.environment['MYSQL_DATABASE'] ?? 'knex_test';

/// A MySQL account used by **this file only**.
///
/// The whole measurement depends on it. MySQL shows a user without the
/// `PROCESS` privilege only their *own* threads in
/// `information_schema.PROCESSLIST`, so connecting as an account nobody else
/// uses makes the server itself scope the view to this test. Without that,
/// there is no way to tell this test's connections apart from the five other
/// integration files sharing the server, and no assertion on the numbers can
/// be made to work — see the history in issue #38.
///
/// Deliberately not defaulted to [_user]: falling back to the shared account
/// would leave the test running with a measurement that cannot distinguish a
/// leak from unrelated traffic, which is how it was flaky in the first place.
/// Unset means skip.
String? get _raceUser => Platform.environment['MYSQL_RACE_USER'];
String get _racePassword =>
    Platform.environment['MYSQL_RACE_PASSWORD'] ?? 'knex_race';

Future<MySQLClient> _connect() => MySQLClient.connect(
  host: _host,
  port: _port,
  user: _raceUser!,
  password: _racePassword,
  database: _database,
  poolConfig: const PoolConfig(min: 0, max: 2),
);

/// The ids of the connections held by [_raceUser], newest state each call.
///
/// Identities rather than a count, because a count cannot answer the question:
/// a leak and an unrelated disconnect move a global counter in opposite
/// directions, so no threshold on it distinguishes them. A leaked connection
/// is an id present afterwards that was not present before.
///
/// The `USER` filter is belt-and-braces — the server already restricts this
/// view to [_raceUser]'s own threads, since the account is granted no
/// `PROCESS` privilege.
Future<Set<int>> _connectionIds(MySQLClient monitor) async {
  final rows = await monitor.raw(
    'SELECT ID, USER FROM information_schema.PROCESSLIST',
  );
  return {
    for (final row in rows)
      if (row['USER'].toString() == _raceUser) int.parse(row['ID'].toString()),
  };
}

void main() {
  group('MySQLClient close() racing an in-flight connection create', () {
    MySQLClient? monitor;
    String? skipReason;

    setUpAll(() async {
      if (_raceUser == null) {
        skipReason =
            'MYSQL_RACE_USER is not set. This test needs a MySQL account used '
            'by nothing else so the server scopes PROCESSLIST to it; see the '
            'note on _raceUser. Provision it as CI does, or skip.';
        return;
      }
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
