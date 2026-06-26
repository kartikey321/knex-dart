import 'package:dartastic_opentelemetry_api/dartastic_opentelemetry_api.dart';
import 'package:knex_dart_otel/knex_dart_otel.dart';
import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';
import 'package:sqlite3/sqlite3.dart';

const int _iterations = 10000;
const int _seedRows = 100;

typedef Bench = Future<void> Function();

class CapturingHistogram extends APIHistogram<double> {
  final List<(double value, Map<String, Object> attrs)> recordings = [];

  CapturingHistogram(APIMeter meter)
    : super('db.client.operation.duration', null, 's', true, meter);

  @override
  void record(double value, [Attributes? attributes]) {
    recordings.add((value, {}));
  }

  @override
  void recordWithMap(double value, Map<String, Object> attributeMap) {
    recordings.add((value, Map<String, Object>.from(attributeMap)));
  }
}

Future<Duration> _time(Bench fn) async {
  final sw = Stopwatch()..start();
  await fn();
  sw.stop();
  return sw.elapsed;
}

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
      _db.execute('INSERT INTO users (name, age) VALUES (?, ?)', [
        'seed_$i',
        20 + i % 40,
      ]);
    }
  }

  void tearDown() => _db.close();

  Future<Duration> benchSelect() => _time(() async {
    for (var i = 0; i < _iterations; i++) {
      _db.select('SELECT * FROM users WHERE age > ?', [25]);
    }
  });

  Future<Duration> benchSelectMapped() => _time(() async {
    for (var i = 0; i < _iterations; i++) {
      final result = _db.select('SELECT * FROM users WHERE age > ?', [25]);
      final columns = result.columnNames;
      for (final row in result.rows) {
        final mapped = <String, dynamic>{};
        for (var j = 0; j < columns.length; j++) {
          mapped[columns[j]] = row[j];
        }
      }
    }
  });

  Future<Duration> benchInsert() => _time(() async {
    for (var i = 0; i < _iterations; i++) {
      _db.execute('INSERT INTO users (name, age) VALUES (?, ?)', [
        'bench_$i',
        30,
      ]);
    }
  });

  Future<Duration> benchUpdate() => _time(() async {
    for (var i = 0; i < _iterations; i++) {
      _db.execute('UPDATE users SET age = ? WHERE name = ?', [
        31,
        'seed_${i % _seedRows}',
      ]);
    }
  });

  Future<Duration> benchDelete() => _time(() async {
    for (var i = 0; i < _iterations; i++) {
      _db.execute("DELETE FROM users WHERE name = 'del_$i'");
    }
  });

  void seedDeleteRows() {
    for (var i = 0; i < _iterations; i++) {
      _db.execute('INSERT INTO users (name, age) VALUES (?, ?)', [
        'del_$i',
        99,
      ]);
    }
  }
}

class KnexBench {
  late KnexSQLite _db;

  Future<void> setUp() async {
    _db = await KnexSQLite.connect(filename: ':memory:');
    await _seed(_db);
  }

  Future<void> tearDown() => _db.close();

  Future<Duration> benchSelect() => _time(() async {
    for (var i = 0; i < _iterations; i++) {
      final qb = _db.queryBuilder().table('users').where('age', '>', 25);
      await _db.select(qb);
    }
  });

  Future<Duration> benchInsert() => _time(() async {
    for (var i = 0; i < _iterations; i++) {
      final qb = _db.queryBuilder().table('users').insert({
        'name': 'bench_$i',
        'age': 30,
      });
      await _db.insert(qb);
    }
  });

  Future<Duration> benchUpdate() => _time(() async {
    for (var i = 0; i < _iterations; i++) {
      final qb = _db
          .queryBuilder()
          .table('users')
          .where('name', '=', 'seed_${i % _seedRows}')
          .update({'age': 31});
      await _db.update(qb);
    }
  });

  Future<Duration> benchDelete() => _time(() async {
    for (var i = 0; i < _iterations; i++) {
      final del = _db
          .queryBuilder()
          .table('users')
          .where('name', '=', 'del_$i')
          .delete();
      await _db.delete(del);
    }
  });

  Future<void> seedDeleteRows() => _seedDeleteRows(_db);
}

class KnexOtelBench {
  late KnexSQLite _db;

  Future<void> setUp() async {
    OTelAPI.initialize(
      endpoint: 'http://localhost:4317',
      serviceName: 'knex-dart-sqlite-live-benchmark',
      serviceVersion: '0.0.1',
    );
    final tracer = OTelAPI.tracer('knex_dart_sqlite_live_benchmark');
    final histogram = CapturingHistogram(
      OTelAPI.meterProvider().getMeter(name: 'knex_dart_sqlite_live_benchmark'),
    );
    _db = await KnexSQLite.connect(
      filename: ':memory:',
      interceptors: [
        KnexOtelInterceptor(
          tracer: tracer,
          operationDurationHistogram: histogram,
        ),
      ],
    );
    await _seed(_db);
  }

