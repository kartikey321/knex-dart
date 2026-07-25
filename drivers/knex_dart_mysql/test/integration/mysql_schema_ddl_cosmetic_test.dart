/// Live-execution verification that the "cosmetic MySQL syntax" divergences
/// documented in the schema-DDL parity harness's allowlist
/// (packages/knex_dart/test/parity/schema_parity_test.dart) are genuinely
/// equivalent, valid MySQL — not just plausible-looking SQL that happens to
/// parse differently from knex.js. Text comparison against knex.js proves
/// the two sides differ; it can't prove both sides are actually correct.
/// This runs knex-dart's exact generated SQL against a real MySQL server.
@Tags(['mysql'])
library;

import 'package:universal_io/io.dart';
import 'package:knex_dart_mysql/knex_dart_mysql.dart';
import 'package:test/test.dart';

void main() {
  late KnexMySQL db;

  final host = Platform.environment['MYSQL_HOST'] ?? 'localhost';
  final port = int.parse(Platform.environment['MYSQL_PORT'] ?? '3306');
  final user = Platform.environment['MYSQL_USER'] ?? 'knex';
  final password = Platform.environment['MYSQL_PASSWORD'] ?? 'knex';
  final database = Platform.environment['MYSQL_DATABASE'] ?? 'knex_test';

  final suffix = DateTime.now().microsecondsSinceEpoch.toString();
  final usersTable = 'cosmetic_users_$suffix';

  Future<void> cleanup() async {
    await db.raw('DROP TABLE IF EXISTS `$usersTable`');
  }

  setUpAll(() async {
    db = await KnexMySQL.connect(
      host: host,
      port: port,
      user: user,
      password: password,
      database: database,
    );
    await cleanup();
  });

  tearDownAll(() async {
    await cleanup();
    await db.close();
  });

  group('MySQL cosmetic-syntax allowlist entries execute for real', () {
    test('ADD COLUMN, DROP COLUMN, RENAME COLUMN all execute', () async {
      await db.executeSchema((s) {
        s.createTable(usersTable, (t) {
          t.increments('id');
          t.string('email');
        });
      });

      // alter-table-add-column::mysql: `alter table t add col ...`
      await db.executeSchema((s) {
        s.alterTable(usersTable, (t) => t.string('nickname'));
      });
      expect(await db.raw("SHOW COLUMNS FROM `$usersTable` LIKE 'nickname'"), hasLength(1));

      // alter-table-rename-column::mysql: modern RENAME COLUMN
      await db.executeSchema((s) {
        s.alterTable(usersTable, (t) => t.renameColumn('nickname', 'nick'));
      });
      expect(await db.raw("SHOW COLUMNS FROM `$usersTable` LIKE 'nick'"), hasLength(1));

      // alter-table-drop-column::mysql: `alter table t drop col`
      await db.executeSchema((s) {
        s.alterTable(usersTable, (t) => t.dropColumn('nick'));
      });
      expect(await db.raw("SHOW COLUMNS FROM `$usersTable` LIKE 'nick'"), isEmpty);
    });

    test('unique constraint: ADD CONSTRAINT ... UNIQUE actually enforces uniqueness', () async {
      await db.executeSchema((s) {
        s.alterTable(usersTable, (t) => t.unique(['email'], 'uq_cosmetic_email'));
      });

      await db.execute(
        db.queryBuilder().table(usersTable).insert({
          'id': 1,
          'email': 'a@b.com',
        }),
      );

      Object? uniqueError;
      try {
        await db.execute(
          db.queryBuilder().table(usersTable).insert({
            'id': 2,
            'email': 'a@b.com',
          }),
        );
      } catch (e) {
        uniqueError = e;
      }
      expect(
        uniqueError,
        isNotNull,
        reason: '`ADD CONSTRAINT name UNIQUE (col)` did not actually create '
            'a unique constraint',
      );
    });

    test('add index / drop index (CREATE INDEX form) both execute', () async {
      // alter-table-add-index::mysql: `create index ...` (vs knex.js's
      // `alter table t add index name(cols)`)
      await db.executeSchema((s) {
        s.alterTable(usersTable, (t) => t.index(['email'], 'idx_cosmetic_email'));
      });
      final indexes = await db.raw('SHOW INDEX FROM `$usersTable` WHERE Key_name = ?', [
        'idx_cosmetic_email',
      ]);
      expect(indexes, isNotEmpty);

      // alter-table-drop-index::mysql: `drop index name on t` (vs knex.js's
      // `alter table t drop index name`)
      await db.executeSchema((s) {
        s.alterTable(usersTable, (t) => t.dropIndex(['email'], 'idx_cosmetic_email'));
      });
      final afterDrop = await db.raw('SHOW INDEX FROM `$usersTable` WHERE Key_name = ?', [
        'idx_cosmetic_email',
      ]);
      expect(afterDrop, isEmpty);
    });

    test('dropUnique (ALTER ... DROP INDEX form) removes the constraint', () async {
      // Reuses the constraint the previous test created (uq_cosmetic_email)
      // rather than adding a second one on the same column — MySQL allows
      // multiple unique indexes on one column, so a second one would mask
      // whether dropping the first actually freed anything.
      await db.executeSchema((s) {
        s.alterTable(usersTable, (t) => t.dropUnique(['email'], 'uq_cosmetic_email'));
      });

      // Constraint is actually gone: duplicate email now succeeds.
      await db.execute(
        db.queryBuilder().table(usersTable).insert({
          'id': 3,
          'email': 'a@b.com', // already used by id=1 above
        }),
      );
      final rows = await db.select(
        db.queryBuilder().from(usersTable).where('email', 'a@b.com'),
      );
      expect(rows.length, greaterThanOrEqualTo(2));
    });

    test('primary key: ADD CONSTRAINT name PRIMARY KEY (cols) form executes', () async {
      final pkTable = 'cosmetic_pk_$suffix';
      await db.executeSchema((s) {
        s.createTable(pkTable, (t) {
          t.integer('a_id');
          t.integer('b_id');
        });
        s.alterTable(pkTable, (t) => t.primary(['a_id', 'b_id'], 'cosmetic_pk'));
      });

      await db.execute(
        db.queryBuilder().table(pkTable).insert({'a_id': 1, 'b_id': 1}),
      );
      Object? pkError;
      try {
        await db.execute(
          db.queryBuilder().table(pkTable).insert({'a_id': 1, 'b_id': 1}),
        );
      } catch (e) {
        pkError = e;
      }
      expect(pkError, isNotNull, reason: 'duplicate composite PK was accepted');

      await db.raw('DROP TABLE IF EXISTS `$pkTable`');
    });
  });
}
