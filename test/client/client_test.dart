import 'package:knex_dart/src/client/client.dart';
import 'package:knex_dart/src/client/knex_config.dart';
import 'package:knex_dart/src/formatter/formatter.dart';
import 'package:knex_dart/src/query/query_builder.dart';
import 'package:knex_dart/src/query/query_compiler.dart';
import 'package:knex_dart/src/schema/schema_builder.dart';
import 'package:knex_dart/src/schema/schema_compiler.dart';
import 'package:knex_dart/src/transaction/transaction.dart';
import 'package:test/test.dart';

import '../mocks/mock_client.dart';

void main() {
  group('Client - wrapIdentifier', () {
    test('passes through * unchanged', () {
      final client = MockClient();
      expect(client.wrapIdentifier('*'), equals('*'));
    });

    test('delegates to wrapIdentifierImpl for normal identifiers', () {
      final client = MockClient();
      expect(client.wrapIdentifier('users'), equals('"users"'));
    });

    test('uses custom wrapIdentifier from config when provided', () {
      final client = _CustomClient(
        KnexConfig(
          client: 'mock',
          connection: {},
          wrapIdentifier: (id) => '[[$id]]',
        ),
      );
      expect(client.wrapIdentifier('users'), equals('[[users]]'));
    });
  });

  group('Client - alias', () {
    test('formats as value AS alias', () {
      final client = MockClient();
      expect(client.alias('"users"', '"u"'), equals('"users" AS "u"'));
    });
  });

  group('Client - parameter', () {
    test('appends value to bindings and returns placeholder', () {
      final client = MockClient();
      final bindings = <dynamic>[];

      expect(client.parameter('active', bindings), equals(r'$1'));
      expect(bindings, equals(['active']));

      expect(client.parameter(42, bindings), equals(r'$2'));
      expect(bindings, equals(['active', 42]));
    });
  });

  group('Client - prepareBindings', () {
    test('returns bindings unchanged by default', () {
      final client = MockClient();
      final bindings = [1, 'two', true];
      expect(client.prepareBindings(bindings), equals(bindings));
    });
  });

  group('Client - positionBindings', () {
    test('returns sql unchanged by default', () {
      final client = MockClient();
      const sql = 'select * from "users" where "id" = ?';
      expect(client.positionBindings(sql), equals(sql));
    });
  });

  group('Client - postProcessResponse', () {
    test('returns response unchanged when no hook configured', () {
      final client = MockClient();
      final response = [
        {'id': 1},
      ];
      expect(client.postProcessResponse(response, null), equals(response));
    });

    test('applies postProcessResponse function from config', () {
      final client = _CustomClient(
        KnexConfig(
          client: 'mock',
          connection: {},
          postProcessResponse: (response, ctx) =>
              (response as List).map((r) => {'wrapped': r}).toList(),
        ),
      );
      final response = [
        {'id': 1},
      ];
      final result = client.postProcessResponse(response, null) as List;
      expect(result.first, equals({'wrapped': {'id': 1}}));
    });
  });

  group('Client - event streams', () {
    test('onQuery emits QueryEvent when emitQuery is called', () async {
      final client = _TestableClient();

      expect(
        client.onQuery,
        emits(
          predicate<QueryEvent>(
            (e) =>
                e.sql == 'select 1' && e.bindings.isEmpty && e.uid == 'uid-1',
          ),
        ),
      );

      client.triggerEmitQuery('select 1', [], 'uid-1');
    });

    test('QueryEvent includes txId when provided', () async {
      final client = _TestableClient();

      expect(
        client.onQuery,
        emits(predicate<QueryEvent>((e) => e.txId == 'tx-99')),
      );

      client.triggerEmitQuery('select 1', [], 'uid-1', 'tx-99');
    });

    test('onQueryError emits QueryErrorEvent', () async {
      final client = _TestableClient();
      final err = Exception('boom');

      expect(
        client.onQueryError,
        emits(
          predicate<QueryErrorEvent>(
            (e) => e.error == err && e.query.sql == 'bad sql',
          ),
        ),
      );

      client.triggerEmitQueryError(err, StackTrace.current, 'bad sql', []);
    });

    test('onQueryError uses "unknown" uid when not provided', () async {
      final client = _TestableClient();
      final err = Exception('fail');

      expect(
        client.onQueryError,
        emits(predicate<QueryErrorEvent>((e) => e.query.uid == 'unknown')),
      );

      client.triggerEmitQueryError(err, StackTrace.current, 'sql', []);
    });

    test('onQueryError uses provided uid', () async {
      final client = _TestableClient();
      final err = Exception('fail');

      expect(
        client.onQueryError,
        emits(predicate<QueryErrorEvent>((e) => e.query.uid == 'my-uid')),
      );

      client.triggerEmitQueryError(
        err,
        StackTrace.current,
        'sql',
        [],
        'my-uid',
      );
    });

    test('onQueryResponse emits QueryResponseEvent', () async {
      final client = _TestableClient();
      final response = [
        {'id': 1},
      ];

      expect(
        client.onQueryResponse,
        emits(
          predicate<QueryResponseEvent>(
            (e) => e.response == response && e.query.sql == 'select 1',
          ),
        ),
      );

      client.triggerEmitQueryResponse(response, 'select 1', [], 'uid-1');
    });
  });

  group('Client - destroy', () {
    test('closes all stream controllers without error', () async {
      final client = _TestableClient();
      await expectLater(client.destroy(), completes);
    });

    test('onQuery stream is done after destroy', () async {
      final client = _TestableClient();
      await client.destroy();
      expect(client.onQuery.isEmpty, completes);
    });
  });

  group('QueryEvent', () {
    test('constructs with required fields and null txId', () {
      const e = QueryEvent(sql: 'select 1', bindings: [], uid: 'uid-1');
      expect(e.sql, equals('select 1'));
      expect(e.bindings, isEmpty);
      expect(e.uid, equals('uid-1'));
      expect(e.txId, isNull);
    });

    test('constructs with optional txId', () {
      const e = QueryEvent(
        sql: 'select 1',
        bindings: [],
        uid: 'uid-1',
        txId: 'tx-1',
      );
      expect(e.txId, equals('tx-1'));
    });
  });

  group('QueryErrorEvent', () {
    test('constructs with all required fields', () {
      final err = Exception('oops');
      final st = StackTrace.current;
      const query = QueryEvent(sql: 'bad', bindings: [], uid: 'uid-1');

      final event = QueryErrorEvent(error: err, stackTrace: st, query: query);

      expect(event.error, equals(err));
      expect(event.stackTrace, equals(st));
      expect(event.query, equals(query));
    });
  });

  group('QueryResponseEvent', () {
    test('constructs with response and query, builder defaults to null', () {
      const query = QueryEvent(sql: 'select 1', bindings: [], uid: 'uid-1');
      final event = QueryResponseEvent(
        response: [
          {'id': 1},
        ],
        query: query,
      );

      expect(event.response, equals([{'id': 1}]));
      expect(event.query, equals(query));
      expect(event.builder, isNull);
    });
  });
}

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Client with a custom KnexConfig (for wrapIdentifier / postProcessResponse).
class _CustomClient extends Client {
  _CustomClient(super.config);

