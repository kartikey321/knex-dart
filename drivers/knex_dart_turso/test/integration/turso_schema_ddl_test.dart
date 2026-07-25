/// Live-execution verification for the schema-DDL parity fixes against a
/// real sqld (libSQL/Turso-compatible) server.
///
/// The differential parity harness (packages/knex_dart/test/parity/
/// schema_parity_test.dart) proved these fixes match knex.js's *text*, but
/// text matching isn't proof the SQL actually executes — this file runs the
/// exact SQL knex-dart now generates against a live SQLite-family engine.
///
/// Motivation: turso/d1 previously fell through to Postgres-shaped DDL
/// (`alter table ... add/drop constraint ...`, `serial`, etc.) for almost
/// every schema operation, because most dialect-dispatch checks in
/// schema_compiler.dart tested `driverName == 'sqlite' || 'sqlite3'`
/// literally instead of the family-aware `_isSqliteLike()` helper. These
/// tests would have failed outright against real sqld before that fix.
///
/// Requires sqld running locally:
///   docker compose up sqld -d
@Tags(['turso'])
library;

import 'package:universal_io/io.dart';

import 'package:knex_dart_turso/knex_dart_turso.dart';
import 'package:test/test.dart';

String get _url =>
    Platform.environment['TURSO_URL'] ?? 'http://127.0.0.1:18080';
String? get _token => Platform.environment['TURSO_AUTH_TOKEN'];

Future<KnexTurso?> _tryOpen() async {
  try {
    final client = KnexTurso(url: _url, authToken: _token ?? '');
    await client.executeRaw('SELECT 1');
    return client;
  } catch (e) {
    return null;
  }
}

void main() {
  KnexTurso? db;
  String? skipReason;

  setUpAll(() async {
    final candidate = await _tryOpen();
    if (candidate == null) {
      skipReason =
          'sqld not reachable at $_url — start via `docker compose up sqld -d`';
      return;
    }
    candidate.close();
  });

  setUp(() async {
    if (skipReason != null) return;
    db = KnexTurso(url: _url, authToken: _token ?? '');
    await db!.executeSchema((schema) {
      schema.dropTableIfExists('orders');
      schema.dropTableIfExists('users');
      schema.dropTableIfExists('memberships');
    });
  });

  tearDown(() async {
    db?.close();
    db = null;
  });

  group('Turso (sqld) — schema DDL fixes execute for real', () {
    test(
      'column-level .references().inTable() FK folds inline and is enforced',
      () async {
        if (skipReason != null) return markTestSkipped(skipReason!);

        await db!.executeSchema((schema) {
          schema.createTable('users', (t) {
            t.increments('id');
            t.string('name');
          });
          schema.createTable('orders', (t) {
            t.increments('id');
            t.integer('user_id').references('id').inTable('users');
          });
        });

        // The FK actually being enforced (not just present as dead syntax)
        // is what proves the inline fold produced real SQLite FK syntax,
        // not just something that merely parses.
        await db!.executeRaw('PRAGMA foreign_keys = ON');
        await db!.execute(
          db!.queryBuilder().table('users').insert({'id': 1, 'name': 'Alice'}),
        );
        await db!.execute(
          db!.queryBuilder().table('orders').insert({'id': 1, 'user_id': 1}),
        );

        Object? fkError;
        try {
          await db!.execute(
            db!.queryBuilder().table('orders').insert({
              'id': 2,
              'user_id': 999, // no such user — must violate the FK
            }),
          );
        } catch (e) {
          fkError = e;
        }
        expect(
          fkError,
          isNotNull,
          reason: 'FK was not actually enforced — inline fold produced '
              'syntax that parsed but did not create a real constraint',
        );
      },
    );

    test(
      'fluent table.foreign().onDelete(cascade) folds inline and cascades',
      () async {
        if (skipReason != null) return markTestSkipped(skipReason!);

        await db!.executeSchema((schema) {
          schema.createTable('users', (t) {
            t.increments('id');
            t.string('name');
          });
          schema.createTable('orders', (t) {
            t.increments('id');
            t.integer('user_id');
            t.foreign('user_id').references('id').inTable('users').onDelete('cascade');
          });
        });

        await db!.executeRaw('PRAGMA foreign_keys = ON');
        await db!.execute(
          db!.queryBuilder().table('users').insert({'id': 1, 'name': 'Alice'}),
        );
        await db!.execute(
          db!.queryBuilder().table('orders').insert({'id': 1, 'user_id': 1}),
        );

        await db!.execute(
          db!.queryBuilder().table('users').where('id', 1).delete(),
        );

        final remaining = await db!.select(
          db!.queryBuilder().from('orders'),
        );
        expect(
          remaining,
          isEmpty,
          reason: 'ON DELETE CASCADE did not fire — the inline-folded FK '
              'clause did not actually carry the cascade action',
        );
      },
    );

    test('composite primary key is enforced (duplicate insert rejected)', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.executeSchema((schema) {
        schema.createTable('memberships', (t) {
          t.integer('user_id');
          t.integer('org_id');
          t.primary(['user_id', 'org_id']);
        });
      });

      await db!.execute(
        db!.queryBuilder().table('memberships').insert({
          'user_id': 1,
          'org_id': 1,
        }),
      );

      Object? pkError;
      try {
        await db!.execute(
          db!.queryBuilder().table('memberships').insert({
            'user_id': 1,
            'org_id': 1,
          }),
        );
      } catch (e) {
        pkError = e;
      }
      expect(
        pkError,
        isNotNull,
        reason: 'duplicate composite primary key was accepted — PK was not '
            'actually created',
      );
    });

    test('alterTable().primary() refuses before touching the server', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.executeSchema((schema) {
        schema.createTable('memberships', (t) {
          t.integer('user_id');
          t.integer('org_id');
        });
      });

      expect(
        () => db!.executeSchema((schema) {
          schema.alterTable('memberships', (t) {
            t.primary(['user_id', 'org_id']);
          });
        }),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('dropPrimary()/dropForeign() refuse before touching the server', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.executeSchema((schema) {
        schema.createTable('orders', (t) {
          t.increments('id');
        });
      });

      expect(
        () => db!.executeSchema((schema) {
          schema.alterTable('orders', (t) => t.dropPrimary());
        }),
        throwsA(isA<UnsupportedError>()),
      );
      expect(
        () => db!.executeSchema((schema) {
          schema.alterTable('orders', (t) => t.dropForeign(['id']));
        }),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('dropUnique executes DROP INDEX (not ALTER ... DROP CONSTRAINT)', () async {
      if (skipReason != null) return markTestSkipped(skipReason!);

      await db!.executeSchema((schema) {
        schema.createTable('users', (t) {
          t.increments('id');
          t.string('email').unique();
        });
      });

      // Would throw a SQLite syntax/support error here before the fix,
      // since SQLite has no ALTER TABLE ... DROP CONSTRAINT.
      await db!.executeSchema((schema) {
        schema.alterTable('users', (t) => t.dropUnique(['email']));
      });

      // Constraint is actually gone: a duplicate email now succeeds.
      await db!.execute(
        db!.queryBuilder().table('users').insert({
          'id': 1,
          'email': 'a@b.com',
        }),
      );
      await db!.execute(
        db!.queryBuilder().table('users').insert({
          'id': 2,
          'email': 'a@b.com',
        }),
      );
      final rows = await db!.select(db!.queryBuilder().from('users'));
      expect(rows, hasLength(2));
    });
  });
}
