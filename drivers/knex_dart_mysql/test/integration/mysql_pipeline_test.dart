/// Pipeline integration tests for KnexMySQL wrapper.
/// Verifies the KnexInterceptorPipeline routes all execution paths correctly
/// through interceptors against a real MySQL instance.
@Tags(['mysql'])
library;

import 'package:universal_io/io.dart';
import 'package:knex_dart/knex_dart.dart';
import 'package:knex_dart_mysql/knex_dart_mysql.dart';
import 'package:test/test.dart';

// ── Spy interceptor ───────────────────────────────────────────────────────────

class SpyInterceptor extends QueryInterceptor {
  final List<QueryExecutionContext> seen = [];

  @override
  Future<T> intercept<T>(
    QueryExecutionContext ctx,
    Future<T> Function() next,
  ) async {
    seen.add(ctx);
    return next();
  }

  @override
  Stream<T> interceptStream<T>(
    QueryExecutionContext ctx,
    Stream<T> Function() next,
  ) {
    seen.add(ctx);
    return next();
  }

  QueryExecutionContext get last => seen.last;
  void reset() => seen.clear();
}

// ── Connection helpers ────────────────────────────────────────────────────────

String get _host => Platform.environment['MYSQL_HOST'] ?? 'localhost';
int get _port => int.parse(Platform.environment['MYSQL_PORT'] ?? '3306');
String get _user => Platform.environment['MYSQL_USER'] ?? 'knex';
String get _password => Platform.environment['MYSQL_PASSWORD'] ?? 'knex';
String get _database => Platform.environment['MYSQL_DATABASE'] ?? 'knex_test';

