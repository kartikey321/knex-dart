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
            'properties': {'id': <String, dynamic>{'type': 'integer'}},
          },
          ifNotExists: true,
        );

        await migrator.latest();
        final lower = client.executedAppSql.map((s) => s.toLowerCase()).toList();
        expect(lower.any((s) => s.contains('auto_table')), isTrue,
            reason: 'Table name from JSON Schema title should appear in DDL');
      },
    );

    test('fromConfig uses MigrationConfig.directory as SQL source', () async {
      final dir = await Directory.systemTemp.createTemp('knex_fromconfig_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      await File('${dir.path}/400_cfg.up.sql')
          .writeAsString('create table cfg_table (id integer primary key)');
      await File('${dir.path}/400_cfg.down.sql')
          .writeAsString('drop table cfg_table');

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
}

class _MigrationTestClient extends MockClient {
  final List<Map<String, dynamic>> _applied = [];
  final List<String> executedAppSql = [];

  _MigrationTestClient({super.config}) : super(driverName: 'pg');

  List<String> get appliedNames =>
      _applied.map((r) => r['name'] as String).toList();

  @override
  Future<dynamic> rawQuery(String sql, List bindings) async {
    final normalized = sql.trim().toLowerCase();

    if (normalized.startsWith('begin') ||
        normalized.startsWith('commit') ||
        normalized.startsWith('rollback')) {
      return [];
    }

    if (normalized.startsWith('create table if not exists') &&
        normalized.contains('knex_migrations')) {
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
