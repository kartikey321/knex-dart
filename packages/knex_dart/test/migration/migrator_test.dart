import 'dart:async';
import 'dart:io';

import 'package:knex_dart/knex_dart.dart';
import 'package:test/test.dart';

import '../mocks/mock_client.dart';

void main() {
  group('Migrator', () {
    test(
      'latest applies pending SQL migrations once and tracks status',
      () async {
        final client = _MigrationTestClient();
        final knex = Knex(client);
        final migrator = knex.migrator(
          migrations: const [
            SqlMigration(
              name: '001_create_users',
              upSql: ['create table users (id integer primary key)'],
              downSql: ['drop table users'],
            ),
            SqlMigration(
              name: '002_seed_users',
              upSql: ['insert into users (id) values (1)'],
              downSql: ['delete from users where id = 1'],
            ),
          ],
        );

        await migrator.latest();
        await migrator.latest(); // idempotent

        final status = await migrator.status();
        expect(status.length, 2);
        expect(status[0]['name'], '001_create_users');
        expect(status[0]['status'], 'completed');
        expect(status[1]['name'], '002_seed_users');
        expect(status[1]['status'], 'completed');

        expect(client.executedAppSql, [
          'create table users (id integer primary key)',
          'insert into users (id) values (1)',
        ]);
      },
    );

    test('rollback reverts latest batch only', () async {
      final client = _MigrationTestClient();
      final knex = Knex(client);

      const m1 = SqlMigration(
        name: '001_create_users',
        upSql: ['create table users (id integer primary key)'],
        downSql: ['drop table users'],
      );
      const m2 = SqlMigration(
        name: '002_add_accounts',
        upSql: ['create table accounts (id integer primary key)'],
        downSql: ['drop table accounts'],
      );

      await knex.migrator(migrations: const [m1]).latest();
      await knex.migrator(migrations: const [m1, m2]).latest();
      await knex.migrator(migrations: const [m1, m2]).rollback();

      expect(client.appliedNames, ['001_create_users']);
      expect(client.executedAppSql.last, 'drop table accounts');
    });

    test('rollback fails clearly when migration has no downSql', () async {
      final client = _MigrationTestClient();
      final knex = Knex(client);
      final migrator = knex.migrator(
        migrations: const [
          SqlMigration(
            name: '001_non_reversible',
            upSql: ['create table t1 (id integer)'],
          ),
        ],
      );

      await migrator.latest();

      await expectLater(
        migrator.rollback,
        throwsA(
          isA<KnexMigrationException>().having(
            (e) => e.message,
            'message',
            contains('failed during down'),
          ),
        ),
      );
    });

    test('schema AST migration can migrate up and down', () async {
      final client = _MigrationTestClient();
      final knex = Knex(client);
      final ast = KnexSchemaAst(
        tables: const [
          KnexTableAst(
            name: 'users',
            columns: [
              KnexColumnAst(
                name: 'id',
                type: KnexColumnType.increments,
                nullable: false,
                primary: true,
              ),
              KnexColumnAst(
                name: 'email',
                type: KnexColumnType.string,
                nullable: false,
                unique: true,
              ),
            ],
          ),
        ],
      );

      final migrator = knex.migrator(
        migrations: [
          SchemaAstMigration(
            name: '001_schema_bootstrap',
            schema: ast,
            ifNotExists: true,
            dropOnDown: true,
          ),
        ],
      );

      await migrator.latest();
      await migrator.rollback();

      final sqlLower = client.executedAppSql
          .map((s) => s.toLowerCase())
          .toList();
      expect(
        sqlLower.any((s) => s.contains('create table if not exists')),
        isTrue,
      );
      expect(sqlLower.any((s) => s.contains('drop table if exists')), isTrue);
    });

    test('latest loads and executes migrations from sources', () async {
      final client = _MigrationTestClient();
      final knex = Knex(client);
      final migrator = knex.migrator(
        sources: [
          CodeMigrationSource(const [
            SqlMigration(
              name: '010_from_source',
              upSql: ['create table source_table (id integer primary key)'],
              downSql: ['drop table source_table'],
            ),
          ]),
        ],
      );

      await migrator.latest();
      final status = await migrator.status();
      expect(status.single['name'], '010_from_source');
      expect(status.single['status'], 'completed');
      expect(
        client.executedAppSql,
        contains('create table source_table (id integer primary key)'),
      );
    });

    test(
      'throws on duplicate migration names across migrations and sources',
      () async {
        final client = _MigrationTestClient();
        final knex = Knex(client);
        final migrator = knex.migrator(
          migrations: const [
            SqlMigration(
              name: '001_dup',
              upSql: ['select 1'],
              downSql: ['select 1'],
            ),
          ],
          sources: [
            CodeMigrationSource(const [
              SqlMigration(
                name: '001_dup',
                upSql: ['select 1'],
                downSql: ['select 1'],
              ),
            ]),
          ],
        );

        await expectLater(
          migrator.latest,
          throwsA(
            isA<KnexMigrationException>().having(
              (e) => e.message,
              'message',
              contains('Duplicate migration name'),
            ),
          ),
        );
      },
    );

    test('fromCode applies units through explicit code entrypoint', () async {
      final client = _MigrationTestClient();
      final knex = Knex(client);

      final migrator = knex.migrate.fromCode(const [
        SqlMigration(
          name: '100_from_code',
          upSql: ['create table code_entry (id integer primary key)'],
          downSql: ['drop table code_entry'],
        ),
      ]);

      await migrator.latest();
      expect(
        client.executedAppSql,
        contains('create table code_entry (id integer primary key)'),
      );
    });

    test('fromSqlDir loads and applies SQL files from directory', () async {
      final client = _MigrationTestClient();
      final knex = Knex(client);
      final dir = await Directory.systemTemp.createTemp('knex_migrator_dir_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      await File(
        '${dir.path}/200_from_dir.up.sql',
      ).writeAsString('create table dir_entry (id integer primary key)');
      await File(
        '${dir.path}/200_from_dir.down.sql',
      ).writeAsString('drop table dir_entry');

      await knex.migrate.fromSqlDir(dir.path).latest();
      expect(
        client.executedAppSql,
        contains('create table dir_entry (id integer primary key)'),
      );
    });

    test(
      'fromSchema converts external schema input and applies migration',
      () async {
        final client = _MigrationTestClient();
        final knex = Knex(client);
        final jsonSchema = <String, dynamic>{
          r'$schema': 'https://json-schema.org/draft/2020-12/schema',
          'title': 'schema_entry',
          'type': 'object',
          'properties': {
            'id': {'type': 'integer'},
            'email': {'type': 'string'},
          },
        };

        final migrator = knex.migrate.fromSchema(
          name: '300_from_schema',
          input: jsonSchema,
          adapter: JsonSchemaAdapter(),
          ifNotExists: true,
        );

        await migrator.latest();
        final lower = client.executedAppSql
            .map((e) => e.toLowerCase())
            .toList();
        expect(
          lower.any((sql) => sql.contains('create table if not exists')),
          isTrue,
        );
        expect(lower.any((sql) => sql.contains('schema_entry')), isTrue);
      },
    );

    test(
      'fromSchema auto-registers JsonSchemaAdapter when no adapter provided',
      () async {
        final client = _MigrationTestClient();
        final knex = Knex(client);
        // No explicit adapter: JsonSchemaAdapter should be auto-registered.
        final migrator = knex.migrate.fromSchema(
          name: '301_auto_adapter',
          input: {
            r'$schema': 'https://json-schema.org/draft/2020-12/schema',
            'title': 'auto_table',
            'type': 'object',
            'properties': {
              'id': <String, dynamic>{'type': 'integer'},
            },
          },
          ifNotExists: true,
        );

        await migrator.latest();
        final lower = client.executedAppSql
            .map((s) => s.toLowerCase())
            .toList();
        expect(
          lower.any((s) => s.contains('auto_table')),
          isTrue,
          reason: 'Table name from JSON Schema title should appear in DDL',
        );
      },
    );

    test('fromConfig uses MigrationConfig.directory as SQL source', () async {
      final dir = await Directory.systemTemp.createTemp('knex_fromconfig_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      await File(
        '${dir.path}/400_cfg.up.sql',
      ).writeAsString('create table cfg_table (id integer primary key)');
      await File(
        '${dir.path}/400_cfg.down.sql',
      ).writeAsString('drop table cfg_table');

      // Create client with MigrationConfig.directory pointing at temp dir.
      final client = _MigrationTestClient(
        config: KnexConfig(
          client: 'mock',
          connection: {},
          migrations: MigrationConfig(directory: dir.path),
        ),
      );
      final knex = Knex(client);

      await knex.migrate.fromConfig().latest();
      expect(
        client.executedAppSql,
        contains('create table cfg_table (id integer primary key)'),
      );
    });
  });

  group('Migrator failure and concurrency scenarios', () {
    test('latest() with multiple pending migrations records only the ones '
        'that completed before a mid-batch failure, and stops', () async {
      final client = _MigrationTestClient();
      final knex = Knex(client);
      const m1 = SqlMigration(
        name: '001_ok',
        upSql: ['create table ok_table (id integer primary key)'],
        downSql: ['drop table ok_table'],
      );
      const m2 = _ThrowingUpMigration(name: '002_boom');
      const m3 = SqlMigration(
        name: '003_never_reached',
        upSql: ['create table never_table (id integer primary key)'],
        downSql: ['drop table never_table'],
      );
      final migrator = knex.migrator(migrations: const [m1, m2, m3]);

      await expectLater(
        migrator.latest,
        throwsA(
          isA<KnexMigrationException>()
              .having((e) => e.message, 'message', contains('002_boom'))
              .having(
                (e) => e.message,
                'message',
                contains('failed during up'),
              ),
        ),
      );

      // Only the migration that actually completed before the failure
      // should be recorded in the tracking table.
      expect(client.appliedNames, ['001_ok']);

      final status = await migrator.status();
      expect(status, [
        {'name': '001_ok', 'status': 'completed'},
        {'name': '002_boom', 'status': 'pending'},
        {'name': '003_never_reached', 'status': 'pending'},
      ]);

      // The migration after the failing one must never have run.
      expect(
        client.executedAppSql,
        contains('create table ok_table (id integer primary key)'),
      );
      expect(
        client.executedAppSql.any((s) => s.contains('never_table')),
        isFalse,
      );

      // A permanently-failing 002 keeps blocking everything after it:
      // 001 is skipped (already applied) and 003 still never runs. This
      // only proves the blocked state is stable — recovery once 002 is
      // fixed is covered by the next test.
      await expectLater(
        migrator.latest,
        throwsA(isA<KnexMigrationException>()),
      );
      expect(client.appliedNames, ['001_ok']);
    });

    test('latest() recovers after a failed migration is fixed: the retry '
        'applies the failed migration and everything after it', () async {
      final client = _MigrationTestClient();
      final knex = Knex(client);
      const m1 = SqlMigration(
        name: '001_ok',
        upSql: ['create table ok_table (id integer primary key)'],
        downSql: ['drop table ok_table'],
      );
      final m2 = _FailOnceUpMigration(name: '002_flaky');
      const m3 = SqlMigration(
        name: '003_after',
        upSql: ['create table after_table (id integer primary key)'],
        downSql: ['drop table after_table'],
      );
      final migrator = knex.migrator(migrations: [m1, m2, m3]);

      await expectLater(
        migrator.latest,
        throwsA(isA<KnexMigrationException>()),
      );
      expect(client.appliedNames, ['001_ok']);
      expect(
        client.executedAppSql.any((s) => s.contains('after_table')),
        isFalse,
      );

      // The "fix" ships: 002's up() now succeeds. Re-running latest()
      // must skip 001 and apply 002 and 003.
      await migrator.latest();

      expect(client.appliedNames, ['001_ok', '002_flaky', '003_after']);
      expect(m2.upCalls, 2);
      expect(
        client.executedAppSql.where((s) => s.contains('ok_table')).length,
        1,
        reason: '001_ok must not be re-applied on the retry',
      );
      expect(
        client.executedAppSql,
        contains('create table after_table (id integer primary key)'),
      );
      expect(await migrator.status(), [
        {'name': '001_ok', 'status': 'completed'},
        {'name': '002_flaky', 'status': 'completed'},
        {'name': '003_after', 'status': 'completed'},
      ]);
    });

    test('rollback() leaves the tracking table consistent when down() throws '
        '(the row is only deleted after down() succeeds)', () async {
      final client = _MigrationTestClient();
      final knex = Knex(client);
      const m1 = SqlMigration(
        name: '001_first',
        upSql: ['create table first_table (id integer primary key)'],
        downSql: ['drop table first_table'],
      );
      const m2 = _ThrowingDownMigration(name: '002_bad_down');
      final migrator = knex.migrator(migrations: const [m1, m2]);

      await migrator.latest();
      expect(client.appliedNames, ['001_first', '002_bad_down']);

      // Rollback processes the latest batch in reverse order, so
      // 002_bad_down is attempted first and throws immediately — before
      // its tracking row would have been deleted, and before 001_first's
      // down() is even attempted.
      await expectLater(
        migrator.rollback,
        throwsA(
          isA<KnexMigrationException>().having(
            (e) => e.message,
            'message',
            contains('failed during down'),
          ),
        ),
      );

      // Tracking table must still reflect reality: neither migration's
      // down() actually completed, so both must still be recorded as
      // applied. If the row were deleted before/regardless of down()
      // succeeding, this would incorrectly show 002_bad_down as pending
      // while its schema changes were never actually reverted.
      expect(client.appliedNames, ['001_first', '002_bad_down']);
      final status = await migrator.status();
      expect(status, [
        {'name': '001_first', 'status': 'completed'},
        {'name': '002_bad_down', 'status': 'completed'},
      ]);
    });

    test('status() and latest() behave correctly against a brand-new, empty '
        'migrations table', () async {
      final client = _MigrationTestClient();
      final knex = Knex(client);
      final migrator = knex.migrator(
        migrations: const [
          SqlMigration(
            name: '001_fresh',
            upSql: ['create table fresh_table (id integer primary key)'],
            downSql: ['drop table fresh_table'],
          ),
          SqlMigration(
            name: '002_fresh',
            upSql: ['create table fresh_table_2 (id integer primary key)'],
            downSql: ['drop table fresh_table_2'],
          ),
        ],
      );

      // Confirm _ensureTable() has not run before anything is called.
      expect(client.trackingDdl, isEmpty);

      // Nothing has run yet: status() alone must not execute migrations,
      // only create the tracking table and report everything pending.
      final initialStatus = await migrator.status();
      expect(initialStatus, [
        {'name': '001_fresh', 'status': 'pending'},
        {'name': '002_fresh', 'status': 'pending'},
      ]);
      expect(client.appliedNames, isEmpty);
      expect(client.executedAppSql, isEmpty);
      // status() must itself have created the tracking table on this
      // fresh database — this is what distinguishes "no migrations ran"
      // from "the tracking table was never even ensured to exist".
      expect(client.trackingDdl, hasLength(1));

      await migrator.latest();
      // latest() ensures the table again (idempotently via IF NOT EXISTS).
      expect(client.trackingDdl, hasLength(2));

      final finalStatus = await migrator.status();
      // Exactly one more _ensureTable() for this status() call.
      expect(client.trackingDdl, hasLength(3));
      expect(finalStatus, [
        {'name': '001_fresh', 'status': 'completed'},
        {'name': '002_fresh', 'status': 'completed'},
      ]);
      expect(client.appliedNames, ['001_fresh', '002_fresh']);
      expect(
        client.executedAppSql,
        containsAll([
          'create table fresh_table (id integer primary key)',
          'create table fresh_table_2 (id integer primary key)',
        ]),
      );

      await migrator.rollback();
      // rollback() also ensures the table before reading/deleting from it.
      expect(client.trackingDdl, hasLength(4));
      expect(client.appliedNames, isEmpty);
    });

    test('with transactions enabled, a failing up() is rolled back (never '
        'committed) and stops the batch', () async {
      final client = _MigrationTestClient(
        config: KnexConfig(
          client: 'mock',
          connection: {},
          migrations: MigrationConfig(disableTransactions: false),
        ),
      );
      final knex = Knex(client);
      const m1 = SqlMigration(
        name: '001_ok',
        upSql: ['create table ok_table (id integer primary key)'],
        downSql: ['drop table ok_table'],
      );
      const m2 = _ThrowingUpMigration(name: '002_boom');
      const m3 = SqlMigration(
        name: '003_never_reached',
        upSql: ['create table never_table (id integer primary key)'],
        downSql: ['drop table never_table'],
      );
      final migrator = knex.migrator(migrations: const [m1, m2, m3]);

      await expectLater(
        migrator.latest,
        throwsA(
          isA<KnexMigrationException>().having(
            (e) => e.message,
            'message',
            contains('failed during up'),
          ),
        ),
      );

      // 001 ran in its own committed transaction; 002 ran in one that was
      // rolled back; 003 never started a transaction at all.
      expect(client.txStatements, ['begin', 'commit', 'begin', 'rollback']);
      expect(client.appliedNames, ['001_ok']);
      expect(
        client.executedAppSql.any((s) => s.contains('never_table')),
        isFalse,
      );
    });

    test('with transactions enabled, a failing down() is rolled back and '
        'leaves the tracking row in place', () async {
      final client = _MigrationTestClient(
        config: KnexConfig(
          client: 'mock',
          connection: {},
          migrations: MigrationConfig(disableTransactions: false),
        ),
      );
      final knex = Knex(client);
      const m1 = SqlMigration(
        name: '001_first',
        upSql: ['create table first_table (id integer primary key)'],
        downSql: ['drop table first_table'],
      );
      const m2 = _ThrowingDownMigration(name: '002_bad_down');
      final migrator = knex.migrator(migrations: const [m1, m2]);

      await migrator.latest();
      expect(client.txStatements, ['begin', 'commit', 'begin', 'commit']);
      client.txStatements.clear();

      await expectLater(
        migrator.rollback,
        throwsA(
          isA<KnexMigrationException>().having(
            (e) => e.message,
            'message',
            contains('failed during down'),
          ),
        ),
      );

      // Rollback processes the batch in reverse: 002's down() throws inside
      // its transaction, which is rolled back and stops the run before the
      // tracking-row delete and before 001's down() is attempted.
      expect(client.txStatements, ['begin', 'rollback']);
      expect(client.appliedNames, ['001_first', '002_bad_down']);
    });

    test('KNOWN LIMITATION: latest() has no locking, so two concurrent calls '
        'racing on the same pending migration both execute up() '
        '— see the concurrency note on Migrator.latest() in '
        'lib/src/migration/migrator.dart', () async {
      final client = _RacingMigrationTestClient();
      final knex = Knex(client);
      const migration = SqlMigration(
        name: '001_racy',
        upSql: ['create table racy_table (id integer primary key)'],
        downSql: ['drop table racy_table'],
      );

      // Two independent Migrator instances (simulating two processes/
      // isolates, or just two overlapping calls) targeting the same
      // migrations table via the same client.
      final migratorA = knex.migrator(migrations: const [migration]);
      final migratorB = knex.migrator(migrations: const [migration]);

      await Future.wait([migratorA.latest(), migratorB.latest()]);

      // Both racers read the table as empty/pending before either wrote to
      // it, so both applied the migration: the up() SQL ran twice. That is
      // the real hazard on any driver — nothing in Migrator prevents it
      // today, and this is a documented gap, not a bug this test is meant
      // to fix.
      expect(
        client.executedAppSql
            .where(
              (s) => s == 'create table racy_table (id integer primary key)',
            )
            .length,
        2,
        reason: 'demonstrates the migration body ran twice under a race',
      );

      // What happens to the *tracking* row after that differs by driver.
      // `_ensureTable()` declares `name` as PRIMARY KEY, so on a real
      // database the losing racer's INSERT into the tracking table would
      // typically fail with a primary-key violation (surfacing as a
      // KnexMigrationException) rather than silently duplicating the row.
      // `_MigrationTestClient` is a plain in-memory list with no uniqueness
      // check, so here both inserts succeed and we observe two duplicate
      // rows for the same migration name — a second, driver-dependent
      // symptom of the same missing-lock gap, not something this mock is
      // claiming is safe on a real database.
      expect(
        client.appliedNames.where((n) => n == '001_racy').length,
        2,
        reason:
            'the mock has no PRIMARY KEY constraint on name, so both '
            'racers\' inserts succeed here; a real driver would likely '
            'reject the second insert instead of duplicating the row',
      );
    });
  });
}

