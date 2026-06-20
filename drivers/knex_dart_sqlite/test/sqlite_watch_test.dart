import 'dart:async';

import 'package:knex_dart/knex_dart.dart';
import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';
import 'package:test/test.dart';

/// Waits until [events] contains at least [n] items, or times out.
Future<void> waitFor(List<Object?> events, int n) =>
    Future.doWhile(() async {
      if (events.length >= n) return false;
      await Future.delayed(Duration(milliseconds: 5));
      return true;
    }).timeout(Duration(seconds: 2));

void main() {
  group('KnexSQLite watch()', () {
    late KnexSQLite db;

    setUp(() async {
      db = await KnexSQLite.connect(filename: ':memory:');
      await db.executeSchema((s) {
        s.createTable('items', (t) {
          t.increments('id');
          t.string('name').notNullable();
        });
        s.createTable('tags', (t) {
          t.increments('id');
          t.string('label').notNullable();
        });
      });
    });

    tearDown(() => db.close());

    test('implements WatchableClient', () {
      expect(db, isA<WatchableClient>());
    });

    test('emits initial result immediately on subscribe', () async {
      await db.insert(db('items').insert({'name': 'alpha'}));

      final first = await db.watch(db('items')).first;
      expect(first, hasLength(1));
      expect(first.first['name'], 'alpha');
    });

    test('re-emits after insert', () async {
      final events = <List<Map<String, dynamic>>>[];
      final sub = db.watch(db('items')).listen(events.add);

      await waitFor(events, 1); // wait for initial emit
      await db.insert(db('items').insert({'name': 'beta'}));
      await waitFor(events, 2);

      expect(events.last, hasLength(1));
      expect(events.last.first['name'], 'beta');
      await sub.cancel();
    });

    test('re-emits after update', () async {
      await db.insert(db('items').insert({'name': 'old'}));

      final events = <List<Map<String, dynamic>>>[];
      final sub = db.watch(db('items')).listen(events.add);

      await waitFor(events, 1);
      await db.update(
        db('items').where('name', 'old').update({'name': 'new'}),
      );
      await waitFor(events, 2);

      expect(events.last.first['name'], 'new');
      await sub.cancel();
    });

    test('re-emits after delete', () async {
      await db.insert(db('items').insert({'name': 'gone'}));

      final events = <List<Map<String, dynamic>>>[];
      final sub = db.watch(db('items')).listen(events.add);

      await waitFor(events, 1);
      await db.delete(db('items').where('name', 'gone').delete());
      await waitFor(events, 2);

      expect(events.last, isEmpty);
      await sub.cancel();
    });

    test('does not re-emit for unrelated table writes', () async {
      final events = <List<Map<String, dynamic>>>[];
      final sub = db.watch(db('items')).listen(events.add);

      await waitFor(events, 1); // initial emit landed
      final countAfterInit = events.length;

      await db.insert(db('tags').insert({'label': 'unrelated'}));
      await Future.delayed(Duration(milliseconds: 30));

      expect(events.length, countAfterInit); // no new emit
      await sub.cancel();
    });

    test('cancelling the subscription stops re-emits', () async {
      final events = <List<Map<String, dynamic>>>[];
      final sub = db.watch(db('items')).listen(events.add);

      await waitFor(events, 1);
      await sub.cancel();
      final countAfterCancel = events.length;

      await db.insert(db('items').insert({'name': 'after-cancel'}));
      await Future.delayed(Duration(milliseconds: 30));

      expect(events.length, countAfterCancel);
    });

    test('re-emits when a joined table changes', () async {
      await db.executeSchema((s) {
        s.createTable('orders', (t) {
          t.increments('id');
          t.integer('item_id').notNullable();
          t.integer('qty').notNullable();
        });
      });

      await db.insert(db('items').insert({'name': 'widget'}));
      final itemId = (await db.select(db('items')))[0]['id'] as int;

      final joinQuery = db('items').join(
        'orders',
        (j) => j.on('items.id', 'orders.item_id'),
      );

      final events = <List<Map<String, dynamic>>>[];
      final sub = db.watch(joinQuery).listen(events.add);

      await waitFor(events, 1); // initial emit (empty — no orders yet)

      // Write to the joined table — should trigger re-emit.
      await db.insert(
        db('orders').insert({'item_id': itemId, 'qty': 5}),
      );
      await waitFor(events, 2);

      expect(events.last, hasLength(1));
      expect(events.last.first['qty'], 5);
      await sub.cancel();
    });

    test('throws StateError when called on a closed database', () async {
      await db.close();
      expect(
        () => db.watch(db('items')),
        throwsA(isA<StateError>()),
      );
    });

    test('multiple concurrent watch() streams on the same table are independent',
        () async {
      final eventsA = <List<Map<String, dynamic>>>[];
      final eventsB = <List<Map<String, dynamic>>>[];

      final subA = db.watch(db('items')).listen(eventsA.add);
      final subB = db.watch(db('items')).listen(eventsB.add);

      await waitFor(eventsA, 1);
      await waitFor(eventsB, 1);

      await db.insert(db('items').insert({'name': 'shared'}));
      await waitFor(eventsA, 2);
      await waitFor(eventsB, 2);

      expect(eventsA.last, hasLength(1));
      expect(eventsB.last, hasLength(1));
      await subA.cancel();
      await subB.cancel();
    });

    test('rawSql write triggers re-emit', () async {
      final events = <List<Map<String, dynamic>>>[];
      final sub = db.watch(db('items')).listen(events.add);

      await waitFor(events, 1);
      await db.rawSql("INSERT INTO \"items\" (\"name\") VALUES (?)", ['raw']);
      await waitFor(events, 2);

      expect(events.last.first['name'], 'raw');
      await sub.cancel();
    });

    test('DDL via executeSchema does not trigger re-emit', () async {
      final events = <List<Map<String, dynamic>>>[];
      final sub = db.watch(db('items')).listen(events.add);

      await waitFor(events, 1);
      final countAfterInit = events.length;

      await db.executeSchema((s) {
        s.createTable('unrelated_ddl', (t) => t.increments('id'));
      });
      await Future.delayed(Duration(milliseconds: 30));

      expect(events.length, countAfterInit);
      await sub.cancel();
    });

    test('select() error inside emit propagates as stream error', () async {
      final errors = <Object>[];
      // Watch a table that doesn't exist — initial emit should error.
      final sub = db
          .watch(db('nonexistent_table'))
          .listen((_) {}, onError: errors.add);

      await Future.delayed(Duration(milliseconds: 50));
      expect(errors, isNotEmpty);
      await sub.cancel();
    });

    test('second listen() on same watch stream throws StateError', () async {
      final stream = db.watch(db('items'));
      final sub = stream.listen((_) {});
      expect(() => stream.listen((_) {}), throwsStateError);
      await sub.cancel();
    });

    group('transaction safety', () {
      test('committed transaction triggers re-emit', () async {
        final events = <List<Map<String, dynamic>>>[];
        final sub = db.watch(db('items')).listen(events.add);

        await waitFor(events, 1);
        await db.trx((trx) async {
          await trx.insert(db('items').insert({'name': 'committed'}));
        });
        await waitFor(events, 2);

        expect(events.last.first['name'], 'committed');
        await sub.cancel();
      });

      test('rolled-back transaction does not trigger re-emit', () async {
        final events = <List<Map<String, dynamic>>>[];
        final sub = db.watch(db('items')).listen(events.add);

        await waitFor(events, 1);
        final countAfterInit = events.length;

        try {
          await db.trx((trx) async {
            await trx.insert(db('items').insert({'name': 'phantom'}));
            throw Exception('rollback');
          });
        } catch (_) {}
        await Future.delayed(Duration(milliseconds: 30));

        expect(events.length, countAfterInit); // no re-emit for rolled-back write
        final rows = await db.select(db('items'));
        expect(rows.any((r) => r['name'] == 'phantom'), isFalse);
        await sub.cancel();
      });

      test('savepoint rollback does not pollute outer commit re-emit', () async {
        final events = <List<Map<String, dynamic>>>[];
        final sub = db.watch(db('items')).listen(events.add);

        await waitFor(events, 1);

        await db.trx((outer) async {
          await outer.insert(db('items').insert({'name': 'outer'}));
          // Inner savepoint rolls back — its write should not appear.
          try {
            await outer.trx((inner) async {
              await inner.insert(db('items').insert({'name': 'inner-phantom'}));
              throw Exception('savepoint rollback');
            });
          } catch (_) {}
        });
        await waitFor(events, 2);

        final names = events.last.map((r) => r['name']).toList();
        expect(names, contains('outer'));
        expect(names, isNot(contains('inner-phantom')));
        await sub.cancel();
      });
    });

    group('debounce / maxPendingWrites', () {
      test('debounce collapses rapid writes into one re-emit', () async {
        final events = <List<Map<String, dynamic>>>[];
        final sub = db
            .watch(db('items'), debounce: Duration(milliseconds: 80))
            .listen(events.add);

        await waitFor(events, 1); // wait for initial emit
        final countAfterInit = events.length;

        // Five sequential inserts — all complete well within the 80ms window.
        for (var i = 0; i < 5; i++) {
          await db.insert(db('items').insert({'name': 'item$i'}));
        }
        // Wait for debounce window + query round-trip.
        await Future.delayed(Duration(milliseconds: 200));

        expect(events.length, countAfterInit + 1);
        expect(events.last, hasLength(5));
        await sub.cancel();
      });

      test('maxPendingWrites triggers re-emit before debounce window', () async {
        final events = <List<Map<String, dynamic>>>[];
        final sub = db
            .watch(
              db('items'),
              debounce: Duration(seconds: 10), // very long window
              maxPendingWrites: 3,
            )
            .listen(events.add);

        await waitFor(events, 1); // wait for initial emit
        final countAfterInit = events.length;

        // Insert 3 rows — should hit the count ceiling before the 10s timer.
        for (var i = 0; i < 3; i++) {
          await db.insert(db('items').insert({'name': 'item$i'}));
        }
        await waitFor(events, countAfterInit + 1);

        expect(events.length, countAfterInit + 1);
        expect(events.last, hasLength(3));
        await sub.cancel();
      });
    });
  });
}
