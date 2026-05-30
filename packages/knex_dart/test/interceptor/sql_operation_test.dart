import 'package:knex_dart/src/util/enums.dart';
import 'package:test/test.dart';

void main() {
  // ── sqlOperationFromRaw ────────────────────────────────────────────────────

  group('sqlOperationFromRaw', () {
    group('recognises all supported verbs (upper-case)', () {
      const cases = {
        'SELECT * FROM t': 'SELECT',
        'INSERT INTO t VALUES (1)': 'INSERT',
        'UPDATE t SET x=1': 'UPDATE',
        'DELETE FROM t': 'DELETE',
        'CREATE TABLE t (id INT)': 'CREATE',
        'DROP TABLE t': 'DROP',
        'ALTER TABLE t ADD col INT': 'ALTER',
        'TRUNCATE TABLE t': 'TRUNCATE',
        'BEGIN': 'BEGIN',
        'COMMIT': 'COMMIT',
        'ROLLBACK': 'ROLLBACK',
        'SAVEPOINT sp1': 'SAVEPOINT',
        'MERGE INTO t USING s ON (t.id = s.id)': 'MERGE',
      };

      for (final entry in cases.entries) {
        test('${entry.key} → ${entry.value}', () {
          expect(sqlOperationFromRaw(entry.key), entry.value);
        });
      }
    });

    group('case-insensitive matching', () {
      test('lower-case select', () => expect(sqlOperationFromRaw('select * from t'), 'SELECT'));
      test('mixed-case Select', () => expect(sqlOperationFromRaw('Select * from t'), 'SELECT'));
      test('lower-case insert', () => expect(sqlOperationFromRaw('insert into t values (1)'), 'INSERT'));
    });

    group('leading whitespace stripped', () {
      test('spaces before SELECT', () => expect(sqlOperationFromRaw('  SELECT 1'), 'SELECT'));
      test('tab before INSERT', () => expect(sqlOperationFromRaw('\tINSERT INTO t VALUES (1)'), 'INSERT'));
      test('newline before UPDATE', () => expect(sqlOperationFromRaw('\nUPDATE t SET x=1'), 'UPDATE'));
    });

    group('unknown input falls back to DB', () {
      test('empty string', () => expect(sqlOperationFromRaw(''), 'DB'));
      test('whitespace only', () => expect(sqlOperationFromRaw('   '), 'DB'));
      test('EXPLAIN query', () => expect(sqlOperationFromRaw('EXPLAIN SELECT 1'), 'DB'));
      test('WITH CTE (no leading verb match)', () => expect(sqlOperationFromRaw('WITH cte AS (SELECT 1) SELECT * FROM cte'), 'DB'));
    });

    group('word-boundary check — no false positives', () {
      test('SELECTIVITY does not match SELECT', () {
        expect(sqlOperationFromRaw('SELECTIVITY_REPORT foo'), 'DB');
      });
      test('SELECTS (plural) does not match SELECT', () {
        expect(sqlOperationFromRaw('SELECTS_ALL'), 'DB');
      });
      test('INSERTED does not match INSERT', () {
        expect(sqlOperationFromRaw('INSERTED_AT'), 'DB');
      });
      test('UPDATES does not match UPDATE', () {
        expect(sqlOperationFromRaw('UPDATES_COUNT'), 'DB');
      });
      test('DROPPING does not match DROP', () {
        expect(sqlOperationFromRaw('DROPPING_TABLE'), 'DB');
      });
    });

    group('boundary character variants', () {
      test('keyword followed by ( is matched', () {
        expect(sqlOperationFromRaw('SELECT(1)'), 'SELECT');
      });
      test('keyword followed by ; is matched', () {
        expect(sqlOperationFromRaw('COMMIT;'), 'COMMIT');
      });
      test('bare keyword (end of string) is matched', () {
        expect(sqlOperationFromRaw('BEGIN'), 'BEGIN');
      });
      test('keyword followed by tab is matched', () {
        expect(sqlOperationFromRaw('SELECT\t*\tFROM\tt'), 'SELECT');
      });
    });

    group('leading SQL comment is NOT skipped (documented limitation)', () {
      test('block comment before UPDATE returns DB', () {
        expect(sqlOperationFromRaw('/* comment */ UPDATE t SET x=1'), 'DB');
      });
      test('line comment before SELECT returns DB', () {
        expect(sqlOperationFromRaw('-- hint\nSELECT 1'), 'DB');
      });
    });
  });

  // ── queryMethodToSqlOperation ──────────────────────────────────────────────

  group('queryMethodToSqlOperation', () {
    test('select → SELECT', () => expect(queryMethodToSqlOperation(QueryMethod.select), 'SELECT'));
    test('insert → INSERT', () => expect(queryMethodToSqlOperation(QueryMethod.insert), 'INSERT'));
    test('update → UPDATE', () => expect(queryMethodToSqlOperation(QueryMethod.update), 'UPDATE'));
    test('delete → DELETE', () => expect(queryMethodToSqlOperation(QueryMethod.delete), 'DELETE'));
    test('truncate → TRUNCATE', () => expect(queryMethodToSqlOperation(QueryMethod.truncate), 'TRUNCATE'));

    test('first → SELECT (not FIRST)', () {
      expect(queryMethodToSqlOperation(QueryMethod.first), 'SELECT');
    });
    test('pluck → SELECT (not PLUCK)', () {
      expect(queryMethodToSqlOperation(QueryMethod.pluck), 'SELECT');
    });
  });
}