class _MigrationTestClient extends MockClient {
  final List<Map<String, dynamic>> _applied = [];
  final List<String> executedAppSql = [];

  /// Every `CREATE TABLE IF NOT EXISTS ... knex_migrations` statement
  /// [_MigrationTestClient] has seen, in call order — i.e. every time
  /// `Migrator._ensureTable()` actually ran. `executedAppSql` only records
  /// migration-body SQL, so it can't be used to assert the tracking table
  /// was created; this list exists specifically so tests can.
  final List<String> trackingDdl = [];

  /// Transaction control statements (`begin` / `commit` / `rollback`) in
  /// call order — what `Client.runInTransaction()` issues when
  /// `MigrationConfig.disableTransactions` is `false`. The mock has no real
  /// transaction semantics (it never undoes tracking rows on rollback), so
  /// tests can only assert the statement sequence, not data visibility.
  final List<String> txStatements = [];

  _MigrationTestClient({super.config}) : super(driverName: 'pg');

  List<String> get appliedNames =>
      _applied.map((r) => r['name'] as String).toList();

  @override
  Future<dynamic> rawQuery(String sql, List bindings) async {
    final normalized = sql.trim().toLowerCase();

    if (normalized.startsWith('begin') ||
        normalized.startsWith('commit') ||
        normalized.startsWith('rollback')) {
      txStatements.add(normalized.split(RegExp(r'[\s;]')).first);
      return [];
    }

    if (normalized.startsWith('create table if not exists') &&
        normalized.contains('knex_migrations')) {
      trackingDdl.add(sql.trim());
      return [];
    }

    if (normalized.startsWith('select name, batch from') &&
        normalized.contains('knex_migrations')) {
      final rows = _applied.map((r) => Map<String, dynamic>.from(r)).toList();
      rows.sort((a, b) {
        final batchCmp = (a['batch'] as int).compareTo(b['batch'] as int);
        if (batchCmp != 0) return batchCmp;
        return (a['name'] as String).compareTo(b['name'] as String);
      });
      return rows;
    }

    if (normalized.startsWith('insert into') &&
        normalized.contains('knex_migrations')) {
      _applied.add({
        'name': bindings[0] as String,
        'batch': bindings[1] as int,
        'migrated_at': bindings[2],
      });
      return [];
    }

    if (normalized.startsWith('delete from') &&
        normalized.contains('knex_migrations')) {
      final name = bindings[0] as String;
      _applied.removeWhere((r) => r['name'] == name);
      return [];
    }

    executedAppSql.add(sql.trim());
    return [];
  }
}

