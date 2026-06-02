/// Pipeline integration tests for the SQL Server wrapper.
@Tags(['mssql'])
library;

import 'package:universal_io/io.dart';
import 'package:knex_dart/knex_dart.dart';
import 'package:knex_dart_mssql/knex_dart_mssql.dart';
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

String get _host => Platform.environment['MSSQL_HOST'] ?? 'localhost';
String get _port => Platform.environment['MSSQL_PORT'] ?? '1433';
String get _database => Platform.environment['MSSQL_DATABASE'] ?? 'knex_test';
String get _user => Platform.environment['MSSQL_USER'] ?? 'sa';
String get _password => Platform.environment['MSSQL_PASSWORD'] ?? 'Knex_Test1!';

const _table = 'pipeline_test_mssql';
const _ddlTable = 'pipeline_ddl_mssql';

Future<KnexMssql?> _tryConnect({
  List<QueryInterceptor> interceptors = const [],
}) async {
  try {
    return await KnexMssql.connect(
      host: _host,
      port: _port,
      database: _database,
      username: _user,
      password: _password,
      interceptors: interceptors,
    );
  } catch (_) {
    return null;
  }
}

void main() {
  group('KnexMssql pipeline integration', () {
    KnexMssql? db;
    late SpyInterceptor spy;
    String? skipReason;

    setUpAll(() async {
      final candidate = await _tryConnect();
      if (candidate == null) {
        skipReason =
            'SQL Server not reachable at $_host:$_port — start via `docker compose up mssql mssql-init -d`';
      }
      await candidate?.close();
    });

    setUp(() async {
      if (skipReason != null) return;

      spy = SpyInterceptor();
      db = await _tryConnect(interceptors: [spy]);
      await db!.executeSchema((s) {
        s.dropTableIfExists(_ddlTable);
        s.dropTableIfExists(_table);
        s.createTable(_table, (t) {
          t.integer('id').notNullable().primary();
          t.string('name');
        });
      });
      spy.reset();
    });

    tearDown(() async {
      await db?.close();
      db = null;
    });

    test('CRUD, raw, DDL, and trx route through interceptors', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.insert(db!(_table).insert({'id': 1, 'name': 'Alice'}));
      expect(spy.last.operationName, 'INSERT');
      expect(spy.last.collectionName, _table);
      expect(spy.last.dbSystem, 'mssql');
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
      expect(txContexts.any((c) => c.txId!.contains('_sp')), isTrue);
    });
  });
}
