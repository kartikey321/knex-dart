/// Pipeline integration tests for the Turso wrapper against a real sqld server.
@Tags(['turso'])
library;

import 'package:universal_io/io.dart';
import 'package:knex_dart/knex_dart.dart';
import 'package:knex_dart_turso/knex_dart_turso.dart';
import 'package:test/test.dart';

class SpyInterceptor extends QueryInterceptor {
  final seen = <QueryExecutionContext>[];

  @override
  Future<T> intercept<T>(
    QueryExecutionContext ctx,
    Future<T> Function() next,
  ) async {
    seen.add(ctx);
    return next();
  }

  QueryExecutionContext get last => seen.last;
  void reset() => seen.clear();
}

String get _url =>
    Platform.environment['TURSO_URL'] ?? 'http://127.0.0.1:18080';
String? get _token => Platform.environment['TURSO_AUTH_TOKEN'];

const _table = 'pipeline_test_turso';
const _ddlTable = 'pipeline_ddl_turso';

Future<KnexTurso?> _tryOpen({
  List<QueryInterceptor> interceptors = const [],
}) async {
  try {
    final db = KnexTurso(
      url: _url,
      authToken: _token ?? '',
      interceptors: interceptors,
    );
    await db.rawSql('SELECT 1');
    return db;
  } catch (e) {
    // Only swallow connection-level failures (server not running).
    // Rethrow driver bugs so they surface as real failures.
    final msg = e.toString();
    if (msg.contains('Connection refused') ||
        msg.contains('SocketException') ||
        msg.contains('Failed host lookup') ||
        msg.contains('timed out')) {
      return null;
    }
    rethrow;
  }
}

void main() {
  group('KnexTurso pipeline integration', () {
    KnexTurso? db;
    late SpyInterceptor spy;
    String? skipReason;

    setUpAll(() async {
      final candidate = await _tryOpen();
      if (candidate == null) {
        skipReason =
            'sqld not reachable at $_url — start via `docker compose up sqld -d`';
      }
      candidate?.close();
    });

    setUp(() async {
      if (skipReason != null) return;

      spy = SpyInterceptor();
      db = await _tryOpen(interceptors: [spy]);
      await db!.executeSchema((s) {
        s.dropTableIfExists(_ddlTable);
        s.dropTableIfExists(_table);
        s.createTable(_table, (t) {
          t.integer('id').primary();
          t.string('name');
        });
      });
      spy.reset();
    });

    tearDown(() {
      db?.close();
      db = null;
    });

    test('CRUD, raw, DDL, and trx route through interceptors', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.insert(db!(_table).insert({'id': 1, 'name': 'Alice'}));
      expect(spy.last.operationName, 'INSERT');
      expect(spy.last.collectionName, _table);
      expect(spy.last.dbSystem, 'sqlite');
      spy.reset();

      final rows = await db!.select(db!(_table).select(['*']));
      expect(rows, hasLength(1));
      expect(spy.last.operationName, 'SELECT');
      spy.reset();

      await db!.update(db!(_table).where('id', '=', 1).update({'name': 'Bob'}));
      expect(spy.last.operationName, 'UPDATE');
      spy.reset();

      await db!.rawSql('SELECT 1');
      expect(spy.last.operationName, 'SELECT');
      spy.reset();

      await db!.executeSchema((s) {
        s.createTable(_ddlTable, (t) => t.integer('id'));
      });
      expect(spy.last.operationName, 'CREATE');
      spy.reset();

      await db!.trx((tx) async {
        await tx.insert(tx(_table).insert({'id': 2, 'name': 'Trx'}));
        await tx.trx((inner) async {
          await inner.insert(inner(_table).insert({'id': 3, 'name': 'Nested'}));
        });
      });

      final txContexts = spy.seen.where((c) => c.txId != null).toList();
      expect(txContexts, isNotEmpty);
      expect(txContexts.any((c) => c.operationName == 'SAVEPOINT'), isTrue);
    });
  });
}