/// A migration whose [up] always throws, for exercising partial-batch
/// failure handling in [Migrator.latest].
class _ThrowingUpMigration implements MigrationUnit {
  @override
  final String name;

  const _ThrowingUpMigration({required this.name});

  @override
  Future<void> up(Knex knex) async {
    throw StateError('$name: intentional failure in up()');
  }

  @override
  Future<void> down(Knex knex) async {}
}

/// A migration whose [up] throws on its first call and succeeds afterwards,
/// modelling "the failing migration was fixed" between two [Migrator.latest]
/// runs.
class _FailOnceUpMigration implements MigrationUnit {
  @override
  final String name;

  int upCalls = 0;

  _FailOnceUpMigration({required this.name});

  @override
  Future<void> up(Knex knex) async {
    upCalls++;
    if (upCalls == 1) {
      throw StateError('$name: intentional first-attempt failure in up()');
    }
  }

  @override
  Future<void> down(Knex knex) async {}
}

/// A migration whose [up] succeeds but [down] always throws, for exercising
/// tracking-table consistency when [Migrator.rollback] fails mid-batch.
class _ThrowingDownMigration implements MigrationUnit {
  @override
  final String name;

  const _ThrowingDownMigration({required this.name});

  @override
  Future<void> up(Knex knex) async {
    await knex.client.rawQuery('select 1 -- up for $name', const []);
  }

