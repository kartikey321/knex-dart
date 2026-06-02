import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';
import 'package:test/test.dart';

const _isWeb = bool.fromEnvironment('dart.library.js_interop');

void main() {
  group('SQLiteClient error futures', () {
    late KnexSQLite db;

    setUp(() async {
      db = await KnexSQLite.connect(filename: ':memory:');
    });

    tearDown(() => db.close());

    test(
      'invalid SQL preserves the originating stack trace',
      () async {
        Object? error;
        StackTrace? stackTrace;

        try {
          await db.rawSql('SELEC invalid syntax');
        } catch (e, st) {
          error = e;
          stackTrace = st;
        }

        expect(error, isNotNull);
        expect(stackTrace, isNotNull);
        expect(stackTrace.toString(), contains('_execute'));
      },
      skip: _isWeb ? 'native stack symbol assertion' : false,
    );

    test(
      'constraint failures preserve the originating stack trace',
      () async {
        await db.rawSql(
          'CREATE TABLE unique_items (id INTEGER PRIMARY KEY, name TEXT UNIQUE)',
        );
        await db.rawSql('INSERT INTO unique_items (name) VALUES (?)', ['same']);

        Object? error;
        StackTrace? stackTrace;
        try {
          await db.rawSql('INSERT INTO unique_items (name) VALUES (?)', [
            'same',
          ]);
        } catch (e, st) {
          error = e;
          stackTrace = st;
        }

        expect(error, isNotNull);
        expect(stackTrace, isNotNull);
        expect(stackTrace.toString(), contains('_execute'));
      },
      skip: _isWeb ? 'native stack symbol assertion' : false,
    );

    test(
      'compiled query failures preserve the originating stack trace',
      () async {
        final query = db.queryBuilder().table('missing_items').select(['id']);

        Object? error;
        StackTrace? stackTrace;
        try {
          await db.select(query);
        } catch (e, st) {
          error = e;
          stackTrace = st;
        }

        expect(error, isNotNull);
        expect(stackTrace, isNotNull);
        expect(stackTrace.toString(), contains('_execute'));
      },
      skip: _isWeb ? 'native stack symbol assertion' : false,
    );
  });
}
