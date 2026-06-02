import 'dart:async';

import 'package:knex_dart/knex_dart.dart';
import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';
import 'package:test/test.dart';

// ── Spy interceptor ───────────────────────────────────────────────────────────

class SpyInterceptor extends QueryInterceptor {
  final List<QueryExecutionContext> seen = [];
  final List<Object> errors = [];

  @override
  Future<T> intercept<T>(
    QueryExecutionContext ctx,
    Future<T> Function() next,
  ) async {
    seen.add(ctx);
    try {
      return await next();
    } catch (e) {
      errors.add(e);
      rethrow;
    }
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
  void reset() {
    seen.clear();
    errors.clear();
  }
}

// ── Test setup ─────────────────────────────────────────────────────────────────

void main() {
  group('SQLite pipeline integration', () {
    late KnexSQLite db;
    late SpyInterceptor spy;

    setUp(() async {
      spy = SpyInterceptor();
      db = await KnexSQLite.connect(
        filename: ':memory:',
        interceptors: [spy],
      );

      await db.executeSchema((s) {
        s.createTable('users', (t) {
          t.increments('id');
          t.string('name').nullable();
          t.integer('age').nullable();
        });
      });
      spy.reset(); // don't count schema setup calls
    });

    tearDown(() => db.destroy());

    // ── CRUD operations ────────────────────────────────────────────────────

    test('insert: interceptor sees INSERT operationName and table', () async {
      await db.insert(db('users').insert({'name': 'Alice', 'age': 30}));
      expect(spy.seen, hasLength(1));
      expect(spy.last.operationName, 'INSERT');
      expect(spy.last.collectionName, 'users');
      expect(spy.last.querySummary, 'INSERT users');
      expect(spy.last.dbSystem, 'sqlite');
      expect(spy.last.txId, isNull);
    });

    test('select: interceptor sees SELECT operationName and table', () async {
      await db.insert(db('users').insert({'name': 'Bob', 'age': 25}));
      spy.reset();

      final rows = await db.select(db('users').select(['*']));
      expect(spy.last.operationName, 'SELECT');
      expect(spy.last.collectionName, 'users');
      expect(rows, isNotEmpty);
    });

    test('update: interceptor sees UPDATE', () async {
      await db.insert(db('users').insert({'name': 'Carol', 'age': 20}));
      spy.reset();

      await db.update(db('users').update({'age': 21}).where('name', '=', 'Carol'));
      expect(spy.last.operationName, 'UPDATE');
      expect(spy.last.collectionName, 'users');
    });

    test('delete: interceptor sees DELETE', () async {
      await db.insert(db('users').insert({'name': 'Dave', 'age': 40}));
      spy.reset();

      await db.delete(db('users').delete().where('name', '=', 'Dave'));
      expect(spy.last.operationName, 'DELETE');
      expect(spy.last.collectionName, 'users');
    });

    test('select with where clause: SQL contains parameter', () async {
      await db.insert(db('users').insert({'name': 'Eve', 'age': 35}));
      spy.reset();

      await db.select(db('users').select(['*']).where('name', '=', 'Eve'));
      expect(spy.last.sql, contains('where'));
      expect(spy.last.parameters, isNotEmpty);
    });

    // ── Raw SQL ────────────────────────────────────────────────────────────

    test('rawSql: interceptor sees correct operationName', () async {
      await db.rawSql('SELECT 1');
      expect(spy.last.operationName, 'SELECT');
      expect(spy.last.collectionName, isNull);
      expect(spy.last.querySummary, 'SELECT');
    });

    test('rawSql with parameters: parameters passed to context', () async {
      await db.insert(db('users').insert({'name': 'Frank', 'age': 50}));
      spy.reset();

      await db.rawSql('SELECT * FROM users WHERE age > ?', [30]);
      expect(spy.last.parameters, [30]);
    });

    // ── DDL via executeSchema ──────────────────────────────────────────────

    test('executeSchema: each DDL statement intercepted as CREATE', () async {
      await db.executeSchema((s) {
        s.createTable('orders', (t) {
          t.increments('id');
          t.integer('user_id').nullable();
        });
      });
      expect(spy.seen, isNotEmpty);
      for (final ctx in spy.seen) {
        expect(ctx.operationName, 'CREATE',
            reason: 'DDL: ${ctx.sql}');
      }
    });

    // ── Streaming ──────────────────────────────────────────────────────────

    test('streamQuery: interceptor sees SELECT, stream delivers rows', () async {
      await db.insert(db('users').insert([
        {'name': 'G', 'age': 1},
        {'name': 'H', 'age': 2},
      ]));
      spy.reset();

      final rows = await db
          .streamQuery(db('users').select(['*']))
          .toList();

      expect(spy.seen, hasLength(1));
      expect(spy.last.operationName, 'SELECT');
      expect(rows, hasLength(2));
    });

    // ── Transactions ───────────────────────────────────────────────────────

    test('trx: every query inside has txId set', () async {
      await db.trx((tx) async {
        await tx.insert(tx('users').insert({'name': 'Trx1', 'age': 10}));
        await tx.select(tx('users').select(['*']));
      });

      final trxCtxs = spy.seen.where((c) => c.txId != null).toList();
      expect(trxCtxs, isNotEmpty, reason: 'all trx queries must have txId');
      // All txIds inside one transaction share the same prefix.
      final txId = trxCtxs.first.txId!;
      for (final ctx in trxCtxs) {
        expect(ctx.txId, txId, reason: 'same transaction = same txId');
      }
    });

    test('trx: txId matches pipeline nextUid format <instanceId>_<n>', () async {
      String? capturedTxId;
      await db.trx((tx) async {
        await tx.insert(tx('users').insert({'name': 'TxFmt', 'age': 1}));
        capturedTxId = spy.last.txId;
      });
      expect(capturedTxId, isNotNull);
      expect(capturedTxId, matches(RegExp(r'^[0-9a-f]+_\d+$')));
    });

    test('nested trx: child txId contains parent txId as prefix', () async {
      String? parentTxId;
      String? childTxId;

      await db.trx((outer) async {
        await outer.insert(outer('users').insert({'name': 'P', 'age': 1}));
        parentTxId = spy.last.txId;

        await outer.trx((inner) async {
          await inner.insert(inner('users').insert({'name': 'C', 'age': 2}));
          childTxId = spy.last.txId;
        });
      });

      expect(parentTxId, isNotNull);
      expect(childTxId, isNotNull);
      expect(childTxId, isNot(equals(parentTxId)));
      expect(childTxId, startsWith(parentTxId!),
          reason: 'child txId must be prefixed with parent txId');
    });

    test('trx rollback on error: interceptor sees error queries', () async {
      Object? caught;
      try {
        await db.trx((tx) async {
          await tx.insert(tx('users').insert({'name': 'Fail', 'age': 1}));
          throw StateError('forced rollback');
        });
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<StateError>());
      // At least the insert was seen by the interceptor.
      expect(spy.seen.where((c) => c.operationName == 'INSERT'), isNotEmpty);
    });

    // ── QueryBuilder subquery FROM — tableName safety ──────────────────────

    test('subquery as FROM: does not throw, collectionName is null', () async {
      await db.insert(db('users').insert({'name': 'Sub', 'age': 5}));
      spy.reset();

      // Use a subquery as the FROM source.
      final sub = db('users').select(['name']).as('sub');
      final outer = db.queryBuilder().from(sub).select(['*']);
      final rows = await db.select(outer);

      expect(spy.last.collectionName, isNull,
          reason: 'subquery FROM must not produce a collection name');
      expect(rows, isNotEmpty);
    });

    // ── No interceptors — zero overhead path ──────────────────────────────

    test('no interceptors: spy sees nothing (short-circuit path)', () async {
      final dbNoOtel = await KnexSQLite.connect(filename: ':memory:');
      addTearDown(dbNoOtel.destroy);

      await dbNoOtel.executeSchema((s) {
        s.createTable('t', (t) => t.increments('id'));
      });

      // Spy is attached to original db, not dbNoOtel.
      final countBefore = spy.seen.length;
      await dbNoOtel.select(dbNoOtel('t').select(['*']));
      expect(spy.seen.length, countBefore,
          reason: 'no-interceptor db must not touch the spy');
    });
  });
}
