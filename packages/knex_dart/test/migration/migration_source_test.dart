import 'dart:io';

import 'package:knex_dart/knex_dart.dart';
import 'package:test/test.dart';

import '../mocks/mock_client.dart';

void main() {
  group('MigrationSource contracts', () {
    test(
      'CodeMigrationSource returns registered migration units unchanged',
      () async {
        final knex = Knex(MockClient());
        final source = CodeMigrationSource(const [
          SqlMigration(
            name: '001_a',
            upSql: ['select 1'],
            downSql: ['select 1'],
          ),
        ]);

        final units = await source.load(knex);
        expect(units.length, 1);
        expect(units.first.name, '001_a');
      },
    );

    test(
      'SqlDirectoryMigrationSource loads .up/.down pairs in sorted order',
      () async {
        final knex = Knex(MockClient());
        final dir = await Directory.systemTemp.createTemp('knex_dart_mig_src_');
        addTearDown(() async {
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
        });

        await File(
          '${dir.path}/002_seed.up.sql',
        ).writeAsString('insert into users (id) values (1)');
        await File(
          '${dir.path}/001_create.up.sql',
        ).writeAsString('create table users (id integer primary key)');
        await File(
          '${dir.path}/001_create.down.sql',
        ).writeAsString('drop table users');
        await File('${dir.path}/README.md').writeAsString('ignore me');

        final source = SqlDirectoryMigrationSource(dir.path);
        final units = await source.load(knex);

        expect(units.map((u) => u.name).toList(), ['001_create', '002_seed']);

        final first = units.first as SqlMigration;
        expect(
          first.upSql.single.trim(),
          'create table users (id integer primary key)',
        );
        expect(first.downSql.single.trim(), 'drop table users');

        final second = units[1] as SqlMigration;
        expect(second.downSql, isEmpty); // no 002_seed.down.sql
      },
    );

    test(
      'SqlDirectoryMigrationSource throws if directory is missing',
      () async {
        final knex = Knex(MockClient());
        final source = SqlDirectoryMigrationSource(
          '${Directory.systemTemp.path}/not_real_knex_migrations_dir_12345',
        );

        await expectLater(
          () => source.load(knex),
          throwsA(
            isA<KnexMigrationException>().having(
              (e) => e.message,
              'message',
              contains('does not exist'),
            ),
          ),
        );
      },
    );
  });
}
