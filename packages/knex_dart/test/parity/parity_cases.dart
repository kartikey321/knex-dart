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

  // Batch 3 — nested subqueries, EXISTS, UNION/INTERSECT, CTEs, window
  // functions, DML with RETURNING/onConflict. Mirrors run_js.mjs 1:1 by id;
  // shapes mined from knex.js's test/unit/query/builder.js.

  // ── Subqueries (select / where / from, incl. 2+ level nesting) ──────────
  'subquery/from-aliased': (d) => _qb(d)
      .table(_qb(d).table('foo').select(['*']).as('bar'))
      .join('baz', 'foo.id', 'bar.foo_id')
      .toSQL(),
  'subquery/where-scalar': (d) => _qb(d)
      .table('users')
      .where('id', '=', _qb(d).table('users').select(['id']).where('email', 'bar'))
      .toSQL(),
  'subquery/where-scalar-callback': (d) => _qb(d)
      .table('users')
      .where('id', '=', (QueryBuilder qb) {
        qb.select([_qb(d).client.raw('max(id)')]).table('users').where('email', '=', 'bar');
      })
      .toSQL(),
  'subquery/select-scalar': (d) => _qb(d)
      .table('employee as e')
      .select(['e.lastname', 'e.salary'])
      .select([
        _qb(d)
            .table('employee')
            .select(['avg(salary)'])
            .where(_qb(d).client.raw('dept_no = e.dept_no'))
            .as('avg_sal_dept'),
      ])
      .where('dept_no', '=', 'e.dept_no')
      .toSQL(),
  'subquery/select-first-as': (d) => _qb(d)
      .table('employee as e')
      .select([
        'e.lastname',
        'e.salary',
        _qb(d)
            .first('salary')
            .table('employee')
            .where(_qb(d).client.raw('dept_no = e.dept_no'))
            .orderBy('salary', 'desc')
            .as('top_dept_salary'),
      ])
      .where('dept_no', '=', 'e.dept_no')
      .toSQL(),
  'subquery/from-basic-alias': (d) => _qb(d)
      .table(
        _qb(d)
            .table('orders')
            .select([_qb(d).client.raw('? as f', ['inner raw select'])])
            .as('g'),
      )
      .select([_qb(d).client.raw('?', ['outer raw select']), 'g.f'])
      .where('g.secret', 123)
      .toSQL(),
  'subquery/from-nested-2level': (d) => _qb(d)
      .table(
        _qb(d)
            .table(
              _qb(d).table('inner_t').select(['*']).where('x', 1).as('mid'),
            )
            .select(['*'])
            .as('outer_alias'),
      )
      .select(['*'])
      .toSQL(),
  'subquery/where-in-2level': (d) => _qb(d)
      .table('users')
      .whereIn(
        'id',
        _qb(d)
            .table('orders')
            .select(['user_id'])
            .whereIn(
              'product_id',
              _qb(d).table('products').select(['id']).where('active', true),
            ),
      )
      .toSQL(),

  // ── CTEs ──────────────────────────────────────────────────────────────
  'cte/nested': (d) {
    final withSubClause = _qb(d).select(['foo']).table('users').as('baz');
    final withClause = _qb(d)
        .withQuery('withSubClause', withSubClause)
        .select(['*'])
        .table('withSubClause');
    return _qb(d)
        .withQuery('withClause', withClause)
        .select(['*'])
        .table('withClause')
        .toSQL();
  },
  'cte/chained-siblings': (d) => _qb(d)
      .withQuery('firstWithClause', _qb(d).select(['foo']).table('users'))
      .withQuery('secondWithClause', _qb(d).select(['bar']).table('users'))
      .select(['*'])
      .table('secondWithClause')
      .toSQL(),
  'cte/raw': (d) => _qb(d)
      .withQuery('withRawClause', _qb(d).client.raw('select "foo" as "baz" from "users"'))
      .select(['*'])
      .table('withRawClause')
      .toSQL(),
  'cte/recursive-nested-chained': (d) {
    final firstSub = _qb(d).select(['foo']).table('users').as('foz');
    final firstWith = _qb(d)
        .withRecursive('firstWithSubClause', firstSub)
        .select(['*'])
        .table('firstWithSubClause');
    final secondSub = _qb(d).select(['bar']).table('users').as('baz');
    final secondWith = _qb(d)
        .withRecursive('secondWithSubClause', secondSub)
        .select(['*'])
        .table('secondWithSubClause');
    return _qb(d)
        .withRecursive('firstWithClause', firstWith)
        .withRecursive('secondWithClause', secondWith)
        .select(['*'])
        .table('secondWithClause')
        .toSQL();
  },
  'cte/insert-multi-source': (d) => _qb(d)
      .withQuery(
        'withClause',
        _qb(d).select(['foo']).table('users').where('name', 'bob'),
      )
      .table('users')
      .insert([
        {'email': 'thisMail', 'name': 'sam'},
        {'email': 'thatMail', 'name': 'jack'},
      ])
      .toSQL(),
  'cte/update-source': (d) => _qb(d)
      .withQuery(
        'updated_group',
        _qb(d)
            .table('group')
            .update({'group_name': 'bar'})
            .where('group_id', 1)
            .returning(['group_id']),
      )
      .table('user')
      .update({'name': 'foo'})
      .where('group_id', 1)
      .toSQL(),
  'cte/delete-source': (d) => _qb(d)
      .withQuery(
        'delete1',
        _qb(d).table('accounts').delete().where('id', 1),
      )
      .table('accounts')
      .toSQL(),

  // ── EXISTS / NOT EXISTS ──────────────────────────────────────────────────
  'exists/where': (d) => _qb(d)
      .table('orders')
      .select(['*'])
      .whereExists((qb) {
        qb.select(['*']).table('products').where(
          'products.id',
          '=',
          _qb(d).client.raw('"orders"."id"'),
        );
      })
      .toSQL(),
  'exists/where-not': (d) => _qb(d)
      .table('orders')
      .select(['*'])
      .whereNotExists((qb) {
        qb.select(['*']).table('products').where(
          'products.id',
          '=',
          _qb(d).client.raw('"orders"."id"'),
        );
      })
      .toSQL(),
  'exists/or-where': (d) => _qb(d)
      .table('orders')
      .select(['*'])
      .where('id', '=', 1)
      .orWhereExists((qb) {
        qb.select(['*']).table('products').where(
          'products.id',
          '=',
          _qb(d).client.raw('"orders"."id"'),
        );
      })
      .toSQL(),
  'exists/or-where-not': (d) => _qb(d)
      .table('orders')
      .select(['*'])
      .where('id', '=', 1)
      .orWhereNotExists((qb) {
        qb.select(['*']).table('products').where(
          'products.id',
          '=',
          _qb(d).client.raw('"orders"."id"'),
        );
      })
      .toSQL(),
  'exists/wrapped-or': (d) => _qb(d)
      .table('orders')
      .select(['*'])
      .where('status', 'shipped')
      .where((qb) {
        qb
            .whereExists((inner) {
              inner.select(['*']).table('products').where(
                'products.id',
                '=',
                _qb(d).client.raw('"orders"."id"'),
              );
            })
            .orWhereExists((inner) {
              inner.select(['*']).table('refunds').where(
                'refunds.order_id',
                '=',
                _qb(d).client.raw('"orders"."id"'),
              );
            });
      })
      .toSQL(),
  'exists/with-select-subquery': (d) => _qb(d)
      .table('orders')
      .select([
        '*',
        _qb(d)
            .table('order_meta')
            .select(['value'])
            .where('order_meta.order_id', '=', _qb(d).client.raw('"orders"."id"'))
            .as('meta_value'),
      ])
      .whereExists((qb) {
        qb.select(['*']).table('products').where(
          'products.id',
          '=',
          _qb(d).client.raw('"orders"."id"'),
        );
      })
      .toSQL(),

  // ── UNION / INTERSECT / EXCEPT ───────────────────────────────────────────
  'union/three-way': (d) => _qb(d)
      .table('a')
      .select(['id'])
      .where('x', 1)
      .union([
        _qb(d).table('b').select(['id']).where('y', 2),
        _qb(d).table('c').select(['id']).where('z', 3),
      ])
      .toSQL(),
  'union/array-callbacks': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .where('id', 1)
      .union([
        (QueryBuilder qb) {
          qb.table('users').select(['*']).where('id', 2);
        },
        (QueryBuilder qb) {
          qb.table('users').select(['*']).where('id', 3);
        },
      ])
      .toSQL(),
  'union/order-limit-outer': (d) => _qb(d)
      .table('a')
      .select(['id', 'name'])
      .where('x', 1)
      .union([_qb(d).table('b').select(['id', 'name']).where('y', 2)])
      .orderBy('name')
      .limit(10)
      .toSQL(),
  'intersect/basic': (d) => _qb(d)
      .table('a')
      .select(['*'])
      .where('id', '=', 1)
      .intersect([_qb(d).table('b').select(['*']).where('id', '=', 2)])
      .toSQL(),
  'intersect/three-way': (d) => _qb(d)
      .table('a')
      .select(['id'])
      .intersect([
        _qb(d).table('b').select(['id']),
        _qb(d).table('c').select(['id']),
      ])
      .toSQL(),
  'except/basic': (d) => _qb(d)
      .table('a')
      .select(['id'])
      .except([_qb(d).table('b').select(['id'])])
      .toSQL(),
  'union/all-order-limit': (d) => _qb(d)
      .table('a')
      .select(['id'])
      .where('x', 1)
      .unionAll([_qb(d).table('b').select(['id']).where('y', 2)])
      .orderBy('id', 'desc')
      .limit(5)
      .offset(2)
      .toSQL(),

  // ── Window / analytic functions ──────────────────────────────────────────
  'window/rank-string-partition': (d) => _qb(d)
      .table('accounts')
      .select(['*'])
      .rank('alias_name', 'email', 'firstName')
      .toSQL(),
  'window/rank-array-both': (d) => _qb(d)
      .table('accounts')
      .select(['*'])
      .rank('alias_name', ['email', 'address'], ['firstName', 'lastName'])
      .toSQL(),
  'window/dense-rank-callback': (d) => _qb(d)
      .table('accounts')
      .select(['*'])
      .denseRank('test_alias', (a) => a.orderBy('email').partitionBy('address'))
      .toSQL(),
  'window/dense-rank-callback-chains': (d) => _qb(d)
      .table('accounts')
      .select(['*'])
      .denseRank(
        'test_alias',
        (a) => a
            .orderBy('email')
            .partitionBy('address')
            .partitionBy('phone')
            .orderBy('name'),
      )
      .toSQL(),
  'window/row-number-array': (d) => _qb(d)
      .table('accounts')
      .select(['*'])
      .rowNumber('alias_name', ['email', 'address'], ['firstName', 'lastName'])
      .toSQL(),
  'window/rank-raw': (d) => _qb(d)
      .table('accounts')
      .select(['*'])
      .rank(null, _qb(d).client.raw('partition by address order by email'))
      .toSQL(),
  'window/chained-multiple': (d) => _qb(d)
      .table('accounts')
      .select(['*'])
      .denseRank('first_alias', 'email')
      .denseRank('second_alias', 'address')
      .toSQL(),
  'window/dense-rank-raw-alias': (d) => _qb(d)
      .table('accounts')
      .select(['*'])
      .denseRank('test_alias', _qb(d).client.raw('partition by address order by email'))
      .toSQL(),
  'window/rank-then-orderby': (d) => _qb(d)
      .table('accounts')
      .select(['*'])
      .rank('rnk', 'salary')
      .where('dept', '=', 'eng')
      .orderBy('rnk')
      .toSQL(),

  // ── DML with RETURNING / onConflict ──────────────────────────────────────
  'dml/onconflict-ignore': (d) => _qb(d)
      .table('users')
      .insert([
        {'email': 'foo'},
        {'email': 'bar'},
      ])
      .onConflict('email')
      .ignore()
      .toSQL(),
  'dml/onconflict-composite-ignore': (d) => _qb(d)
      .table('users')
      .insert([
        {'org': 'acme-inc', 'email': 'foo'},
      ])
      .onConflict(['org', 'email'])
      .ignore()
      .toSQL(),
  'dml/onconflict-merge-explicit': (d) => _qb(d)
      .table('users')
      .insert([
        {'email': 'foo', 'name': 'taylor'},
        {'email': 'bar', 'name': 'dayle'},
      ])
      .onConflict('email')
      .merge({'name': 'overidden'})
      .toSQL(),
  'dml/onconflict-merge-implicit-multi': (d) => _qb(d)
      .table('users')
      .insert([
        {'email': 'foo', 'name': 'taylor'},
        {'email': 'bar', 'name': 'dayle'},
      ])
      .onConflict('email')
      .merge()
      .toSQL(),
  'dml/onconflict-raw-target': (d) => _qb(d)
      .table('users')
      .insert([
        {'email': 'foo'},
        {'email': 'bar'},
      ])
      .onConflict(_qb(d).client.raw('(value) WHERE deleted_at IS NULL'))
      .ignore()
      .toSQL(),
  'dml/onconflict-merge-where': (d) => _qb(d)
      .table('users')
      .insert({'email': 'foo', 'name': 'taylor'})
      .onConflict('email')
      .merge()
      .where('email', 'foo2')
      .toSQL(),
  'dml/returning-multi-insert': (d) => _qb(d)
      .table('users')
      .insert([
        {'email': 'a'},
        {'email': 'b'},
      ])
      .returning(['id', 'email'])
      .toSQL(),
  'dml/returning-update': (d) => _qb(d)
      .table('users')
      .where('id', 1)
      .update({'name': 'Bob'})
      .returning(['*'])
      .toSQL(),
  'dml/returning-delete': (d) => _qb(d)
      .table('users')
      .where('id', 1)
      .delete()
      .returning(['id'])
      .toSQL(),

  // Batch 4 — mined from knex.js test/unit/query/builder.js lines 385-1917.
  // Mirrors run_js.mjs 1:1 by id.
  'select/star': (d) => _qb(d).table('users').select(['*']).toSQL(),
  'select/multi-calls': (d) => _qb(d)
      .table('users')
      .select(['foo'])
      .select(['bar'])
      .select(['baz', 'boom'])
      .toSQL(),
  'select/distinct-then-select': (d) =>
      _qb(d).table('users').distinct().select(['foo', 'bar']).toSQL(),
  'select/alias-map': (d) => _qb(d).table('users').select({'bar': 'foo'}).toSQL(),
  'select/alias-array-mixed': (d) => _qb(d)
      .table('users')
      .select([
        'baz',
        {'bar': 'foo'},
      ])
      .toSQL(),
  'select/old-style-alias': (d) =>
      _qb(d).table('users').select(['foo as bar']).toSQL(),
  'select/alias-trim-spaces': (d) =>
      _qb(d).table('users').select([' foo   as bar ']).toSQL(),
  'select/alias-case-insensitive': (d) =>
      _qb(d).table('users').select([' foo   aS bar ']).toSQL(),
  'select/alias-dotted': (d) =>
      _qb(d).table('users').select(['foo as bar.baz']).toSQL(),
  'table/dotted-schema': (d) => _qb(d).table('public.users').select(['*']).toSQL(),

  'clear/select-basic': (d) =>
      _qb(d).table('users').select(['id', 'email']).clearSelect().toSQL(),
  'clear/select-then-reselect': (d) => _qb(d)
      .table('users')
      .select(['id'])
      .clearSelect()
      .select(['email'])
      .toSQL(),
  'clear/where-basic': (d) => _qb(d)
      .table('users')
      .select(['id'])
      .where('id', '=', 1)
      .clearWhere()
      .toSQL(),
  'clear/where-then-rewhere': (d) => _qb(d)
      .table('users')
      .select(['id'])
      .where('id', '=', 1)
      .clearWhere()
      .where('id', '=', 2)
      .toSQL(),
  'clear/group-basic': (d) => _qb(d).table('users').groupBy('name').clearGroup().toSQL(),
  'clear/group-then-regroup': (d) =>
      _qb(d).table('users').groupBy('name').clearGroup().groupBy('id').toSQL(),
  'clear/order-basic': (d) =>
      _qb(d).table('users').orderBy('name', 'desc').clearOrder().toSQL(),
  'clear/order-then-reorder': (d) => _qb(d)
      .table('users')
      .orderBy('name', 'desc')
      .clearOrder()
      .orderBy('id', 'asc')
      .toSQL(),
  'clear/having-then-rehaving': (d) => _qb(d)
      .table('users')
      .having('id', '>', 100)
      .clearHaving()
      .having('id', '>', 10)
      .toSQL(),
  'clear/counters': (d) => _qb(d)
      .table('users')
      .where('id', '=', 1)
      .update({'email': 'foo@bar.com'})
      .increment('balance', 10)
      .clearCounters()
      .decrement('value', 50)
      .clearCounters()
      .toSQL(),
};
