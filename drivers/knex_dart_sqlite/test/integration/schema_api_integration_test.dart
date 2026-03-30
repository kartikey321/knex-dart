import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';
import 'package:test/test.dart';
import 'package:universal_io/io.dart';

void main() {
  group('SQLite schema API integration parity', () {
    SQLiteClient? db;

    final suffix = DateTime.now().microsecondsSinceEpoch.toString();
    final sourceTable = 'schema_src_$suffix';
    final copiedTable = 'schema_copy_$suffix';
    final renamedTable = 'schema_renamed_$suffix';
    final view1 = 'schema_view_a_$suffix';
    final view2 = 'schema_view_b_$suffix';

    final filename = Platform.environment['SQLITE_DB'] ?? ':memory:';

    setUp(() async {
      db = await SQLiteClient.connect(filename: filename);
      await db!.schemaBuilder().createTable(sourceTable, (t) {
        t.increments('id');
        t.string('name').notNullable();
      }).execute();
    });

    tearDown(() async {
      await db?.close();
      db = null;
    });

    test('hasTable and hasColumn against real database', () async {
      expect(await db!.schemaBuilder().hasTable(sourceTable), isTrue);
      expect(await db!.schemaBuilder().hasColumn(sourceTable, 'name'), isTrue);
      expect(
        await db!.schemaBuilder().hasColumn(sourceTable, 'missing_col'),
        isFalse,
      );
    });

    test('createTableLike with callback then renameTable', () async {
      await db!.schemaBuilder().createTableLike(copiedTable, sourceTable, (t) {
        t.string('nickname').nullable();
      }).execute();

      await db!.execute(
        db!.queryBuilder().table(copiedTable).insert({
          'name': 'alpha',
          'nickname': 'a',
        }),
      );

      final rowsBeforeRename = await db!.select(
        db!.queryBuilder().from(copiedTable).select(['name', 'nickname']),
      );
      expect(rowsBeforeRename, hasLength(1));
      expect(rowsBeforeRename.first['nickname'], 'a');

      await db!
          .schemaBuilder()
          .renameTable(copiedTable, renamedTable)
          .execute();
      expect(await db!.schemaBuilder().hasTable(renamedTable), isTrue);
    });

    test('createViewOrReplace and dropViewIfExists', () async {
      await db!
          .schemaBuilder()
          .createViewOrReplace(view1, 'select 1 as n')
          .execute();
      final rows1 = await db!.raw('select n from "$view1"').execute();
      expect(rows1, hasLength(1));
      expect(rows1.first['n'], 1);

      await db!
          .schemaBuilder()
          .createViewOrReplace(view1, 'select 2 as n')
          .execute();
      final rows2 = await db!.raw('select n from "$view1"').execute();
      expect(rows2.first['n'], 2);

      await db!
          .schemaBuilder()
          .renameTable(sourceTable, renamedTable)
          .dropViewIfExists(view1)
          .dropViewIfExists(view1)
          .execute();

      expect(await db!.schemaBuilder().hasTable(renamedTable), isTrue);
    });

    test('renameView is unsupported on sqlite', () async {
      await db!.schemaBuilder().createView(view1, 'select 1 as n').execute();

      expect(
        () => db!.schemaBuilder().renameView(view1, view2).toSQL(),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('dropTableIfExists is idempotent', () async {
      await db!
          .schemaBuilder()
          .dropTableIfExists(sourceTable)
          .dropTableIfExists(sourceTable)
          .execute();

      expect(await db!.schemaBuilder().hasTable(sourceTable), isFalse);
    });
  });
}
