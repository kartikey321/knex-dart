/// Benchmark: raw sqlite3 queries vs knex_dart QueryBuilder
///
/// Run from the knex_dart_sqlite package root:
///   dart run benchmark/query_benchmark.dart
///
/// The benchmark sets up an in-memory SQLite DB, inserts seed rows, then
/// times each operation (SELECT / INSERT / UPDATE / DELETE) over [_iterations]
/// iterations using both raw SQL and knex QueryBuilder.

import 'package:sqlite3/sqlite3.dart';
import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';

const int _iterations = 10000;
const int _seedRows = 100;

// ─── helpers ─────────────────────────────────────────────────────────────────

typedef Bench = Future<void> Function();

Future<Duration> _time(Bench fn) async {
  final sw = Stopwatch()..start();
  await fn();
  sw.stop();
  return sw.elapsed;
}

void _printRow(String label, Duration d, int iters) {
  final ms = d.inMicroseconds / 1000;
  final perOp = d.inMicroseconds / iters;
  print('  ${label.padRight(34)} ${ms.toStringAsFixed(1).padLeft(9)} ms  '
      '(${perOp.toStringAsFixed(2)} µs/op)');
}

void _header(String title) {
  print('');
  print('── $title ${'─' * (60 - title.length - 3)}');
}

// ─── raw sqlite3 benchmark ───────────────────────────────────────────────────

class RawBench {
  late Database _db;

  void setUp() {
    _db = sqlite3.openInMemory();
    _db.execute('''
      CREATE TABLE users (
        id   INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT    NOT NULL,
        age  INTEGER NOT NULL
      )
    ''');
    for (var i = 0; i < _seedRows; i++) {
      _db.execute(
        'INSERT INTO users (name, age) VALUES (?, ?)',
        ['seed_$i', 20 + i % 40],
      );
    }
  }

  void tearDown() => _db.dispose();

  Future<Duration> benchSelect() => _time(() async {
        for (var i = 0; i < _iterations; i++) {
          _db.select('SELECT * FROM users WHERE age > ?', [25]);
        }
      });

  Future<Duration> benchInsert() => _time(() async {
        for (var i = 0; i < _iterations; i++) {
          _db.execute(
            'INSERT INTO users (name, age) VALUES (?, ?)',
            ['bench_$i', 30],
          );
        }
      });

  Future<Duration> benchUpdate() => _time(() async {
        for (var i = 0; i < _iterations; i++) {
          _db.execute(
            'UPDATE users SET age = ? WHERE name = ?',
            [31, 'seed_${i % _seedRows}'],
          );
        }
      });

  Future<Duration> benchDelete() => _time(() async {
        // Refill so we always have rows to delete.
        for (var i = 0; i < _iterations; i++) {
          _db.execute(
            'INSERT INTO users (name, age) VALUES (?, ?)',
            ['del_$i', 99],
          );
        }
        for (var i = 0; i < _iterations; i++) {
          _db.execute(
            "DELETE FROM users WHERE name = 'del_$i'",
          );
        }
      });
}

// ─── knex QueryBuilder benchmark ─────────────────────────────────────────────

class KnexBench {
  late SQLiteClient _client;

  Future<void> setUp() async {
    _client = await SQLiteClient.connect(filename: ':memory:');
    await _client.rawQuery('''
      CREATE TABLE users (
        id   INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT    NOT NULL,
        age  INTEGER NOT NULL
      )
    ''', []);
    for (var i = 0; i < _seedRows; i++) {
      final qb = _client
          .queryBuilder()
          .table('users')
          .insert({'name': 'seed_$i', 'age': 20 + i % 40});
      await _client.execute(qb);
    }
  }

  Future<void> tearDown() => _client.close();

  Future<Duration> benchSelect() => _time(() async {
        for (var i = 0; i < _iterations; i++) {
          final qb = _client
              .queryBuilder()
              .table('users')
              .where('age', '>', 25);
          await _client.select(qb);
        }
      });

  Future<Duration> benchInsert() => _time(() async {
        for (var i = 0; i < _iterations; i++) {
          final qb = _client
              .queryBuilder()
              .table('users')
              .insert({'name': 'bench_$i', 'age': 30});
          await _client.insert(qb);
        }
      });

  Future<Duration> benchUpdate() => _time(() async {
        for (var i = 0; i < _iterations; i++) {
          final qb = _client
              .queryBuilder()
              .table('users')
              .where('name', '=', 'seed_${i % _seedRows}')
              .update({'age': 31});
          await _client.update(qb);
        }
      });

  Future<Duration> benchDelete() => _time(() async {
        // Refill so we always have rows to delete.
        for (var i = 0; i < _iterations; i++) {
          final ins = _client
              .queryBuilder()
              .table('users')
              .insert({'name': 'del_$i', 'age': 99});
          await _client.insert(ins);
        }
        for (var i = 0; i < _iterations; i++) {
          final del = _client
              .queryBuilder()
              .table('users')
              .where('name', '=', 'del_$i')
              .delete();
          await _client.delete(del);
        }
      });
}

// ─── main ─────────────────────────────────────────────────────────────────────

Future<void> main() async {
  print('knex_dart vs raw sqlite3 — in-memory SQLite benchmark');
  print('iterations : $_iterations');
  print('seed rows  : $_seedRows');

  // ── Raw ──────────────────────────────────────────────────────────────────
  _header('RAW sqlite3');
  final raw = RawBench()..setUp();
  final rawSelect = await raw.benchSelect();
  final rawInsert = await raw.benchInsert();
  final rawUpdate = await raw.benchUpdate();
  final rawDelete = await raw.benchDelete();
  raw.tearDown();

  _printRow('SELECT (age > 25)', rawSelect, _iterations);
  _printRow('INSERT', rawInsert, _iterations);
  _printRow('UPDATE', rawUpdate, _iterations);
  _printRow('DELETE (insert+delete pairs)', rawDelete, _iterations);

  // ── Knex ─────────────────────────────────────────────────────────────────
  _header('knex_dart QueryBuilder');
  final knex = KnexBench();
  await knex.setUp();
  final knexSelect = await knex.benchSelect();
  final knexInsert = await knex.benchInsert();
  final knexUpdate = await knex.benchUpdate();
  final knexDelete = await knex.benchDelete();
  await knex.tearDown();

  _printRow('SELECT (age > 25)', knexSelect, _iterations);
  _printRow('INSERT', knexInsert, _iterations);
  _printRow('UPDATE', knexUpdate, _iterations);
  _printRow('DELETE (insert+delete pairs)', knexDelete, _iterations);

  // ── Comparison ───────────────────────────────────────────────────────────
  _header('Overhead (knex / raw)');

  double ratio(Duration knexD, Duration rawD) =>
      knexD.inMicroseconds / rawD.inMicroseconds;

  void printRatio(String op, Duration k, Duration r) {
    final x = ratio(k, r);
    print('  ${op.padRight(34)} ${x.toStringAsFixed(2)}x');
  }

  printRatio('SELECT', knexSelect, rawSelect);
  printRatio('INSERT', knexInsert, rawInsert);
  printRatio('UPDATE', knexUpdate, rawUpdate);
  printRatio('DELETE', knexDelete, rawDelete);

  print('');
  print('Done.');
}
