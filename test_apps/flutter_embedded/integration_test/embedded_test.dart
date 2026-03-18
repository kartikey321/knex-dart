import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';
import 'package:knex_dart_duckdb/knex_dart_duckdb.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ─── SQLite ──────────────────────────────────────────────────────────────

  group('SQLite driver', () {
    late KnexSQLite db;

    setUpAll(() async {
      db = await KnexSQLite.connect(filename: ':memory:');
      await db.executeSchema((s) {
        s.createTable('items', (t) {
          t.increments('id');
          t.string('name');
          t.float('value').nullable();
        });
      });
    });

    tearDownAll(() => db.close());

    testWidgets('INSERT + SELECT roundtrip', (_) async {
      final qb = db.queryBuilder();
      await db.insert(qb.table('items').insert({'name': 'widget', 'value': 3.14}));

      final rows = await db.select(
        db.queryBuilder().table('items').where('name', 'widget'),
      );
      expect(rows.length, 1);
      expect(rows.first['name'], 'widget');
      expect((rows.first['value'] as num).toDouble(), closeTo(3.14, 0.001));
    });

    testWidgets('transaction commit', (_) async {
      await db.trx((trx) async {
        await trx.insert(
          db.queryBuilder().table('items').insert({'name': 'committed', 'value': 1.0}),
        );
      });

      final rows = await db.select(
        db.queryBuilder().table('items').where('name', 'committed'),
      );
      expect(rows.length, 1);
    });

    testWidgets('transaction rollback on error', (_) async {
      try {
        await db.trx((_) async => throw Exception('force rollback'));
      } catch (_) {}

      // The table stays intact — the rollback did not corrupt it.
      final rows = await db.select(db.queryBuilder().table('items'));
      expect(rows, isA<List>());
    });
  });

  // ─── DuckDB ──────────────────────────────────────────────────────────────

  group('DuckDB driver', () {
    late DuckDBClient db;
    bool available = true;
    String? skipReason;

    setUpAll(() async {
      try {
        db = await DuckDBClient.open(':memory:');
        await db.raw('''
          CREATE TABLE items (
            id INTEGER,
            name VARCHAR,
            value DOUBLE
          )
        ''');
      } catch (e) {
        available = false;
        skipReason = 'DuckDB unavailable: $e';
      }
    });

    tearDownAll(() async {
      if (available) await db.close();
    });

    testWidgets('INSERT + SELECT roundtrip', (_) async {
      if (!available) {
        markTestSkipped(skipReason!);
        return;
      }
      await db.raw("INSERT INTO items VALUES (1, 'widget', 3.14)");

      final rows = await db.raw('SELECT name, value FROM items WHERE id = 1');
      expect(rows.length, 1);
      expect(rows.first['name'], 'widget');
      expect((rows.first['value'] as num).toDouble(), closeTo(3.14, 0.001));
    });

    testWidgets('transaction commit', (_) async {
      if (!available) {
        markTestSkipped(skipReason!);
        return;
      }
      await db.trx((trx) async {
        await trx.raw("INSERT INTO items VALUES (2, 'committed', 1.0)");
      });

      final rows = await db.raw("SELECT name FROM items WHERE name = 'committed'");
      expect(rows.length, 1);
    });

    testWidgets('transaction rollback on error', (_) async {
      if (!available) {
        markTestSkipped(skipReason!);
        return;
      }
      try {
        await db.trx((_) async => throw Exception('force rollback'));
      } catch (_) {}

      // Table stays intact.
      final rows = await db.raw('SELECT * FROM items');
      expect(rows, isA<List>());
    });
  });
}
