import 'package:test/test.dart';
import 'package:knex_dart/src/query/sql_string.dart';

void main() {
  group('SqlString', () {
    test('should create SqlString with sql and bindings', () {
      final sql = SqlString('SELECT * FROM users WHERE id = ?', [1]);
      expect(sql.sql, 'SELECT * FROM users WHERE id = ?');
      expect(sql.bindings, [1]);
      expect(sql.method, null);
    });

    test('should create SqlString with method', () {
      final sql = SqlString('SELECT * FROM users', [], method: 'select');
      expect(sql.method, 'select');
    });

    test('should convert to string', () {
      final sql = SqlString('SELECT * FROM users', []);
      expect(sql.toString(), 'SELECT * FROM users');
    });

    test('should convert to map', () {
      final sql = SqlString('SELECT * FROM users WHERE id = ?', [
        1,
      ], method: 'select');
      final map = sql.toMap();
      expect(map['sql'], 'SELECT * FROM users WHERE id = ?');
      expect(map['bindings'], [1]);
      expect(map['method'], 'select');
    });

    test('should copy with new values', () {
      final sql1 = SqlString('SELECT * FROM users', []);
      final sql2 = sql1.copyWith(sql: 'SELECT * FROM posts', bindings: [1]);
      expect(sql2.sql, 'SELECT * FROM posts');
      expect(sql2.bindings, [1]);
    });

    test('should implement equality correctly', () {
      final sql1 = SqlString('SELECT * FROM users', [1, 2]);
      final sql2 = SqlString('SELECT * FROM users', [1, 2]);
      final sql3 = SqlString('SELECT * FROM users', [1, 3]);

      expect(sql1 == sql2, true);
      expect(sql1 == sql3, false);
    });

    test('should implement hashCode correctly', () {
      final sql1 = SqlString('SELECT * FROM users', [1]);
      final sql2 = SqlString('SELECT * FROM users', [1]);

      expect(sql1.hashCode, sql2.hashCode);
    });
  });
}
