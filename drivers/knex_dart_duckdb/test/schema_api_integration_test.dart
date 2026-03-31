import 'package:knex_dart/knex_dart.dart';
import 'package:knex_dart_duckdb/knex_dart_duckdb.dart';
import 'package:test/test.dart';

class _DuckDbLiveSchemaClient extends Client {
  final KnexDuckDB db;

  _DuckDbLiveSchemaClient(this.db)
    : super(KnexConfig(client: 'duckdb', connection: const {}));

  @override
  String get driverName => 'duckdb';

  @override
  Future<dynamic> rawQuery(String sql, List<dynamic> bindings) =>
      db.raw(sql, bindings);

  @override
  Future<List<Map<String, dynamic>>> query(
    dynamic connection,
    String sql,
    List<dynamic> bindings,
  ) => db.raw(sql, bindings);

  @override
  Stream<Map<String, dynamic>> streamQuery(
    dynamic connection,
    String sql,
    List<dynamic> bindings,
  ) => Stream.fromFuture(
    db.raw(sql, bindings),
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
  String wrapIdentifierImpl(String value) => value == '*' ? value : '"$value"';

  @override
  String parameterPlaceholder(int index) => '\$$index';

  @override
  String formatValue(value) => value.toString();
}

Future<KnexDuckDB?> _tryOpen() async {
  try {
    return await KnexDuckDB.memory().timeout(const Duration(minutes: 2));
  } catch (_) {
    return null;
  }
}

void main() {
  KnexDuckDB? db;
  _DuckDbLiveSchemaClient? live;
  String? skipReason;

  final suffix = DateTime.now().microsecondsSinceEpoch.toString();
  final sourceTable = 'schema_src_$suffix';
  final copiedTable = 'schema_copy_$suffix';
  final renamedTable = 'schema_renamed_$suffix';
  final view1 = 'schema_view_a_$suffix';

  Future<void> cleanup() async {
    if (db == null) return;
    await db!.raw('drop view if exists "$view1"');
    await db!.raw('drop table if exists "$renamedTable"');
    await db!.raw('drop table if exists "$copiedTable"');
    await db!.raw('drop table if exists "$sourceTable"');
  }

  setUpAll(() async {
    final candidate = await _tryOpen();
    if (candidate == null) {
      skipReason =
          'DuckDB native library not found — install via `brew install duckdb`';
      return;
    }
    db = candidate;
    live = _DuckDbLiveSchemaClient(db!);
    await cleanup();
  });

  tearDownAll(() async {
    await cleanup();
    await db?.close();
  });

  group('DuckDB schema API integration parity', () {
    test('hasTable and hasColumn against real database', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.executeSchema((s) {
        s.createTable(sourceTable, (t) {
          t.integer('id').primary();
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

    test('createViewOrReplace and dropViewIfExists', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.executeSchema((s) {
        s.createViewOrReplace(view1, 'select 1 as n');
      });

      final rows = await db!.raw('select n from "$view1"');
      expect(rows, hasLength(1));
      expect(rows.first['n'], 1);

      await db!.executeSchema((s) {
        s.dropViewIfExists(view1);
        s.dropViewIfExists(view1);
      });

      await expectLater(db!.raw('select n from "$view1"'), throwsA(anything));
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
