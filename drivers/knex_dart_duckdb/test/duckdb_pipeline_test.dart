import 'package:knex_dart/knex_dart.dart';
import 'package:knex_dart_duckdb/knex_dart_duckdb.dart';
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

Future<KnexDuckDB?> _tryOpen({
  List<QueryInterceptor> interceptors = const [],
}) async {
  try {
    return await KnexDuckDB.memory(
      interceptors: interceptors,
    ).timeout(const Duration(minutes: 2));
  } catch (_) {
    return null;
  }
}

void main() {
  group('DuckDB pipeline integration', () {
    KnexDuckDB? db;
    late SpyInterceptor spy;
    String? skipReason;

    setUpAll(() async {
      final candidate = await _tryOpen();
      if (candidate == null) {
        skipReason =
            'DuckDB native library not found — install via `brew install duckdb`';
      }
      await candidate?.close();
    });

    setUp(() async {
      if (skipReason != null) return;

      spy = SpyInterceptor();
      db = await _tryOpen(interceptors: [spy]);
      await db!.executeSchema((s) {
        s.createTable('pipeline_test_duckdb', (t) {
          t.integer('id').primary();
          t.string('name');
        });
      });
      spy.reset();
    });

    tearDown(() async {
      await db?.close();
      db = null;
    });

    test('CRUD, raw, stream, and trx routes through interceptors', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.insert(
        db!('pipeline_test_duckdb').insert({'id': 1, 'name': 'Alice'}),
      );
      expect(spy.last.operationName, 'INSERT');
      expect(spy.last.collectionName, 'pipeline_test_duckdb');
      spy.reset();

      final selected = await db!.select(
        db!('pipeline_test_duckdb').select(['*']),
      );
      expect(selected, hasLength(1));
      expect(spy.last.operationName, 'SELECT');
      spy.reset();

      await db!.update(
        db!('pipeline_test_duckdb').where('id', '=', 1).update({'name': 'Bob'}),
      );
      expect(spy.last.operationName, 'UPDATE');
      spy.reset();

      await db!.rawSql('SELECT 1');
      expect(spy.last.operationName, 'SELECT');
      spy.reset();

      final streamed = await db!.stream(db!('pipeline_test_duckdb')).toList();
      expect(streamed, hasLength(1));
      expect(spy.last.operationName, 'SELECT');
      spy.reset();

      await db!.trx((tx) async {
        await tx.insert(
          tx('pipeline_test_duckdb').insert({'id': 2, 'name': 'Trx'}),
        );
      });

      final txContexts = spy.seen.where((c) => c.txId != null).toList();
      expect(txContexts, isNotEmpty);
      expect(txContexts.every((c) => c.txId == txContexts.first.txId), isTrue);
    });
  });
}
