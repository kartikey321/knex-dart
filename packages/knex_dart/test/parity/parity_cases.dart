/// Dialect-agnostic query corpus for the differential parity harness.
///
/// Each entry mirrors — by the SAME id — a builder in `tool/parity/run_js.mjs`.
/// The builder is dialect-agnostic: it receives a dialect name and constructs
/// the query via [KnexQuery.forClient]. `parity_test.dart` runs each builder
/// for every dialect the JS side emitted and asserts the compiled SQL/bindings
/// match knex.js (modulo documented per-dialect normalization).
///
/// To add coverage, add a case here AND in run_js.mjs under the same id, then
/// regenerate the fixtures.
library;

import 'package:knex_dart/knex_dart.dart';

/// Builds a fresh dialect-scoped query builder.
QueryBuilder _qb(String dialect) => KnexQuery.forClient(dialect).queryBuilder();

typedef ParityCase = SqlString Function(String dialect);

final Map<String, ParityCase> parityCases = {
  // WHERE — basics
  'where/eq-string': (d) => _qb(d).table('users').where('status', 'active').toSQL(),
  'where/eq-number': (d) => _qb(d).table('users').where('age', 25).toSQL(),
  'where/op-gt': (d) => _qb(d).table('users').where('age', '>', 18).toSQL(),
  'where/op-lte': (d) => _qb(d).table('users').where('age', '<=', 65).toSQL(),
  'where/and-chain': (d) => _qb(d).table('users').where('a', 1).where('b', 2).toSQL(),
  'where/or': (d) => _qb(d).table('users').where('a', 1).orWhere('b', 2).toSQL(),
  'where/null': (d) => _qb(d).table('users').where('deleted_at', null).toSQL(),
  'where/not-null': (d) => _qb(d).table('users').whereNotNull('email').toSQL(),
  'where/in': (d) => _qb(d).table('users').whereIn('id', [1, 2, 3]).toSQL(),
  'where/not-in': (d) => _qb(d).table('users').whereNotIn('id', [1, 2]).toSQL(),
  'where/or-in': (d) =>
      _qb(d).table('users').where('a', 1).orWhereIn('role', ['x', 'y']).toSQL(),
  'where/between': (d) => _qb(d).table('users').whereBetween('age', [18, 65]).toSQL(),
  'where/grouped': (d) => _qb(d)
      .table('users')
      .where('a', 1)
      .where((q) => q.where('b', 2).orWhere('c', 3))
      .toSQL(),
  'where/subquery-in': (d) => _qb(d)
      .table('users')
      .whereIn(
        'id',
        _qb(d).table('orders').select(['user_id']).where('total', '>', 100),
      )
      .toSQL(),

  // SELECT / ORDER / LIMIT
  'select/columns': (d) => _qb(d).table('users').select(['id', 'name']).toSQL(),
  'select/orderby-multi': (d) =>
      _qb(d).table('users').orderBy('a').orderBy('b', 'desc').toSQL(),
  'select/limit-offset': (d) => _qb(d).table('users').limit(10).offset(5).toSQL(),

  // JOINs
  'join/inner': (d) =>
      _qb(d).table('a').join('b', 'a.id', 'b.a_id').select(['*']).toSQL(),
  'join/left': (d) =>
      _qb(d).table('a').leftJoin('b', 'a.id', 'b.a_id').select(['*']).toSQL(),

  // DML
  'insert/single': (d) =>
      _qb(d).table('users').insert({'email': 'a@b.com', 'name': 'Alice'}).toSQL(),
  'insert/multi-ragged': (d) => _qb(d).table('t').insert([
        {'a': 1, 'b': 2},
        {'a': 3, 'c': 4},
      ]).toSQL(),
  'update/set': (d) =>
      _qb(d).table('users').where('id', 2).update({'name': 'Bob'}).toSQL(),
  'delete/where': (d) => _qb(d).table('users').where('id', 2).delete().toSQL(),

  // UNION / CTE
  'union/two': (d) => _qb(d)
      .table('a')
      .select(['id'])
      .where('x', 1)
      .union([_qb(d).table('b').select(['id']).where('y', 2)])
      .toSQL(),
  'cte/select': (d) => _qb(d)
      .table('t')
      .withQuery(
        'recent',
        _qb(d).table('src').select(['id']).where('flag', true),
      )
      .select(['*'])
      .toSQL(),

  // Capability-varying
  'upsert/merge': (d) => _qb(d)
      .table('users')
      .insert({'email': 'a@b.com', 'name': 'Alice'})
      .onConflict('email')
      .merge()
      .toSQL(),
  'returning/insert': (d) =>
      _qb(d).table('users').insert({'email': 'a@b.com'}).returning(['id']).toSQL(),

  // Batch 2 — aggregates, grouping, distinct, counters, set-ops
  'where/not': (d) => _qb(d).table('users').whereNot('status', 'banned').toSQL(),
  'select/distinct': (d) => _qb(d).table('users').distinct(['name']).toSQL(),
  'select/desc': (d) => _qb(d).table('users').orderBy('created_at', 'desc').toSQL(),
  'agg/count-col': (d) => _qb(d).table('t').count('id').toSQL(),
  'agg/sum': (d) => _qb(d).table('t').sum('amount').toSQL(),
  'agg/min-max': (d) => _qb(d).table('t').min('lo').max('hi').toSQL(),
  'having/basic': (d) => _qb(d).table('t').groupBy('cat').having('cnt', '>', 1).toSQL(),
  'update/increment': (d) => _qb(d).table('t').where('id', 1).increment('views', 5).toSQL(),
  'delete/all': (d) => _qb(d).table('users').delete().toSQL(),
  'union/all': (d) => _qb(d)
      .table('a')
      .select(['id'])
      .unionAll([_qb(d).table('b').select(['id'])])
      .toSQL(),

  // Known-divergence probe
  'jsonb/qmark-op': (d) => _qb(d).table('t').where('tags', '?', 'urgent').toSQL(),
};
