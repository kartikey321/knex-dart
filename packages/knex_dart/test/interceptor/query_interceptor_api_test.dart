import 'dart:async';

import 'package:knex_dart/knex_dart.dart';
import 'package:test/test.dart';

// A minimal interceptor that only overrides the required method.
// If QueryInterceptor were 'abstract interface class', this would fail to
// compile with "missing interceptStream".  The abstract class fix must hold.
class FutureOnlyInterceptor extends QueryInterceptor {
  final List<String> log = [];

  @override
  Future<T> intercept<T>(
    QueryExecutionContext ctx,
    Future<T> Function() next,
  ) async {
    log.add('intercept:${ctx.operationName}');
    return next();
  }
  // interceptStream() is inherited from QueryInterceptor — no override needed.
}

// An interceptor that also overrides interceptStream to verify chaining.
class FullInterceptor extends QueryInterceptor {
  final List<String> log = [];

  @override
  Future<T> intercept<T>(
    QueryExecutionContext ctx,
    Future<T> Function() next,
  ) async {
    log.add('future:${ctx.operationName}');
    return next();
  }

  @override
  Stream<T> interceptStream<T>(
    QueryExecutionContext ctx,
    Stream<T> Function() next,
  ) {
    log.add('stream:${ctx.operationName}');
    return next();
  }
}

void main() {
  group('QueryInterceptor API contract', () {
    test('FutureOnlyInterceptor compiles — interceptStream default inherited', () {
      // This test would not compile at all if the abstract class fix regressed.
      final i = FutureOnlyInterceptor();
      expect(i, isA<QueryInterceptor>());
    });

    test('default interceptStream() is a transparent passthrough', () async {
      final i = FutureOnlyInterceptor();
      final ctx = _ctx('SELECT', 'SELECT users');
      final items = [1, 2, 3];
      final result = await i
          .interceptStream<int>(ctx, () => Stream.fromIterable(items))
          .toList();
      expect(result, [1, 2, 3]);
    });

    test('future interception is called', () async {
      final i = FutureOnlyInterceptor();
      final ctx = _ctx('INSERT', 'INSERT orders');
      await i.intercept<List<Map<String, dynamic>>>(ctx, () async => []);
      expect(i.log, ['intercept:INSERT']);
    });

    test('FullInterceptor overrides both methods', () async {
      final i = FullInterceptor();
      final ctx = _ctx('SELECT', 'SELECT items');
      await i.intercept<List<Map<String, dynamic>>>(ctx, () async => []);
      await i.interceptStream<int>(ctx, () => const Stream.empty()).toList();
      expect(i.log, ['future:SELECT', 'stream:SELECT']);
    });
  });
}

QueryExecutionContext _ctx(String op, String summary) => QueryExecutionContext(
      dbSystem: 'sqlite',
      sql: 'SELECT 1',
      parameters: const [],
      operationName: op,
      querySummary: summary,
    );