  @override
  Future<void> down(Knex knex) async {
    throw StateError('$name: intentional failure in down()');
  }
}

/// Client used to deterministically reproduce the race between two
/// concurrent [Migrator.latest] calls.
///
/// The first caller to read the applied-migrations table captures a stale
/// (empty) snapshot immediately, then blocks until a second reader has also
/// read the table, before returning that stale snapshot regardless of what
/// the second reader did in the meantime. This reliably reproduces the
/// "both readers see no pending work already applied" race without relying
/// on incidental event-loop timing.
class _RacingMigrationTestClient extends _MigrationTestClient {
  final Completer<void> _secondReadStarted = Completer<void>();
  int _selectCount = 0;

  @override
  Future<dynamic> rawQuery(String sql, List bindings) async {
    final normalized = sql.trim().toLowerCase();
    final isAppliedRead =
        normalized.startsWith('select name, batch from') &&
        normalized.contains('knex_migrations');

    if (isAppliedRead) {
      _selectCount++;
      if (_selectCount == 1) {
        // Snapshot the current (empty) state right away, then wait for the
        // second concurrent reader before handing back that stale snapshot.
        final stale = await super.rawQuery(sql, bindings);
        await _secondReadStarted.future;
        return stale;
      }
      if (_selectCount == 2 && !_secondReadStarted.isCompleted) {
        _secondReadStarted.complete();
      }
    }
    return super.rawQuery(sql, bindings);
  }
}
