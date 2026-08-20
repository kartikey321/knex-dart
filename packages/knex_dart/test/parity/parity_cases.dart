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
  'where/eq-string': (d) =>
      _qb(d).table('users').where('status', 'active').toSQL(),
  'where/eq-number': (d) => _qb(d).table('users').where('age', 25).toSQL(),
  'where/op-gt': (d) => _qb(d).table('users').where('age', '>', 18).toSQL(),
  'where/op-lte': (d) => _qb(d).table('users').where('age', '<=', 65).toSQL(),
  'where/and-chain': (d) =>
      _qb(d).table('users').where('a', 1).where('b', 2).toSQL(),
  'where/or': (d) =>
      _qb(d).table('users').where('a', 1).orWhere('b', 2).toSQL(),
  'where/null': (d) => _qb(d).table('users').where('deleted_at', null).toSQL(),
  'where/explicit-null': (d) =>
      _qb(d).table('users').where('deleted_at', '=', null).toSQL(),
  'where/not-null': (d) => _qb(d).table('users').whereNotNull('email').toSQL(),
  'where/in': (d) => _qb(d).table('users').whereIn('id', [1, 2, 3]).toSQL(),
  'where/not-in': (d) => _qb(d).table('users').whereNotIn('id', [1, 2]).toSQL(),
  'where/or-in': (d) =>
      _qb(d).table('users').where('a', 1).orWhereIn('role', ['x', 'y']).toSQL(),
  'where/between': (d) =>
      _qb(d).table('users').whereBetween('age', [18, 65]).toSQL(),
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
  'where/in-multi-column-single-tuple': (d) => _qb(d)
      .table('users')
      .whereIn(
        ['a', 'b'],
        [
          [1, 2],
        ],
      )
      .toSQL(),

  // SELECT / ORDER / LIMIT
  'select/columns': (d) => _qb(d).table('users').select(['id', 'name']).toSQL(),
  'select/orderby-multi': (d) =>
      _qb(d).table('users').orderBy('a').orderBy('b', 'desc').toSQL(),
  'select/orderby-raw-direction': (d) => _qb(d)
      .table('users')
      .orderBy('name', _qb(d).client.raw('desc nulls last'))
      .toSQL(),
  'select/limit-offset': (d) =>
      _qb(d).table('users').limit(10).offset(5).toSQL(),

  // JOINs
  'join/inner': (d) =>
      _qb(d).table('a').join('b', 'a.id', 'b.a_id').select(['*']).toSQL(),
  'join/left': (d) =>
      _qb(d).table('a').leftJoin('b', 'a.id', 'b.a_id').select(['*']).toSQL(),

  // DML
  'insert/single': (d) => _qb(
    d,
  ).table('users').insert({'email': 'a@b.com', 'name': 'Alice'}).toSQL(),
  'insert/multi-ragged': (d) => _qb(d).table('t').insert([
    {'a': 1, 'b': 2},
    {'a': 3, 'c': 4},
  ]).toSQL(),
  'update/set': (d) =>
      _qb(d).table('users').where('id', 2).update({'name': 'Bob'}).toSQL(),
  'delete/where': (d) => _qb(d).table('users').where('id', 2).delete().toSQL(),

  // UNION / CTE
  'union/two': (d) => _qb(d).table('a').select(['id']).where('x', 1).union([
    _qb(d).table('b').select(['id']).where('y', 2),
  ]).toSQL(),
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
  'returning/insert': (d) => _qb(
    d,
  ).table('users').insert({'email': 'a@b.com'}).returning(['id']).toSQL(),

  // Batch 2 — aggregates, grouping, distinct, counters, set-ops
  'where/not': (d) =>
      _qb(d).table('users').whereNot('status', 'banned').toSQL(),
  'select/distinct': (d) => _qb(d).table('users').distinct(['name']).toSQL(),
  'select/desc': (d) =>
      _qb(d).table('users').orderBy('created_at', 'desc').toSQL(),
  'agg/count-col': (d) => _qb(d).table('t').count('id').toSQL(),
  'agg/sum': (d) => _qb(d).table('t').sum('amount').toSQL(),
  'agg/min-max': (d) => _qb(d).table('t').min('lo').max('hi').toSQL(),
  'having/basic': (d) =>
      _qb(d).table('t').groupBy('cat').having('cnt', '>', 1).toSQL(),
  'update/increment': (d) =>
      _qb(d).table('t').where('id', 1).increment('views', 5).toSQL(),
  'delete/all': (d) => _qb(d).table('users').delete().toSQL(),
  'delete/limit-mysql': (d) =>
      _qb(d).table('users').where('id', '>', 1).delete().limit(1).toSQL(),
  'union/all': (d) => _qb(d).table('a').select(['id']).unionAll([
    _qb(d).table('b').select(['id']),
  ]).toSQL(),

  // Known-divergence probe
  'jsonb/qmark-op': (d) =>
      _qb(d).table('t').where('tags', '?', 'urgent').toSQL(),

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
      .where(
        'id',
        '=',
        _qb(d).table('users').select(['id']).where('email', 'bar'),
      )
      .toSQL(),
  'subquery/where-scalar-callback': (d) =>
      _qb(d).table('users').where('id', '=', (QueryBuilder qb) {
        qb
            .select([_qb(d).client.raw('max(id)')])
            .table('users')
            .where('email', '=', 'bar');
      }).toSQL(),
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
            .select([
              _qb(d).client.raw('? as f', ['inner raw select']),
            ])
            .as('g'),
      )
      .select([
        _qb(d).client.raw('?', ['outer raw select']),
        'g.f',
      ])
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
      .withQuery(
        'withRawClause',
        _qb(d).client.raw('select "foo" as "baz" from "users"'),
      )
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
      .withQuery('delete1', _qb(d).table('accounts').delete().where('id', 1))
      .table('accounts')
      .toSQL(),

  // ── EXISTS / NOT EXISTS ──────────────────────────────────────────────────
  'exists/where': (d) => _qb(d).table('orders').select(['*']).whereExists((qb) {
    qb
        .select(['*'])
        .table('products')
        .where('products.id', '=', _qb(d).client.raw('"orders"."id"'));
  }).toSQL(),
  'exists/where-not': (d) =>
      _qb(d).table('orders').select(['*']).whereNotExists((qb) {
        qb
            .select(['*'])
            .table('products')
            .where('products.id', '=', _qb(d).client.raw('"orders"."id"'));
      }).toSQL(),
  'exists/or-where': (d) => _qb(d)
      .table('orders')
      .select(['*'])
      .where('id', '=', 1)
      .orWhereExists((qb) {
        qb
            .select(['*'])
            .table('products')
            .where('products.id', '=', _qb(d).client.raw('"orders"."id"'));
      })
      .toSQL(),
  'exists/or-where-not': (d) => _qb(d)
      .table('orders')
      .select(['*'])
      .where('id', '=', 1)
      .orWhereNotExists((qb) {
        qb
            .select(['*'])
            .table('products')
            .where('products.id', '=', _qb(d).client.raw('"orders"."id"'));
      })
      .toSQL(),
  'exists/wrapped-or': (d) => _qb(d)
      .table('orders')
      .select(['*'])
      .where('status', 'shipped')
      .where((qb) {
        qb
            .whereExists((inner) {
              inner
                  .select(['*'])
                  .table('products')
                  .where(
                    'products.id',
                    '=',
                    _qb(d).client.raw('"orders"."id"'),
                  );
            })
            .orWhereExists((inner) {
              inner
                  .select(['*'])
                  .table('refunds')
                  .where(
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
            .where(
              'order_meta.order_id',
              '=',
              _qb(d).client.raw('"orders"."id"'),
            )
            .as('meta_value'),
      ])
      .whereExists((qb) {
        qb
            .select(['*'])
            .table('products')
            .where('products.id', '=', _qb(d).client.raw('"orders"."id"'));
      })
      .toSQL(),

  // ── UNION / INTERSECT / EXCEPT ───────────────────────────────────────────
  'union/three-way': (d) =>
      _qb(d).table('a').select(['id']).where('x', 1).union([
        _qb(d).table('b').select(['id']).where('y', 2),
        _qb(d).table('c').select(['id']).where('z', 3),
      ]).toSQL(),
  'union/array-callbacks': (d) =>
      _qb(d).table('users').select(['*']).where('id', 1).union([
        (QueryBuilder qb) {
          qb.table('users').select(['*']).where('id', 2);
        },
        (QueryBuilder qb) {
          qb.table('users').select(['*']).where('id', 3);
        },
      ]).toSQL(),
  'union/order-limit-outer': (d) => _qb(d)
      .table('a')
      .select(['id', 'name'])
      .where('x', 1)
      .union([
        _qb(d).table('b').select(['id', 'name']).where('y', 2),
      ])
      .orderBy('name')
      .limit(10)
      .toSQL(),
  'intersect/basic': (d) =>
      _qb(d).table('a').select(['*']).where('id', '=', 1).intersect([
        _qb(d).table('b').select(['*']).where('id', '=', 2),
      ]).toSQL(),
  'intersect/three-way': (d) => _qb(d).table('a').select(['id']).intersect([
    _qb(d).table('b').select(['id']),
    _qb(d).table('c').select(['id']),
  ]).toSQL(),
  'except/basic': (d) => _qb(d).table('a').select(['id']).except([
    _qb(d).table('b').select(['id']),
  ]).toSQL(),
  'union/all-order-limit': (d) => _qb(d)
      .table('a')
      .select(['id'])
      .where('x', 1)
      .unionAll([
        _qb(d).table('b').select(['id']).where('y', 2),
      ])
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
      .denseRank(
        'test_alias',
        _qb(d).client.raw('partition by address order by email'),
      )
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
  'dml/returning-delete': (d) =>
      _qb(d).table('users').where('id', 1).delete().returning(['id']).toSQL(),

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
  'select/alias-map': (d) =>
      _qb(d).table('users').select({'bar': 'foo'}).toSQL(),
  'select/alias-map-multi': (d) =>
      _qb(d).table('users').select({'bar': 'foo', 'baz': 'qux'}).toSQL(),
  'select/alias-array-mixed': (d) => _qb(d).table('users').select([
    'baz',
    {'bar': 'foo'},
  ]).toSQL(),
  'select/old-style-alias': (d) =>
      _qb(d).table('users').select(['foo as bar']).toSQL(),
  'select/alias-trim-spaces': (d) =>
      _qb(d).table('users').select([' foo   as bar ']).toSQL(),
  'select/alias-case-insensitive': (d) =>
      _qb(d).table('users').select([' foo   aS bar ']).toSQL(),
  'select/alias-dotted': (d) =>
      _qb(d).table('users').select(['foo as bar.baz']).toSQL(),
  'table/dotted-schema': (d) =>
      _qb(d).table('public.users').select(['*']).toSQL(),

  'clear/select-basic': (d) =>
      _qb(d).table('users').select(['id', 'email']).clearSelect().toSQL(),
  'clear/select-then-reselect': (d) => _qb(
    d,
  ).table('users').select(['id']).clearSelect().select(['email']).toSQL(),
  'clear/where-basic': (d) => _qb(
    d,
  ).table('users').select(['id']).where('id', '=', 1).clearWhere().toSQL(),
  'clear/where-then-rewhere': (d) => _qb(d)
      .table('users')
      .select(['id'])
      .where('id', '=', 1)
      .clearWhere()
      .where('id', '=', 2)
      .toSQL(),
  'clear/group-basic': (d) =>
      _qb(d).table('users').groupBy('name').clearGroup().toSQL(),
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

  // Batch 2 (HAVING) — mined from knex.js test/unit/query/builder.js lines
  // 3547-5949.

  // ── HAVING ────────────────────────────────────────────────────────────
  'having/nested': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .havingWrapped((q) => q.having('email', '>', 1))
      .toSQL(),
  'having/nested-or': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .havingWrapped(
        (q) => q.having('email', '>', 10).orHaving('email', '=', 7),
      )
      .toSQL(),
  'having/grouped': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .groupBy(['email'])
      .having('email', '>', 1)
      .toSQL(),
  'having/from-alias': (d) => _qb(d)
      .table('users')
      .select(['email as foo_email'])
      .having('foo_email', '>', 1)
      .toSQL(),
  // JS: having(raw(...)) — Dart's having() requires a String column, so this
  // is adapted to havingRaw(), which compiles to identical SQL.
  'having/raw': (d) => _qb(
    d,
  ).table('users').select(['*']).havingRaw('user_foo < user_bar').toSQL(),
  'having/raw-or': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .having('baz', '=', 1)
      .orHavingRaw('user_foo < user_bar')
      .toSQL(),
  'having/null': (d) =>
      _qb(d).table('users').select(['*']).havingNull('baz').toSQL(),
  'having/or-null': (d) => _qb(
    d,
  ).table('users').select(['*']).havingNull('baz').orHavingNull('foo').toSQL(),
  'having/not-null': (d) =>
      _qb(d).table('users').select(['*']).havingNotNull('baz').toSQL(),
  'having/or-not-null': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .havingNotNull('baz')
      .orHavingNotNull('foo')
      .toSQL(),
  'having/exists': (d) => _qb(d).table('users').select(['*']).havingExists((q) {
    q.select(['baz']).table('users');
  }).toSQL(),
  'having/or-exists': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .havingExists((q) {
        q.select(['baz']).table('users');
      })
      .orHavingExists((q) {
        q.select(['foo']).table('users');
      })
      .toSQL(),
  'having/not-exists': (d) =>
      _qb(d).table('users').select(['*']).havingNotExists((q) {
        q.select(['baz']).table('users');
      }).toSQL(),
  'having/or-not-exists': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .havingNotExists((q) {
        q.select(['baz']).table('users');
      })
      .orHavingNotExists((q) {
        q.select(['foo']).table('users');
      })
      .toSQL(),
  'having/between': (d) =>
      _qb(d).table('users').select(['*']).havingBetween('baz', [5, 10]).toSQL(),
  'having/or-between': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .havingBetween('baz', [5, 10])
      .orHavingBetween('baz', [20, 30])
      .toSQL(),
  'having/not-between': (d) => _qb(
    d,
  ).table('users').select(['*']).havingNotBetween('baz', [5, 10]).toSQL(),
  'having/or-not-between': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .havingNotBetween('baz', [5, 10])
      .orHavingNotBetween('baz', [20, 30])
      .toSQL(),
  'having/in': (d) =>
      _qb(d).table('users').select(['*']).havingIn('baz', [5, 10, 37]).toSQL(),
  'having/or-in': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .havingIn('baz', [5, 10, 37])
      .orHavingIn('foo', ['Batman', 'Joker'])
      .toSQL(),
  'having/not-in': (d) => _qb(
    d,
  ).table('users').select(['*']).havingNotIn('baz', [5, 10, 37]).toSQL(),
  'having/or-not-in': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .havingNotIn('baz', [5, 10, 37])
      .orHavingNotIn('foo', ['Batman', 'Joker'])
      .toSQL(),

  // ── Batch 3 (lines 5950-8353) — insert edge cases, update/counter
  // overwrite semantics, locks, joins in DML, misc operators/raw, and
  // denseRank/rank null-alias variants.

  // Insert edge cases
  'insert/ragged-defaults-3col': (d) => _qb(d).table('table').insert([
    {'a': 1},
    {'b': 2},
    {'a': 2, 'c': 3},
  ]).toSQL(),
  'insert/empty-array-noop': (d) => _qb(d).table('users').insert([]).toSQL(),
  'insert/empty-object-returning': (d) =>
      _qb(d).table('users').insert([{}], ['id']).toSQL(),
  'insert/raw-value': (d) => _qb(d).table('users').insert({
    'email': _qb(d).client.raw('CURRENT TIMESTAMP'),
  }).toSQL(),

  // update() basic variations
  'update/two-cols': (d) => _qb(d)
      .update({'email': 'foo', 'name': 'bar'})
      .table('users')
      .where('id', '=', 1)
      .toSQL(),
  'update/null-value': (d) => _qb(d)
      .update({'email': null, 'name': 'bar'})
      .table('users')
      .where('id', 1)
      .toSQL(),
  'update/from-where-then-update': (d) => _qb(d)
      .table('users')
      .where('id', '=', 1)
      .update({'email': 'foo', 'name': 'bar'})
      .toSQL(),
  'update/raw-value': (d) => _qb(d).table('users').where('id', '=', 1).update({
    'email': _qb(d).client.raw('foo'),
    'name': 'bar',
  }).toSQL(),

  // update() + orderBy/limit/join — probing whether they're honored
  'update/orderby-limit': (d) => _qb(d)
      .table('users')
      .where('id', '=', 1)
      .orderBy('foo', 'desc')
      .limit(5)
      .update({'email': 'foo', 'name': 'bar'})
      .toSQL(),
  'update/join-mysql': (d) => _qb(d)
      .table('users')
      .join('orders', 'users.id', 'orders.user_id')
      .where('users.id', '=', 1)
      .update({'email': 'foo', 'name': 'bar'})
      .toSQL(),
  'update/limit-mysql': (d) => _qb(d)
      .table('users')
      .where('users.id', '=', 1)
      .update({'email': 'foo', 'name': 'bar'})
      .limit(1)
      .toSQL(),
  'update/join-mysql-qualified-col': (d) => _qb(d)
      .table('tblPerson')
      .update({'tblPerson.City': 'Boonesville'})
      .join(
        'tblPersonData',
        (j) => j.on('tblPersonData.PersonId', '=', 'tblPerson.PersonId'),
      )
      .where('tblPersonData.DataId', 1)
      .where('tblPerson.PersonId', 5)
      .toSQL(),

  // Batch 4 — mined from knex.js test/unit/query/builder.js lines 8354-end.
  // Mirrors run_js.mjs 1:1 by id.

  // ── Window functions (representative shapes) ────────────────────────────
  'window/rank-callback-orderby-only': (d) => _qb(d)
      .table('accounts')
      .select(['*'])
      .rank(null, (a) => a.orderBy('email'))
      .toSQL(),
  'window/rank-callback-alias-partition': (d) => _qb(d)
      .table('accounts')
      .select(['*'])
      .rank('test_alias', (a) => a.orderBy('email').partitionBy('address'))
      .toSQL(),
  'window/rank-callback-arrays': (d) => _qb(d)
      .table('accounts')
      .select(['*'])
      .rank(
        'test_alias',
        (a) => a.orderBy(['email', 'name']).partitionBy(['address', 'phone']),
      )
      .toSQL(),
  'window/rank-chained-multiple': (d) => _qb(d)
      .table('accounts')
      .select(['*'])
      .rank('first_alias', 'email')
      .rank('second_alias', 'address')
      .toSQL(),
  'window/rank-raw-alias': (d) => _qb(d)
      .table('accounts')
      .select(['*'])
      .rank(
        'test_alias',
        _qb(d).client.raw('partition by address order by email'),
      )
      .toSQL(),
  'window/row-number-no-partition': (d) =>
      _qb(d).table('accounts').select(['*']).rowNumber(null, 'email').toSQL(),

  // ── Insert / subqueries ───────────────────────────────────────────────
  'insert/value-subselect': (d) => _qb(d).table('entries').insert({
    'secret': 123,
    'sequence': _qb(d).table('entries').count('*').where('secret', 123),
  }).toSQL(),
  'subquery/from-no-alias': (d) {
    final subquery = _qb(d).select([
      _qb(d).client.raw('?', ['inner raw select']),
      'bar',
    ]);
    return _qb(d)
        .select([
          _qb(d).client.raw('?', ['outer raw select']),
        ])
        .table(subquery)
        .toSQL();
  },

  // ── select() / where() extras ────────────────────────────────────────
  'select/fromraw': (d) => _qb(
    d,
  ).select(['*']).fromRaw('(select * from users where age > 18)').toSQL(),
  'select/modify-callback': (d) => _qb(d)
      .select(['foo_id'])
      .table('foos')
      .modify((QueryBuilder qb, String table, String fk) {
        qb.leftJoin('bars', '$table.$fk', 'bars.id').select(['bars.*']);
      }, ['foos', 'bar_id'])
      .toSQL(),
  'where/empty-callback': (d) =>
      _qb(d).select(['foo']).table('tbl').where((q) {}).toSQL(),
  'where/not-raw': (d) => _qb(
    d,
  ).table('testtable').whereNot(_qb(d).client.raw('is_active')).toSQL(),
  'where/or-raw': (d) => _qb(
    d,
  ).table('users').where('a', 1).orWhere(_qb(d).client.raw('b = 2')).toSQL(),
  'where/named-binding-array': (d) => _qb(d)
      .select(['*'])
      .table('users')
      .whereIn(
        'id',
        _qb(d).client.raw('select (:test)', {
          'test': [1, 2, 3],
        }),
      )
      .toSQL(),
  'where/named-binding-identifier': (d) => _qb(d)
      .select(['*'])
      .table('users')
      .where(
        _qb(d).client.raw(':name: = :thisGuy or :name: = :otherGuy', {
          'name': 'users.name',
          'thisGuy': 'Bob',
          'otherGuy': 'Jay',
        }),
      )
      .toSQL(),
  'jsonb/pipe-op': (d) =>
      _qb(d).table('users').select(['*']).where('id', '?|', 1).toSQL(),
  'jsonb/amp-op': (d) =>
      _qb(d).table('users').select(['*']).where('id', '?&', 1).toSQL(),
  'select/numeric-literal': (d) => _qb(d).select([0]).toSQL(),

  // ── CTE + simple UPDATE/DELETE ───────────────────────────────────────
  'cte/update-simple': (d) => _qb(d)
      .withQuery('withClause', _qb(d).select(['foo']).table('users'))
      .update({'foo': 'updatedFoo'})
      .where('email', '=', 'foo')
      .table('users')
      .toSQL(),
  'cte/delete-simple': (d) => _qb(d)
      .withQuery('withClause', _qb(d).select(['email']).table('users'))
      .delete()
      .where('foo', '=', 'updatedFoo')
      .table('users')
      .toSQL(),

  // ── knex.ref() ────────────────────────────────────────────────────────
  'ref/where-column': (d) => _qb(d)
      .table('sometable')
      .where(
        'sometable.column',
        _qb(d).client.ref('someothertable.someothercolumn'),
      )
      .select(['*'])
      .toSQL(),
  'ref/select-alias': (d) => _qb(d).table('sometable').select([
    'one',
    _qb(d).client.ref('sometable.two').as('Two'),
  ]).toSQL(),

  // ── .first() chained onto a non-select method — must throw ────────────
  'errors/first-on-update': (d) =>
      _qb(d).table('sometable').update({'column': 'value'}).first().toSQL(),
  'errors/first-on-insert': (d) =>
      _qb(d).table('sometable').insert({'column': 'value'}).first().toSQL(),
  'errors/first-on-delete': (d) =>
      _qb(d).table('sometable').delete().first().toSQL(),

  // ── DELETE + JOIN ─────────────────────────────────────────────────────
  'delete/join-single': (d) => _qb(d)
      .table('users')
      .delete()
      .join('photos', 'photos.id', 'users.id')
      .where('user.email', 'mock@example.com')
      .toSQL(),
  'delete/join-multi': (d) => _qb(d)
      .table('users')
      .delete()
      .join('photos', 'photos.id', 'users.id')
      .join('docs', 'docs.id', 'users.id')
      .where('user.email', 'mock@example.com')
      .toSQL(),
  'delete/join-no-where': (d) => _qb(
    d,
  ).table('users').delete().join('photos', 'photos.id', 'users.id').toSQL(),
  'delete/join-oncallback-where': (d) => _qb(d)
      .table('users')
      .where('activated', false)
      .join(
        'accounts',
        (j) => j
            .on('accounts.id', 'users.account_id')
            .andOn('accounts.user_id', 'users.id'),
      )
      .delete()
      .toSQL(),

  // ── JSON where family (adapted: knex-dart has no "Not" variant of these,
  // so both sides use the plain/OR forms only) ────────────────────────────
  'json/where-object': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .whereJsonObject('address', {'street': 'street1', 'number': 5})
      .orWhereJsonObject('address', {'street': 'street2', 'number': 7})
      .toSQL(),
  'json/where-path': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .whereJsonPath('address', r'$.street.number', '>', 5)
      .orWhereJsonPath('address', r'$.street.number', '<', 8)
      .toSQL(),
  'json/where-superset-object': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .whereJsonSupersetOf('address', {'test': 'value'})
      .orWhereJsonSupersetOf('address', {'test': 'value2'})
      .toSQL(),
  'json/where-superset-string': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .whereJsonSupersetOf('address', 'test')
      .orWhereJsonSupersetOf('address', 'test2')
      .toSQL(),
  'json/where-subset': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .whereJsonSubsetOf('address', {'test': 'value'})
      .orWhereJsonSubsetOf('address', {'test': 'value2'})
      .toSQL(),

  // Batch 5 — mined from knex.js test/unit/query/builder.js regions not
  // covered by batches 1-4. Mirrors run_js.mjs 1:1 by id.

  // ── Set-ops wrap=true quartet ───────────────────────────────────────
  'union/wrapped-array': (d) =>
      _qb(d).table('users').select(['*']).where('id', 1).union([
        (QueryBuilder qb) {
          qb.table('users').select(['*']).where('id', 2);
        },
        (QueryBuilder qb) {
          qb.table('users').select(['*']).where('id', 3);
        },
      ], wrap: true).toSQL(),
  'unionAll/wrapped-array': (d) =>
      _qb(d).table('users').select(['*']).where('id', 1).unionAll([
        (QueryBuilder qb) {
          qb.table('users').select(['*']).where('id', 2);
        },
        (QueryBuilder qb) {
          qb.table('users').select(['*']).where('id', 3);
        },
      ], wrap: true).toSQL(),
  'intersect/wrapped-array': (d) =>
      _qb(d).table('users').select(['*']).where('id', 1).intersect([
        (QueryBuilder qb) {
          qb.table('users').select(['*']).where('id', 2);
        },
        (QueryBuilder qb) {
          qb.table('users').select(['*']).where('id', 3);
        },
      ], wrap: true).toSQL(),
  'except/wrapped-array': (d) =>
      _qb(d).table('users').select(['*']).where('id', 1).except([
        (QueryBuilder qb) {
          qb.table('users').select(['*']).where('id', 2);
        },
        (QueryBuilder qb) {
          qb.table('users').select(['*']).where('id', 3);
        },
      ], wrap: true).toSQL(),

  // ── whereColumn, whereNotBetween ────────────────────────────────────
  'where/column': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .whereColumn('users.id', '=', 'users.otherId')
      .toSQL(),
  'where/not-between': (d) =>
      _qb(d).table('users').select(['*']).whereNotBetween('id', [1, 2]).toSQL(),
  'where/not-between-alt': (d) => _qb(
    d,
  ).table('users').select(['*']).where('id', 'not between ', [1, 2]).toSQL(),

  // ── countDistinct multi-column (pg wraps in extra parens) ───────────
  'agg/count-distinct-multi-col': (d) =>
      _qb(d).table('users').countDistinct(['foo', 'bar']).toSQL(),

  // ── Raw group/order ─────────────────────────────────────────────────
  'group/raw': (d) =>
      _qb(d).table('users').select(['*']).groupByRaw('id, email').toSQL(),
  'order/raw': (d) => _qb(
    d,
  ).table('users').select(['*']).orderByRaw('col NULLS LAST DESC').toSQL(),
  'order/raw-with-binding': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .orderByRaw('col NULLS LAST ?', ['dEsc'])
      .toSQL(),

  // ── JOIN family: cross, full-outer, right, joins with raw ───────────
  'join/cross-multi': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .crossJoin('contracts')
      .crossJoin('photos')
      .toSQL(),
  // knex.js supports `crossJoin('t', 'a', 'b')` (CROSS JOIN ... ON); dart's
  // crossJoin() is intentionally cross-product only (no ON). No API
  // equivalent — `join/cross-on` deliberately not mined here. See the audit
  // punchlist: noted as a real API gap, separate from parity-bug territory.
  'join/full-outer': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .fullOuterJoin('contacts', 'users.id', 'contacts.id')
      .toSQL(),
  'join/right-and-right-outer': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .rightJoin('contacts', 'users.id', 'contacts.id')
      .rightOuterJoin('photos', 'users.id', 'photos.id')
      .toSQL(),
  'join/raw-operand': (d) => _qb(d)
      .table('users')
      .select(['*'])
      // knex.js's `join('contacts', 'users.id', raw(1))` builds the join
      // condition `on "users"."id" = 1` — knex.js's `raw(value)` (with a
      // non-string single arg) emits the literal scalar inline, NOT a
      // placeholder+binding. dart's Raw requires a SQL string, so the
      // faithful mirror is `raw('1')` (no bindings) — emits the literal `1`
      // directly. Likewise knex.js's `leftJoin('photos', 'photos.title',
      // '=', raw('?', ['My Photo']))` uses a parameterized raw, mirrored
      // directly as `raw('?', ['My Photo'])`.
      .join('contacts', (j) => j.on('users.id', '=', _qb(d).client.raw('1')))
      .leftJoin(
        'photos',
        (j) => j.on('photos.title', '=', _qb(d).client.raw('?', ['My Photo'])),
      )
      .toSQL(),

  // ── on-* family in JOIN clause ──────────────────────────────────────
  'on/null': (d) => _qb(d).table('users').select(['*']).join('contacts', (j) {
    j.on('users.id', '=', 'contacts.id').onNull('contacts.address');
  }).toSQL(),
  'on/or-null': (d) =>
      _qb(d).table('users').select(['*']).join('contacts', (j) {
        j
            .on('users.id', '=', 'contacts.id')
            .onNull('contacts.address')
            .orOnNull('contacts.phone');
      }).toSQL(),
  'on/not-null': (d) =>
      _qb(d).table('users').select(['*']).join('contacts', (j) {
        j.on('users.id', '=', 'contacts.id').onNotNull('contacts.address');
      }).toSQL(),
  'on/or-not-null': (d) =>
      _qb(d).table('users').select(['*']).join('contacts', (j) {
        j
            .on('users.id', '=', 'contacts.id')
            .onNotNull('contacts.address')
            .orOnNotNull('contacts.phone');
      }).toSQL(),
  'on/in': (d) => _qb(d).table('users').select(['*']).join('contacts', (j) {
    j.onIn('users.id', [1, 2, 3]);
  }).toSQL(),
  'on/or-in': (d) => _qb(d).table('users').select(['*']).join('contacts', (j) {
    j.onIn('users.id', [1, 2, 3]).orOnIn('users.id', [4, 5]);
  }).toSQL(),
  'on/not-in': (d) => _qb(d).table('users').select(['*']).join('contacts', (j) {
    j.onNotIn('users.id', [1, 2, 3]);
  }).toSQL(),
  'on/between': (d) =>
      _qb(d).table('users').select(['*']).join('contacts', (j) {
        j.onBetween('users.id', [1, 5]);
      }).toSQL(),
  'on/not-between': (d) =>
      _qb(d).table('users').select(['*']).join('contacts', (j) {
        j.onNotBetween('users.id', [1, 5]);
      }).toSQL(),
  'on/exists': (d) => _qb(d).table('users').select(['*']).join('contacts', (j) {
    j.onExists((inner) {
      inner
          .select(['*'])
          .table('phones')
          .where(
            'phones.contact_id',
            '=',
            _qb(d).client.raw('"contacts"."id"'),
          );
    });
  }).toSQL(),
  'on/not-exists': (d) =>
      _qb(d).table('users').select(['*']).join('contacts', (j) {
        j.onNotExists((inner) {
          inner
              .select(['*'])
              .table('phones')
              .where(
                'phones.contact_id',
                '=',
                _qb(d).client.raw('"contacts"."id"'),
              );
        });
      }).toSQL(),
  'on/val': (d) => _qb(d).table('users').select(['*']).join('contacts', (j) {
    j
        .on('users.id', '=', 'contacts.id')
        .onVal('contacts.status', '=', 'active');
  }).toSQL(),
  'on/or-val': (d) => _qb(d).table('users').select(['*']).join('contacts', (j) {
    j
        .on('users.id', '=', 'contacts.id')
        .onVal('contacts.status', '=', 'active')
        .orOnVal('contacts.status', '=', 'pending');
  }).toSQL(),
  'on/and-between': (d) =>
      _qb(d).table('users').select(['*']).join('contacts', (j) {
        j.andOnBetween('contacts.score', [1, 5]);
      }).toSQL(),
  'on/or-between': (d) =>
      _qb(d).table('users').select(['*']).join('contacts', (j) {
        j.onBetween('contacts.score', [1, 5]).orOnBetween('contacts.score', [
          10,
          20,
        ]);
      }).toSQL(),
  'on/and-not-between': (d) =>
      _qb(d).table('users').select(['*']).join('contacts', (j) {
        j.andOnNotBetween('contacts.score', [1, 5]);
      }).toSQL(),
  'on/or-not-between': (d) =>
      _qb(d).table('users').select(['*']).join('contacts', (j) {
        j.onNotBetween('contacts.score', [1, 5]).orOnNotBetween(
          'contacts.score',
          [10, 20],
        );
      }).toSQL(),

  // ── row-level lock modes ──────────────────────────────────────────────
  'lock/for-update': (d) =>
      _qb(d).table('users').select(['*']).forUpdate().toSQL(),
  'lock/for-update-tables': (d) =>
      _qb(d).table('users').select(['*']).forUpdate(['users']).toSQL(),
  'lock/for-share': (d) =>
      _qb(d).table('users').select(['*']).forShare().toSQL(),
  'lock/for-no-key-update': (d) =>
      _qb(d).table('users').select(['*']).forNoKeyUpdate().toSQL(),
  'lock/for-key-share': (d) =>
      _qb(d).table('users').select(['*']).forKeyShare().toSQL(),
  'lock/for-update-skip-locked': (d) =>
      _qb(d).table('users').select(['*']).forUpdate().skipLocked().toSQL(),
  'lock/for-update-no-wait': (d) =>
      _qb(d).table('users').select(['*']).forUpdate().noWait().toSQL(),
  'lock/for-share-skip-locked': (d) =>
      _qb(d).table('users').select(['*']).forShare().skipLocked().toSQL(),

  // ── Batch 7: aggregate/raw/pluck + remaining ON family ──────────────
  'agg/count-array': (d) => _qb(d).table('t').count(['id', 'name']).toSQL(),
  'agg/count-map': (d) =>
      _qb(d).table('t').count({'total': 'id', 'cnt': 'name'}).toSQL(),
  'agg/count-raw': (d) =>
      _qb(d).table('t').count(_qb(d).client.raw('coalesce(?, 0)', [1])).toSQL(),
  'pluck/basic': (d) => _qb(d).table('t').pluck('name').toSQL(),
  'on/raw': (d) => _qb(d).table('users').select(['*']).join('contacts', (j) {
    j.onRaw(
      _qb(d).client.raw(
        '"users"."id" = "contacts"."user_id" and "contacts"."active" = ?',
        [true],
      ),
    );
  }).toSQL(),
  'on/wrapped': (d) =>
      _qb(d).table('users').select(['*']).join('contacts', (j) {
        j.on('users.id', '=', 'contacts.user_id').on((nested) {
          nested
              .on('contacts.active', '=', 'users.active')
              .orOn('contacts.admin', '=', 'users.admin');
        });
      }).toSQL(),
  'on/using': (d) => _qb(d).table('users').select(['*']).join('contacts', (j) {
    j.using(['user_id', 'tenant_id']);
  }).toSQL(),
  'on/json-path-equals': (d) => _qb(d).table('users').select(['*']).join(
    'contacts',
    (j) {
      j.onJsonPathEquals('users.meta', r'$.id', 'contacts.meta', r'$.user_id');
    },
  ).toSQL(),
  'on/in-tuple': (d) =>
      _qb(d).table('users').select(['*']).join('contacts', (j) {
        j.onIn(
          ['contacts.tenant_id', 'contacts.user_id'],
          [
            [1, 2],
            [3, 4],
          ],
        );
      }).toSQL(),
  'on/in-subquery': (d) =>
      _qb(d).table('users').select(['*']).join('contacts', (j) {
        j.onIn(
          'contacts.user_id',
          _qb(d).table('admins').select(['user_id']).where('enabled', true),
        );
      }).toSQL(),
  'on/in-raw': (d) => _qb(d).table('users').select(['*']).join('contacts', (j) {
    j.onIn('contacts.user_id', _qb(d).client.raw('select ? as "user_id"', [1]));
  }).toSQL(),
};