const _table = 'pipeline_test_mysql';
const _ddlTable = 'pipeline_ddl_mysql';

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('KnexMySQL pipeline integration', () {
    KnexMySQL? db;
    late SpyInterceptor spy;
    var schemaReady = false;

    setUpAll(() async {
      spy = SpyInterceptor();
      db = await KnexMySQL.connect(
        host: _host,
        port: _port,
        user: _user,
        password: _password,
        database: _database,
        interceptors: [spy],
      );

      await db!.executeSchema((s) {
        s.createTableIfNotExists(_table, (t) {
          t.increments('id');
          t.string('name').nullable();
        });
      });
      schemaReady = true;
      spy.reset();
    });

    tearDownAll(() async {
      final current = db;
      if (current == null) return;
      if (schemaReady) {
        await current.rawSql('DROP TABLE IF EXISTS $_ddlTable');
        await current.rawSql('DROP TABLE IF EXISTS $_table');
      }
      await current.destroy();
    });

    setUp(() async {
      await db!.rawSql('DELETE FROM $_table');
      spy.reset();
    });

    test('insert: interceptor sees INSERT with table and dbSystem', () async {
      await db!.insert(db!(_table).insert({'name': 'Alice'}));
      expect(spy.seen, hasLength(1));
      expect(spy.last.operationName, 'INSERT');
      expect(spy.last.collectionName, _table);
      expect(spy.last.dbSystem, 'mysql');
      expect(spy.last.txId, isNull);
    });

    test('select: interceptor sees SELECT', () async {
      await db!.insert(db!(_table).insert({'name': 'Alice'}));
      spy.reset();

      final rows = await db!.select(db!(_table).select(['*']));
      expect(spy.last.operationName, 'SELECT');
      expect(spy.last.collectionName, _table);
      expect(rows, isNotEmpty);
    });

    test('update: interceptor sees UPDATE', () async {
      await db!.insert(db!(_table).insert({'name': 'Alice'}));
      spy.reset();

      await db!.update(
        db!(_table).update({'name': 'Bob'}).where('name', '=', 'Alice'),
      );
      expect(spy.last.operationName, 'UPDATE');
      expect(spy.last.collectionName, _table);
    });

    test('delete: interceptor sees DELETE', () async {
      await db!.insert(db!(_table).insert({'name': 'Bob'}));
      spy.reset();

      await db!.delete(db!(_table).delete().where('name', '=', 'Bob'));
      expect(spy.last.operationName, 'DELETE');
    });

    test('rawSql: interceptor sees correct operationName', () async {
      await db!.rawSql('SELECT 1');
      expect(spy.last.operationName, 'SELECT');
      expect(spy.last.collectionName, isNull);
    });

    test('raw alias: interceptor routes through rawSql', () async {
      await db!.raw('SELECT 1');
      expect(spy.last.operationName, 'SELECT');
      expect(spy.last.collectionName, isNull);
    });

    test('executeSchema DDL: interceptor sees CREATE', () async {
      try {
        await db!.executeSchema((s) {
          s.createTableIfNotExists(_ddlTable, (t) => t.increments('id'));
        });
        expect(spy.seen, isNotEmpty);
        for (final ctx in spy.seen) {
          expect(ctx.operationName, 'CREATE', reason: 'DDL: ${ctx.sql}');
        }
      } finally {
        await db!.rawSql('DROP TABLE IF EXISTS $_ddlTable');
      }
    });

    test('streamQuery: interceptor sees SELECT, rows delivered', () async {
      await db!.insert(db!(_table).insert({'name': 'Stream'}));
      spy.reset();

      final rows = await db!.streamQuery(db!(_table).select(['*'])).toList();
      expect(spy.seen, hasLength(1));
      expect(spy.last.operationName, 'SELECT');
      expect(rows, isNotEmpty);
    });

    test('trx: all queries inside have txId set', () async {
      await db!.trx((tx) async {
        await tx.insert(tx(_table).insert({'name': 'TrxA'}));
        await tx.select(tx(_table).select(['*']));
      });

      final trxCtxs = spy.seen.where((c) => c.txId != null).toList();
      expect(trxCtxs, isNotEmpty, reason: 'all trx queries must have txId');
      final txId = trxCtxs.first.txId!;
      for (final ctx in trxCtxs) {
        expect(ctx.txId, txId);
      }
    });

    test('trx: txId matches <instanceId>_<n> format', () async {
      String? capturedTxId;
      await db!.trx((tx) async {
        await tx.insert(tx(_table).insert({'name': 'TxFmt'}));
        capturedTxId = spy.last.txId;
      });
      expect(capturedTxId, matches(RegExp(r'^[0-9a-f]+_\d+$')));
    });

    test('nested trx: child txId prefixed with parent txId', () async {
      String? parentTxId;
      String? childTxId;

      await db!.trx((outer) async {
        await outer.insert(outer(_table).insert({'name': 'Parent'}));
        parentTxId = spy.last.txId;

        await outer.trx((inner) async {
          await inner.insert(inner(_table).insert({'name': 'Child'}));
          childTxId = spy.last.txId;
        });
      });

      expect(childTxId, startsWith(parentTxId!));
      expect(childTxId, isNot(equals(parentTxId)));
    });

    test('trx: rollback propagates errors and does not commit rows', () async {
      await expectLater(
        db!.trx((tx) async {
          await tx.insert(tx(_table).insert({'name': 'Rollback'}));
          throw StateError('force rollback');
        }),
        throwsA(isA<StateError>()),
      );

      final rows = await db!.select(
        db!(_table).select(['*']).where('name', '=', 'Rollback'),
      );
      expect(rows, isEmpty);
      expect(spy.seen.where((c) => c.txId != null), isNotEmpty);
    });

    test('no interceptors: zero spy calls (short-circuit)', () async {
      final dbClean = await KnexMySQL.connect(
        host: _host,
        port: _port,
        user: _user,
        password: _password,
        database: _database,
      );
      addTearDown(dbClean.destroy);
      final countBefore = spy.seen.length;
      await dbClean.select(dbClean(_table).select(['*']));
      expect(spy.seen.length, countBefore);
    });
  });
}