  Future<void> tearDown() async {
    await _db.close();
  }

  Future<Duration> benchSelect() => _time(() async {
    for (var i = 0; i < _iterations; i++) {
      final qb = _db.queryBuilder().table('users').where('age', '>', 25);
      await _db.select(qb);
    }
  });

  Future<Duration> benchInsert() => _time(() async {
    for (var i = 0; i < _iterations; i++) {
      final qb = _db.queryBuilder().table('users').insert({
        'name': 'bench_$i',
        'age': 30,
      });
      await _db.insert(qb);
    }
  });

  Future<Duration> benchUpdate() => _time(() async {
    for (var i = 0; i < _iterations; i++) {
      final qb = _db
          .queryBuilder()
          .table('users')
          .where('name', '=', 'seed_${i % _seedRows}')
          .update({'age': 31});
      await _db.update(qb);
    }
  });

  Future<Duration> benchDelete() => _time(() async {
    for (var i = 0; i < _iterations; i++) {
      final del = _db
          .queryBuilder()
          .table('users')
          .where('name', '=', 'del_$i')
          .delete();
      await _db.delete(del);
    }
  });

  Future<void> seedDeleteRows() => _seedDeleteRows(_db);
}

Future<void> _seed(KnexSQLite db) async {
  await db.rawSql('''
      CREATE TABLE users (
        id   INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT    NOT NULL,
        age  INTEGER NOT NULL
      )
    ''');
  for (var i = 0; i < _seedRows; i++) {
    final qb = db.queryBuilder().table('users').insert({
      'name': 'seed_$i',
      'age': 20 + i % 40,
    });
    await db.insert(qb);
  }
}

Future<void> _seedDeleteRows(KnexSQLite db) async {
  for (var i = 0; i < _iterations; i++) {
    final ins = db.queryBuilder().table('users').insert({
      'name': 'del_$i',
      'age': 99,
    });
    await db.insert(ins);
  }
}

double _perOp(Duration duration) => duration.inMicroseconds / _iterations;

String _formatMicros(Duration duration) => _perOp(duration).toStringAsFixed(2);

String _formatRatio(Duration numerator, Duration denominator) {
  return '${(numerator.inMicroseconds / denominator.inMicroseconds).toStringAsFixed(2)}x';
}

String _cell(String value, int width) => value.padLeft(width);

Future<void> main() async {
  final raw = RawBench()..setUp();
  final rawSelect = await raw.benchSelect();
  final rawSelectMapped = await raw.benchSelectMapped();
  final rawInsert = await raw.benchInsert();
  final rawUpdate = await raw.benchUpdate();
  raw.seedDeleteRows();
  final rawDelete = await raw.benchDelete();
  raw.tearDown();

  final knex = KnexBench();
  await knex.setUp();
  final knexSelect = await knex.benchSelect();
  final knexInsert = await knex.benchInsert();
  final knexUpdate = await knex.benchUpdate();
  await knex.seedDeleteRows();
  final knexDelete = await knex.benchDelete();
  await knex.tearDown();

  final otel = KnexOtelBench();
  await otel.setUp();
  final otelSelect = await otel.benchSelect();
  final otelInsert = await otel.benchInsert();
  final otelUpdate = await otel.benchUpdate();
  await otel.seedDeleteRows();
  final otelDelete = await otel.benchDelete();
  await otel.tearDown();

  print('## SQLite Live Query Benchmark  (10 000 iterations)');
  print('');
  print(
    '| Operation | raw sqlite3 | raw mapped | knex (µs/op) | knex+otel (µs/op) | knex/raw | knex/mapped | otel/knex |',
  );
  print(
    '|-----------|-------------|------------|--------------|-------------------|----------|-------------|-----------|',
  );

  void printRow(
    String operation,
    Duration rawDuration,
    Duration? rawMappedDuration,
    Duration knexDuration,
    Duration otelDuration,
  ) {
    final mappedDuration = rawMappedDuration ?? rawDuration;
    print(
      '| ${operation.padRight(9)} '
      '| ${_cell(_formatMicros(rawDuration), 11)} '
      '| ${_cell(rawMappedDuration == null ? '-' : _formatMicros(rawMappedDuration), 10)} '
      '| ${_cell(_formatMicros(knexDuration), 12)} '
      '| ${_cell(_formatMicros(otelDuration), 17)} '
      '| ${_cell(_formatRatio(knexDuration, rawDuration), 8)} '
      '| ${_cell(_formatRatio(knexDuration, mappedDuration), 11)} '
      '| ${_cell(_formatRatio(otelDuration, knexDuration), 9)} |',
    );
  }

  printRow('SELECT', rawSelect, rawSelectMapped, knexSelect, otelSelect);
  printRow('INSERT', rawInsert, null, knexInsert, otelInsert);
  printRow('UPDATE', rawUpdate, null, knexUpdate, otelUpdate);
  printRow('DELETE', rawDelete, null, knexDelete, otelDelete);
}
