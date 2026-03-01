import 'package:test/test.dart';
import '../mocks/mock_client.dart';

void main() {
  group('whereFullText (PostgreSQL)', () {
    late MockClient pg;

    setUp(() => pg = MockClient(driverName: 'pg'));

    test('Single column', () {
      final sql = pg
          .queryBuilder()
          .from('articles')
          .whereFullText('body', 'knex')
          .toSQL();
      expect(
        sql.sql,
        'select * from "articles" where (to_tsvector("body")) @@ to_tsquery(\$1)',
      );
      expect(sql.bindings, ['knex']);
    });

    test('Multiple columns', () {
      final sql = pg.queryBuilder().from('articles').whereFullText([
        'title',
        'body',
      ], 'knex dart').toSQL();
      expect(
        sql.sql,
        'select * from "articles" where (to_tsvector("title") || to_tsvector("body")) @@ to_tsquery(\$1)',
      );
      expect(sql.bindings, ['knex dart']);
    });

    test('With language option', () {
      final sql = pg.queryBuilder().from('articles').whereFullText(
        'body',
        'knex',
        {'language': 'english'},
      ).toSQL();
      expect(
        sql.sql,
        'select * from "articles" where (to_tsvector(\'english\', "body")) @@ to_tsquery(\'english\', \$1)',
      );
      expect(sql.bindings, ['knex']);
    });

    test('orWhereFullText', () {
      final sql = pg
          .queryBuilder()
          .from('articles')
          .where('public', true)
          .orWhereFullText('body', 'knex')
          .toSQL();
      expect(
        sql.sql,
        'select * from "articles" where "public" = \$1 or (to_tsvector("body")) @@ to_tsquery(\$2)',
      );
      expect(sql.bindings, [true, 'knex']);
    });
  });

  group('whereFullText (MySQL)', () {
    test('Single column', () {
      final my = MockClient(driverName: 'mysql');
      final sql = my
          .queryBuilder()
          .from('articles')
          .whereFullText('body', 'knex')
          .toSQL();
      expect(
        sql.sql,
        'select * from `articles` where MATCH(`body`) AGAINST(\$1)',
      );
      expect(sql.bindings, ['knex']);
    });

    test('Multiple columns', () {
      final my = MockClient(driverName: 'mysql');
      final sql = my.queryBuilder().from('articles').whereFullText([
        'title',
        'body',
      ], 'knex dart').toSQL();
      expect(
        sql.sql,
        'select * from `articles` where MATCH(`title`, `body`) AGAINST(\$1)',
      );
      expect(sql.bindings, ['knex dart']);
    });

    test('With mode option', () {
      final my = MockClient(driverName: 'mysql');
      final sql = my.queryBuilder().from('articles').whereFullText(
        'body',
        'knex',
        {'mode': 'IN BOOLEAN MODE'},
      ).toSQL();
      expect(
        sql.sql,
        'select * from `articles` where MATCH(`body`) AGAINST(\$1 IN BOOLEAN MODE)',
      );
      expect(sql.bindings, ['knex']);
    });
  });

  group('whereFullText (SQLite)', () {
    test('SQLite uses MATCH against the first column', () {
      final sq = MockClient(driverName: 'sqlite');
      final sql = sq
          .queryBuilder()
          .from('articles')
          .whereFullText('articles', 'knex')
          .toSQL();
      expect(sql.sql, 'select * from "articles" where "articles" MATCH \$1');
      expect(sql.bindings, ['knex']);
    });

    test('Fallback dialect gets a LIKE query', () {
      final client = MockClient(driverName: 'unknownDB');
      final sql = client
          .queryBuilder()
          .from('articles')
          .whereFullText('title', 'knex')
          .toSQL();
      expect(sql.sql, 'select * from "articles" where "title" like \$1');
      expect(sql.bindings, ['%knex%']);
    });
  });
}
