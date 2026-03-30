@Tags(['postgres'])
library;

import 'package:universal_io/io.dart';
import 'package:knex_dart/knex_dart.dart';
import 'package:knex_dart_postgres/knex_dart_postgres.dart';
import 'package:test/test.dart';

class _PgLiveSchemaClient extends Client {
  final KnexPostgres db;

  _PgLiveSchemaClient(this.db)
    : super(KnexConfig(client: 'pg', connection: const {}));

  @override
  String get driverName => 'pg';

  @override
  Future<dynamic> rawQuery(String sql, List<dynamic> bindings) =>
      db.rawSql(sql, bindings);

  @override
  Future<List<Map<String, dynamic>>> query(
    dynamic connection,
    String sql,
    List<dynamic> bindings,
  ) => db.rawSql(sql, bindings);

  @override
  Stream<Map<String, dynamic>> streamQuery(
    dynamic connection,
    String sql,
    List<dynamic> bindings,
  ) => Stream.fromFuture(
    db.rawSql(sql, bindings),
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

void main() {
  late KnexPostgres db;
  late _PgLiveSchemaClient live;

  final host = Platform.environment['PG_HOST'] ?? 'localhost';
  final port = int.parse(Platform.environment['PG_PORT'] ?? '5432');
  final database = Platform.environment['PG_DATABASE'] ?? 'knex_test';
  final username = Platform.environment['PG_USER'] ?? 'test';
  final password = Platform.environment['PG_PASSWORD'] ?? 'test';

  final suffix = DateTime.now().microsecondsSinceEpoch.toString();
  final sourceTable = 'schema_src_$suffix';
  final copiedTable = 'schema_copy_$suffix';
  final renamedTable = 'schema_renamed_$suffix';
  final view1 = 'schema_view_a_$suffix';
  final view2 = 'schema_view_b_$suffix';

  Future<void> cleanup() async {
    await db.rawSql('drop view if exists "$view2"');
    await db.rawSql('drop view if exists "$view1"');
    await db.rawSql('drop table if exists "$renamedTable"');
    await db.rawSql('drop table if exists "$copiedTable"');
    await db.rawSql('drop table if exists "$sourceTable"');
  }

  setUpAll(() async {
    db = await KnexPostgres.connect(
      host: host,
      port: port,
      database: database,
      username: username,
      password: password,
    );
    live = _PgLiveSchemaClient(db);
    await cleanup();
  });

  tearDownAll(() async {
    await cleanup();
    await db.close();
  });

  group('Postgres schema API integration parity', () {
    test('hasTable and hasColumn against real database', () async {
      await db.executeSchema((s) {
        s.createTable(sourceTable, (t) {
          t.increments('id');
          t.string('name').notNullable();
        });
      });

      expect(await live.schemaBuilder().hasTable(sourceTable), isTrue);
      expect(await live.schemaBuilder().hasColumn(sourceTable, 'name'), isTrue);
      expect(
        await live.schemaBuilder().hasColumn(sourceTable, 'missing_col'),
        isFalse,
      );
    });

    test('createTableLike with callback then renameTable', () async {
      await db.executeSchema((s) {
        s.createTableLike(copiedTable, sourceTable, (t) {
          t.string('nickname').nullable();
        });
      });

      await db.execute(
        db.queryBuilder().table(copiedTable).insert({
          'name': 'alpha',
          'nickname': 'a',
        }),
      );

      final rowsBeforeRename = await db.select(
        db.queryBuilder().from(copiedTable).select(['name', 'nickname']),
      );
      expect(rowsBeforeRename, hasLength(1));
      expect(rowsBeforeRename.first['nickname'], 'a');

      await db.executeSchema((s) {
        s.renameTable(copiedTable, renamedTable);
      });

      expect(await live.schemaBuilder().hasTable(renamedTable), isTrue);
    });

    test('createViewOrReplace, renameView, and dropViewIfExists', () async {
      await db.executeSchema((s) {
        s.createViewOrReplace(view1, 'select 1 as n');
        s.renameView(view1, view2);
      });

      final rows = await db.rawSql('select n from "$view2"');
      expect(rows, hasLength(1));
      expect(rows.first['n'], 1);

      await db.executeSchema((s) {
        s.dropViewIfExists(view2);
        s.dropViewIfExists(view2);
      });

      expect(() => db.rawSql('select n from "$view2"'), throwsA(anything));
    });

    test('dropTableIfExists is idempotent', () async {
      await db.executeSchema((s) {
        s.dropTableIfExists(sourceTable);
        s.dropTableIfExists(sourceTable);
      });

      expect(await live.schemaBuilder().hasTable(sourceTable), isFalse);
    });
  });
}
