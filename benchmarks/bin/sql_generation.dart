import 'package:knex_dart/knex_dart.dart';

const int _iterations = 10000;
const int _warmupIterations = 1000;

typedef SqlGeneration = SqlString Function(KnexDialect dialect);

SqlString? _lastSql;

class SqlOperation {
  final String name;
  final SqlGeneration run;

  const SqlOperation(this.name, this.run);
}

class OperationResult {
  final String fastestDialect;
  final String slowestDialect;
  final double ratio;

  const OperationResult({
    required this.fastestDialect,
    required this.slowestDialect,
    required this.ratio,
  });
}

const _dialects = [
  KnexDialect.postgres,
  KnexDialect.mysql,
  KnexDialect.sqlite,
  KnexDialect.mariadb,
  KnexDialect.redshift,
  KnexDialect.turso,
  KnexDialect.d1,
  KnexDialect.duckdb,
  KnexDialect.snowflake,
  KnexDialect.bigquery,
  KnexDialect.mssql,
];

final _operations = [
  SqlOperation(
    'SELECT simple',
    (dialect) => KnexQuery.forDialect(
      dialect,
    ).from('users').select(['id', 'name', 'email']).toSQL(),
  ),
  SqlOperation(
    'SELECT complex',
    (dialect) => KnexQuery.forDialect(dialect)
        .from('users')
        .select(['*'])
        .where('age', '>', 25)
        .where('active', '=', true)
        .orderBy('name', 'asc')
        .limit(50)
        .offset(100)
        .toSQL(),
  ),
  SqlOperation(
    'INSERT',
    (dialect) => KnexQuery.forDialect(dialect).from('users').insert({
      'name': 'Alice',
      'age': 30,
      'email': 'a@example.com',
    }).toSQL(),
  ),
  SqlOperation(
    'UPDATE',
    (dialect) => KnexQuery.forDialect(dialect)
        .from('users')
        .where('id', '=', 1)
        .update({'name': 'Bob', 'age': 31})
        .toSQL(),
  ),
  SqlOperation(
    'DELETE',
    (dialect) => KnexQuery.forDialect(
      dialect,
    ).from('users').where('id', '=', 1).delete().toSQL(),
  ),
  SqlOperation(
    'JOIN',
    (dialect) => KnexQuery.forDialect(dialect)
        .from('users')
        .select(['users.*', 'orders.total'])
        .join('orders', (JoinClause join) {
          join.on('users.id', '=', 'orders.user_id');
        })
        .where('orders.total', '>', 100)
        .toSQL(),
  ),
  SqlOperation(
    'Subquery',
    (dialect) => KnexQuery.forDialect(dialect).from('users').whereIn('id', (
      QueryBuilder qb,
    ) {
      qb.from('orders').select(['user_id']).where('total', '>', 500);
    }).toSQL(),
  ),
];

Duration _time(SqlGeneration fn, KnexDialect dialect, int iterations) {
  final sw = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    _lastSql = fn(dialect);
  }
  sw.stop();
  return sw.elapsed;
}

String _dialectName(KnexDialect dialect) => dialect.name;

String _formatPerOp(Duration duration) {
  final perOp = duration.inMicroseconds / _iterations;
  return '${perOp.toStringAsFixed(2)} µs/op';
}

String _cell(String value, int width) => value.padLeft(width);

OperationResult _operationResult(
  Map<KnexDialect, Map<String, Duration>> results,
  String operationName,
) {
  var fastest = _dialects.first;
  var slowest = _dialects.first;

  for (final dialect in _dialects.skip(1)) {
    final duration = results[dialect]![operationName]!;
    if (duration < results[fastest]![operationName]!) {
      fastest = dialect;
    }
    if (duration > results[slowest]![operationName]!) {
      slowest = dialect;
    }
  }

  final fastestMicros = results[fastest]![operationName]!.inMicroseconds;
  final slowestMicros = results[slowest]![operationName]!.inMicroseconds;
  final ratio = fastestMicros == 0 ? 0 : slowestMicros / fastestMicros;

  return OperationResult(
    fastestDialect: _dialectName(fastest),
    slowestDialect: _dialectName(slowest),
    ratio: ratio.toDouble(),
  );
}

Future<void> main() async {
  final results = <KnexDialect, Map<String, Duration>>{};

  for (final dialect in _dialects) {
    final dialectResults = <String, Duration>{};
    for (final operation in _operations) {
      _time(operation.run, dialect, _warmupIterations);
      dialectResults[operation.name] = _time(
        operation.run,
        dialect,
        _iterations,
      );
    }
    results[dialect] = dialectResults;
  }

  print('## SQL Generation Benchmark  (10 000 iterations each)');
  print('');
  print(
    '| Dialect    | SELECT simple | SELECT complex | INSERT | UPDATE | DELETE | JOIN   | Subquery |',
  );
  print(
    '|------------|--------------|----------------|--------|--------|--------|--------|----------|',
  );
  for (final dialect in _dialects) {
    final row = results[dialect]!;
    print(
      '| ${_dialectName(dialect).padRight(10)} '
      '| ${_cell(_formatPerOp(row['SELECT simple']!), 13)} '
      '| ${_cell(_formatPerOp(row['SELECT complex']!), 14)} '
      '| ${_cell(_formatPerOp(row['INSERT']!), 6)} '
      '| ${_cell(_formatPerOp(row['UPDATE']!), 6)} '
      '| ${_cell(_formatPerOp(row['DELETE']!), 6)} '
      '| ${_cell(_formatPerOp(row['JOIN']!), 6)} '
      '| ${_cell(_formatPerOp(row['Subquery']!), 8)} |',
    );
  }

  print('');
  print('## Overhead vs fastest dialect');
  print('');
  print('| Operation      | Fastest | Slowest | Ratio |');
  print('|----------------|---------|---------|-------|');
  for (final operation in _operations) {
    final result = _operationResult(results, operation.name);
    print(
      '| ${operation.name.padRight(14)} '
      '| ${result.fastestDialect.padRight(7)} '
      '| ${result.slowestDialect.padRight(7)} '
      '| ${result.ratio.toStringAsFixed(1)}x  |',
    );
  }

  if (_lastSql == null) {
    throw StateError('benchmark produced no SQL');
  }
}
