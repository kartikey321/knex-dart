@Tags(['mssql'])
library;

import 'package:knex_dart/knex_dart.dart';
import 'package:knex_dart_mssql/knex_dart_mssql.dart';
import 'package:test/test.dart';
import 'package:universal_io/io.dart';

class _MssqlLiveSchemaClient extends Client {
  final KnexMssql db;

  _MssqlLiveSchemaClient(this.db)
    : super(KnexConfig(client: 'mssql', connection: const {}));

  @override
  String get driverName => 'mssql';

  @override
  Future<dynamic> rawQuery(String sql, List<dynamic> bindings) =>
      db.executeRaw(sql, bindings);

  @override
  Future<List<Map<String, dynamic>>> query(
    dynamic connection,
    String sql,
    List<dynamic> bindings,
  ) => db.executeRaw(sql, bindings);

  @override
  Stream<Map<String, dynamic>> streamQuery(
    dynamic connection,
    String sql,
    List<dynamic> bindings,
  ) => Stream.fromFuture(
    db.executeRaw(sql, bindings),
  ).asyncExpand((rows) => Stream<Map<String, dynamic>>.fromIterable(rows));

  @override
  QueryBuilder queryBuilder() => QueryBuilder(this);

  @override
  QueryCompiler queryCompiler(QueryBuilder builder) =>
      QueryCompiler(this, builder);

  @override
  dynamic formatter(dynamic builder) => Formatter(this, builder);

  @override
  SchemaBuilder schemaBuilder() => SchemaBuilder(this);

  @override
  SchemaCompiler schemaCompiler(SchemaBuilder builder) =>
      SchemaCompiler(this, builder);

  @override
  Future<Transaction> transaction([TransactionConfig? config]) =>
      throw UnimplementedError();

  @override
  void initializeDriver() {}

  @override
  void initializePool([PoolConfig? poolConfig]) {}

  @override
  Future acquireConnection() => throw UnimplementedError();

  @override
  Future<void> releaseConnection(connection) async {}

  @override
  String wrapIdentifierImpl(String value) =>
      value == '*' ? value : '[${value.replaceAll(']', ']]')}]';

  @override
  String parameterPlaceholder(int index) => '?';

  @override
  String formatValue(value) => value.toString();
}

Future<KnexMssql?> _tryConnect() async {
  final host = Platform.environment['MSSQL_HOST'] ?? 'localhost';
  final port = Platform.environment['MSSQL_PORT'] ?? '1433';
  final database = Platform.environment['MSSQL_DATABASE'] ?? 'knex_test';
  final username = Platform.environment['MSSQL_USER'] ?? 'sa';
  final password = Platform.environment['MSSQL_PASSWORD'] ?? 'Knex_Test1!';

  try {
    return await KnexMssql.connect(
      host: host,
      port: port,
      database: database,
      username: username,
      password: password,
    );
  } catch (_) {
    return null;
  }
}

void main() {
  KnexMssql? db;
  _MssqlLiveSchemaClient? live;
  String? skipReason;

  final suffix = DateTime.now().microsecondsSinceEpoch.toString();
  final sourceTable = 's_src_$suffix';
  final copiedTable = 's_copy_$suffix';
  final renamedTable = 's_ren_$suffix';
  final view1 = 's_v1_$suffix';
  final view2 = 's_v2_$suffix';

  Future<void> cleanup() async {
    if (db == null) return;
    await db!.executeRaw(
      'if object_id(?, \'V\') is not null DROP VIEW [$view2]',
      [view2],
    );
    await db!.executeRaw(
      'if object_id(?, \'V\') is not null DROP VIEW [$view1]',
      [view1],
    );
    await db!.executeRaw(
      'if object_id(?, \'U\') is not null DROP TABLE [$renamedTable]',
      [renamedTable],
    );
    await db!.executeRaw(
      'if object_id(?, \'U\') is not null DROP TABLE [$copiedTable]',
      [copiedTable],
    );
    await db!.executeRaw(
      'if object_id(?, \'U\') is not null DROP TABLE [$sourceTable]',
      [sourceTable],
    );
  }

  setUpAll(() async {
    final candidate = await _tryConnect();
    if (candidate == null) {
      skipReason =
          'SQL Server not reachable — start via `docker compose up mssql -d`';
      return;
    }
    db = candidate;
    live = _MssqlLiveSchemaClient(db!);
    await cleanup();
  });

  tearDownAll(() async {
    await cleanup();
    await db?.close();
  });

  group('MSSQL schema API integration parity', () {
    test('hasTable and hasColumn against real database', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.executeSchema((s) {
        s.createTable(sourceTable, (t) {
          t.integer('id').notNullable().primary();
          t.string('name').notNullable();
        });
      });

      expect(await live!.schemaBuilder().hasTable(sourceTable), isTrue);
      expect(
        await live!.schemaBuilder().hasColumn(sourceTable, 'name'),
        isTrue,
      );
      expect(
        await live!.schemaBuilder().hasColumn(sourceTable, 'missing_col'),
        isFalse,
      );
    });

    test('createTableLike with callback then renameTable', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.executeSchema((s) {
        s.createTableLike(copiedTable, sourceTable, (t) {
          t.string('nickname').nullable();
        });
      });

      await db!.execute(
        db!.queryBuilder().table(copiedTable).insert({
          'id': 1,
          'name': 'alpha',
          'nickname': 'a',
        }),
      );

      final rowsBeforeRename = await db!.select(
        db!.queryBuilder().from(copiedTable).select(['name', 'nickname']),
      );
      expect(rowsBeforeRename, hasLength(1));
      expect(rowsBeforeRename.first['nickname'], 'a');

      await db!.executeSchema((s) {
        s.renameTable(copiedTable, renamedTable);
      });

      expect(await live!.schemaBuilder().hasTable(renamedTable), isTrue);
    });

    test('createView, renameView, and dropViewIfExists', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.executeSchema((s) {
        s.createView(view1, 'select 1 as n');
        s.renameView(view1, view2);
      });

      final rows = await db!.executeRaw('SELECT n FROM [$view2]');
      expect(rows, hasLength(1));
      expect(rows.first['n'], 1);

      await db!.executeSchema((s) {
        s.dropViewIfExists(view2);
        s.dropViewIfExists(view2);
      });

      await expectLater(
        db!.executeRaw('SELECT n FROM [$view2]'),
        throwsA(anything),
      );
    });

    test('dropTableIfExists is idempotent', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.executeSchema((s) {
        s.dropTableIfExists(sourceTable);
        s.dropTableIfExists(sourceTable);
      });

      expect(await live!.schemaBuilder().hasTable(sourceTable), isFalse);
    });
  });
}