  @override
  String get driverName => 'mock';

  @override
  void initializeDriver() {}

  @override
  void initializePool([poolConfig]) {}

  @override
  QueryBuilder queryBuilder() => QueryBuilder(this);

  @override
  QueryCompiler queryCompiler(QueryBuilder builder) =>
      QueryCompiler(this, builder);

  @override
  Formatter formatter(dynamic builder) => Formatter(this, builder);

  @override
  SchemaBuilder schemaBuilder() => SchemaBuilder(this);

  @override
  SchemaCompiler schemaCompiler(SchemaBuilder builder) =>
      SchemaCompiler(this, builder);

  @override
  Future<Transaction> transaction([TransactionConfig? config]) =>
      throw UnimplementedError();

  @override
  Future<dynamic> rawQuery(String sql, List<dynamic> bindings) =>
      throw UnimplementedError();

  @override
  Future<List<Map<String, dynamic>>> query(
    dynamic connection,
    String sql,
    List<dynamic> bindings,
  ) => throw UnimplementedError();

  @override
  Stream<Map<String, dynamic>> streamQuery(
    dynamic connection,
    String sql,
    List<dynamic> bindings,
  ) => throw UnimplementedError();

  @override
  Future<dynamic> acquireConnection() => throw UnimplementedError();

  @override
  Future<void> releaseConnection(dynamic connection) => Future.value();

  @override
  String wrapIdentifierImpl(String identifier) => '"$identifier"';

  @override
  String parameterPlaceholder(int index) => '\$$index';

  @override
  String formatValue(dynamic value) => value.toString();
}

/// MockClient subclass that exposes protected emit methods for testing.
class _TestableClient extends MockClient {
  void triggerEmitQuery(
    String sql,
    List<dynamic> bindings,
    String uid, [
    String? txId,
  ]) {
    emitQuery(sql, bindings, uid, txId);
  }

  void triggerEmitQueryError(
    Object error,
    StackTrace stackTrace,
    String sql,
    List<dynamic> bindings, [
    String? uid,
  ]) {
    emitQueryError(error, stackTrace, sql, bindings, uid);
  }

  void triggerEmitQueryResponse(
    dynamic response,
    String sql,
    List<dynamic> bindings,
    String uid,
  ) {
    emitQueryResponse(response, sql, bindings, uid);
  }
}
