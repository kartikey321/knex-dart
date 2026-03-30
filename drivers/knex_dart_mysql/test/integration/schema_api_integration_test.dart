@Tags(['mysql'])
library;

import 'package:universal_io/io.dart';
import 'package:knex_dart/knex_dart.dart';
import 'package:knex_dart_mysql/knex_dart_mysql.dart';
import 'package:test/test.dart';

class _MySqlLiveSchemaClient extends Client {
  final KnexMySQL db;

  _MySqlLiveSchemaClient(this.db)
    : super(KnexConfig(client: 'mysql2', connection: const {}));

  @override
  String get driverName => 'mysql2';

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
  String wrapIdentifierImpl(String value) => value == '*' ? value : '`$value`';

  @override
  String parameterPlaceholder(int index) => '?';

  @override
  String formatValue(value) => value.toString();
}

void main() {
  late KnexMySQL db;
  late _MySqlLiveSchemaClient live;

  final host = Platform.environment['MYSQL_HOST'] ?? 'localhost';
  final port = int.parse(Platform.environment['MYSQL_PORT'] ?? '3306');
  final user = Platform.environment['MYSQL_USER'] ?? 'test';
  final password = Platform.environment['MYSQL_PASSWORD'] ?? 'test';
  final database = Platform.environment['MYSQL_DATABASE'] ?? 'knex_test';

  final suffix = DateTime.now().microsecondsSinceEpoch.toString();
  final sourceTable = 'schema_src_$suffix';
  final copiedTable = 'schema_copy_$suffix';
  final renamedTable = 'schema_renamed_$suffix';
  final view1 = 'schema_view_a_$suffix';
  final view2 = 'schema_view_b_$suffix';

  Future<void> cleanup() async {
    await db.raw('DROP VIEW IF EXISTS `$view2`');
    await db.raw('DROP VIEW IF EXISTS `$view1`');
    await db.raw('DROP TABLE IF EXISTS `$renamedTable`');
    await db.raw('DROP TABLE IF EXISTS `$copiedTable`');
    await db.raw('DROP TABLE IF EXISTS `$sourceTable`');
  }

  setUpAll(() async {
    db = await KnexMySQL.connect(
      host: host,
      port: port,
      user: user,
      password: password,
      database: database,
    );
    live = _MySqlLiveSchemaClient(db);
    await cleanup();
  });

  tearDownAll(() async {
    await cleanup();
    await db.close();
  });

  group('MySQL schema API integration parity', () {
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

      final rows = await db.raw('select n from `$view2`');
      expect(rows, hasLength(1));
      expect(rows.first['n'], 1);

      await db.executeSchema((s) {
        s.dropViewIfExists(view2);
        s.dropViewIfExists(view2);
      });

      expect(() => db.raw('select n from `$view2`'), throwsA(anything));
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
