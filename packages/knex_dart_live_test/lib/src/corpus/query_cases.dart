/// Dialect-agnostic query corpus, shared by knex_dart's differential parity
/// harness (`packages/knex_dart/test/parity/parity_test.dart`) and
/// knex_dart_live_test's live-execution framework.
///
/// Each entry mirrors — by the SAME id — a builder in `tool/parity/run_js.mjs`.
/// The builder is dialect-agnostic: it receives a dialect name and constructs
/// the query via [KnexQuery.forClient], returning the [QueryBuilder] itself
/// (not compiled SQL) — the parity harness calls `.buildValidated(dialect)`
/// then `.toSQL()` on the result for text comparison; the live-execution
/// runner calls `.buildValidated(dialect)` and executes the QueryBuilder
/// directly through a driver's real methods, so both consumers exercise
/// exactly the same builder-construction code.
///
/// To add coverage, add a case here AND in run_js.mjs under the same id, then
/// regenerate the fixtures.
library;

import 'package:knex_dart/knex_dart.dart';

/// Builds a fresh dialect-scoped query builder.
QueryBuilder _qb(String dialect) => KnexQuery.forClient(dialect).queryBuilder();

/// A single corpus case: a dialect-agnostic query builder plus the
/// operation ([expectedMethod]) it's meant to represent.
///
/// [expectedMethod] is declared independently of what the builder happens
/// to produce — [buildValidated] checks the two match on every build, so a
/// case whose builder chain silently stops representing its claimed
/// operation (e.g. a `delete/*` case that no longer calls `.delete()`)
/// fails loudly and immediately, rather than quietly compiling to — and a
/// live-execution runner quietly running — something else. `null` means
/// the case is expected to THROW when built (see the `errors/*` cases,
/// which test `.first()` chained onto a non-select method) — there is no
/// successful method to validate.
class QueryCorpusCase {
  final String id;
  final QueryMethod? expectedMethod;
  final QueryBuilder Function(String dialect) build;

  const QueryCorpusCase(this.id, this.expectedMethod, this.build);

  /// Builds a fresh [QueryBuilder] for [dialect] and validates its actual
  /// compiled method against [expectedMethod] (skipped when null, i.e. the
  /// case is expected to throw during [build] itself).
  QueryBuilder buildValidated(String dialect) {
    final query = build(dialect);
    if (expectedMethod != null && query.method != expectedMethod) {
      throw StateError(
        '"$id" built ${query.method}, expected $expectedMethod — the '
        "builder chain no longer represents this case's declared operation",
      );
    }
    return query;
  }
}

/// The raw dialect-agnostic builders, keyed by stable id — unchanged in
/// content from the pre-reshape corpus (`packages/knex_dart/test/parity/`
/// `parity_cases.dart`), only the terminal `.toSQL()` call removed so the
/// builder itself, not its compiled SQL, is what gets shared.
final Map<String, QueryBuilder Function(String dialect)> _builders = {
  // WHERE — basics
  'where/eq-string': (d) =>
      _qb(d).table('users').where('status', 'active'),
  'where/eq-number': (d) => _qb(d).table('users').where('age', 25),
  'where/op-gt': (d) => _qb(d).table('users').where('age', '>', 18),
  'where/op-lte': (d) => _qb(d).table('users').where('age', '<=', 65),
  'where/and-chain': (d) =>
      _qb(d).table('users').where('a', 1).where('b', 2),
  'where/or': (d) =>
      _qb(d).table('users').where('a', 1).orWhere('b', 2),
  'where/null': (d) => _qb(d).table('users').where('deleted_at', null),
  'where/explicit-null': (d) =>
      _qb(d).table('users').where('deleted_at', '=', null),
  'where/not-null': (d) => _qb(d).table('users').whereNotNull('email'),
  'where/in': (d) => _qb(d).table('users').whereIn('id', [1, 2, 3]),
  'where/not-in': (d) => _qb(d).table('users').whereNotIn('id', [1, 2]),
  'where/or-in': (d) =>
      _qb(d).table('users').where('a', 1).orWhereIn('role', ['x', 'y']),
  'where/between': (d) =>
      _qb(d).table('users').whereBetween('age', [18, 65]),
  'where/grouped': (d) => _qb(d)
      .table('users')
      .where('a', 1)
      .where((q) => q.where('b', 2).orWhere('c', 3))
      ,
  'where/subquery-in': (d) => _qb(d)
      .table('users')
      .whereIn(
        'id',
        _qb(d).table('orders').select(['user_id']).where('total', '>', 100),
      )
      ,
  'where/in-multi-column-single-tuple': (d) => _qb(d)
      .table('users')
      .whereIn(
        ['a', 'b'],
        [
          [1, 2],
        ],
      )
      ,
  'where/in-callback': (d) => _qb(d).table('users').whereIn('id', (q) {
    q.select(['user_id']).table('orders').where('total', '>', 100);
  }),

  // SELECT / ORDER / LIMIT
  'select/columns': (d) => _qb(d).table('users').select(['id', 'name']),
  'select/orderby-multi': (d) =>
      _qb(d).table('users').orderBy('a').orderBy('b', 'desc'),
  'select/orderby-raw-direction': (d) => _qb(d)
      .table('users')
      .orderBy('name', _qb(d).client.raw('desc nulls last'))
      ,
  'select/limit-offset': (d) =>
      _qb(d).table('users').limit(10).offset(5),

  // JOINs
  'join/inner': (d) =>
      _qb(d).table('a').join('b', 'a.id', 'b.a_id').select(['*']),
  'join/left': (d) =>
      _qb(d).table('a').leftJoin('b', 'a.id', 'b.a_id').select(['*']),
  'query/truncate': (d) => _qb(d).table('users').truncate(),
  'join/raw': (d) => _qb(d)
      .table('users')
      .joinRaw('join contacts on contacts.id = users.contact_id')
      ,
  'join/raw-with-binding': (d) => _qb(
    d,
  ).table('users').joinRaw('join contacts on contacts.id = ?', [1]),

  // DML
  'insert/single': (d) => _qb(
    d,
  ).table('users').insert({'email': 'a@b.com', 'name': 'Alice'}),
  'insert/multi-ragged': (d) => _qb(d).table('t').insert([
    {'a': 1, 'b': 2},
    {'a': 3, 'c': 4},
  ]),
  'update/set': (d) =>
      _qb(d).table('users').where('id', 2).update({'name': 'Bob'}),
  'delete/where': (d) => _qb(d).table('users').where('id', 2).delete(),

  // UNION / CTE
  'union/two': (d) => _qb(d).table('a').select(['id']).where('x', 1).union([
    _qb(d).table('b').select(['id']).where('y', 2),
  ]),
  'cte/select': (d) => _qb(d)
      .table('t')
      .withQuery(
        'recent',
        _qb(d).table('src').select(['id']).where('flag', true),
      )
      .select(['*'])
      ,

  // Capability-varying
  'upsert/merge': (d) => _qb(d)
      .table('users')
      .insert({'email': 'a@b.com', 'name': 'Alice'})
      .onConflict('email')
      .merge()
      ,
  'upsert/merge-columns': (d) => _qb(d)
      .table('users')
      .insert({'email': 'a@b.com', 'name': 'Alice', 'updated_at': 'now'})
      .onConflict('email')
      .merge(['name', 'updated_at'])
      ,
  'returning/insert': (d) => _qb(
    d,
  ).table('users').insert({'email': 'a@b.com'}).returning(['id']),

  // Batch 2 — aggregates, grouping, distinct, counters, set-ops
  'where/not': (d) =>
      _qb(d).table('users').whereNot('status', 'banned'),
  'select/distinct': (d) => _qb(d).table('users').distinct(['name']),
  'select/desc': (d) =>
      _qb(d).table('users').orderBy('created_at', 'desc'),
  'agg/count-col': (d) => _qb(d).table('t').count('id'),
  'agg/sum': (d) => _qb(d).table('t').sum('amount'),
  'agg/min-max': (d) => _qb(d).table('t').min('lo').max('hi'),
  'having/basic': (d) =>
      _qb(d).table('t').groupBy('cat').having('cnt', '>', 1),
  'update/increment': (d) =>
      _qb(d).table('t').where('id', 1).increment('views', 5),
  'delete/all': (d) => _qb(d).table('users').delete(),
  'delete/limit-mysql': (d) =>
      _qb(d).table('users').where('id', '>', 1).delete().limit(1),
  'union/all': (d) => _qb(d).table('a').select(['id']).unionAll([
    _qb(d).table('b').select(['id']),
  ]),

  // Known-divergence probe
  'jsonb/qmark-op': (d) =>
      _qb(d).table('t').where('tags', '?', 'urgent'),

  // Batch 3 — nested subqueries, EXISTS, UNION/INTERSECT, CTEs, window
  // functions, DML with RETURNING/onConflict. Mirrors run_js.mjs 1:1 by id;
  // shapes mined from knex.js's test/unit/query/builder.js.

  // ── Subqueries (select / where / from, incl. 2+ level nesting) ──────────
  'subquery/from-aliased': (d) => _qb(d)
      .table(_qb(d).table('foo').select(['*']).as('bar'))
      .join('baz', 'foo.id', 'bar.foo_id')
      ,
  'subquery/where-scalar': (d) => _qb(d)
      .table('users')
      .where(
        'id',
        '=',
        _qb(d).table('users').select(['id']).where('email', 'bar'),
      )
      ,
  'subquery/where-scalar-callback': (d) =>
      _qb(d).table('users').where('id', '=', (QueryBuilder qb) {
        qb
            .select([_qb(d).client.raw('max(id)')])
            .table('users')
            .where('email', '=', 'bar');
      }),
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
      ,
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
      ,
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
      ,
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
      ,
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
      ,

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
        ;
  },
  'cte/chained-siblings': (d) => _qb(d)
      .withQuery('firstWithClause', _qb(d).select(['foo']).table('users'))
      .withQuery('secondWithClause', _qb(d).select(['bar']).table('users'))
      .select(['*'])
      .table('secondWithClause')
      ,
  'cte/raw': (d) => _qb(d)
      .withQuery(
        'withRawClause',
        _qb(d).client.raw('select "foo" as "baz" from "users"'),
      )
      .select(['*'])
      .table('withRawClause')
      ,
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
        ;
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
      ,
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
      ,
  'cte/delete-source': (d) => _qb(d)
      .withQuery('delete1', _qb(d).table('accounts').delete().where('id', 1))
      .table('accounts')
      ,

  // ── EXISTS / NOT EXISTS ──────────────────────────────────────────────────
  'exists/where': (d) => _qb(d).table('orders').select(['*']).whereExists((qb) {
    qb
        .select(['*'])
        .table('products')
        .where('products.id', '=', _qb(d).client.raw('"orders"."id"'));
  }),
  'exists/where-not': (d) =>
      _qb(d).table('orders').select(['*']).whereNotExists((qb) {
        qb
            .select(['*'])
            .table('products')
            .where('products.id', '=', _qb(d).client.raw('"orders"."id"'));
      }),
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
      ,
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
      ,
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
      ,
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
      ,

  // ── UNION / INTERSECT / EXCEPT ───────────────────────────────────────────
  'union/three-way': (d) =>
      _qb(d).table('a').select(['id']).where('x', 1).union([
        _qb(d).table('b').select(['id']).where('y', 2),
        _qb(d).table('c').select(['id']).where('z', 3),
      ]),
  'union/array-callbacks': (d) =>
      _qb(d).table('users').select(['*']).where('id', 1).union([
        (QueryBuilder qb) {
          qb.table('users').select(['*']).where('id', 2);
        },
        (QueryBuilder qb) {
          qb.table('users').select(['*']).where('id', 3);
        },
      ]),
  'union/order-limit-outer': (d) => _qb(d)
      .table('a')
      .select(['id', 'name'])
      .where('x', 1)
      .union([
        _qb(d).table('b').select(['id', 'name']).where('y', 2),
      ])
      .orderBy('name')
      .limit(10)
      ,
  'intersect/basic': (d) =>
      _qb(d).table('a').select(['*']).where('id', '=', 1).intersect([
        _qb(d).table('b').select(['*']).where('id', '=', 2),
      ]),
  'intersect/three-way': (d) => _qb(d).table('a').select(['id']).intersect([
    _qb(d).table('b').select(['id']),
    _qb(d).table('c').select(['id']),
  ]),
  'except/basic': (d) => _qb(d).table('a').select(['id']).except([
    _qb(d).table('b').select(['id']),
  ]),
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
      ,

  // ── Window / analytic functions ──────────────────────────────────────────
  'window/rank-string-partition': (d) => _qb(d)
      .table('accounts')
      .select(['*'])
      .rank('alias_name', 'email', 'firstName')
      ,
  'window/rank-array-both': (d) => _qb(d)
      .table('accounts')
      .select(['*'])
      .rank('alias_name', ['email', 'address'], ['firstName', 'lastName'])
      ,
  'window/dense-rank-callback': (d) => _qb(d)
      .table('accounts')
      .select(['*'])
      .denseRank('test_alias', (a) => a.orderBy('email').partitionBy('address'))
      ,
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
      ,
  'window/row-number-array': (d) => _qb(d)
      .table('accounts')
      .select(['*'])
      .rowNumber('alias_name', ['email', 'address'], ['firstName', 'lastName'])
      ,
  'window/rank-raw': (d) => _qb(d)
      .table('accounts')
      .select(['*'])
      .rank(null, _qb(d).client.raw('partition by address order by email'))
      ,
  'window/chained-multiple': (d) => _qb(d)
      .table('accounts')
      .select(['*'])
      .denseRank('first_alias', 'email')
      .denseRank('second_alias', 'address')
      ,
  'window/dense-rank-raw-alias': (d) => _qb(d)
      .table('accounts')
      .select(['*'])
      .denseRank(
        'test_alias',
        _qb(d).client.raw('partition by address order by email'),
      )
      ,
  'window/rank-then-orderby': (d) => _qb(d)
      .table('accounts')
      .select(['*'])
      .rank('rnk', 'salary')
      .where('dept', '=', 'eng')
      .orderBy('rnk')
      ,

  // ── DML with RETURNING / onConflict ──────────────────────────────────────
  'dml/onconflict-ignore': (d) => _qb(d)
      .table('users')
      .insert([
        {'email': 'foo'},
        {'email': 'bar'},
      ])
      .onConflict('email')
      .ignore()
      ,
  'dml/onconflict-composite-ignore': (d) => _qb(d)
      .table('users')
      .insert([
        {'org': 'acme-inc', 'email': 'foo'},
      ])
      .onConflict(['org', 'email'])
      .ignore()
      ,
  'dml/onconflict-merge-explicit': (d) => _qb(d)
      .table('users')
      .insert([
        {'email': 'foo', 'name': 'taylor'},
        {'email': 'bar', 'name': 'dayle'},
      ])
      .onConflict('email')
      .merge({'name': 'overidden'})
      ,
  'dml/onconflict-merge-implicit-multi': (d) => _qb(d)
      .table('users')
      .insert([
        {'email': 'foo', 'name': 'taylor'},
        {'email': 'bar', 'name': 'dayle'},
      ])
      .onConflict('email')
      .merge()
      ,
  'dml/onconflict-raw-target': (d) => _qb(d)
      .table('users')
      .insert([
        {'email': 'foo'},
        {'email': 'bar'},
      ])
      .onConflict(_qb(d).client.raw('(value) WHERE deleted_at IS NULL'))
      .ignore()
      ,
  'dml/onconflict-merge-where': (d) => _qb(d)
      .table('users')
      .insert({'email': 'foo', 'name': 'taylor'})
      .onConflict('email')
      .merge()
      .where('email', 'foo2')
      ,
  'dml/returning-multi-insert': (d) => _qb(d)
      .table('users')
      .insert([
        {'email': 'a'},
        {'email': 'b'},
      ])
      .returning(['id', 'email'])
      ,
  'dml/returning-update': (d) => _qb(d)
      .table('users')
      .where('id', 1)
      .update({'name': 'Bob'})
      .returning(['*'])
      ,
  'dml/returning-delete': (d) =>
      _qb(d).table('users').where('id', 1).delete().returning(['id']),

  // Batch 4 — mined from knex.js test/unit/query/builder.js lines 385-1917.
  // Mirrors run_js.mjs 1:1 by id.
  'select/star': (d) => _qb(d).table('users').select(['*']),
  'select/multi-calls': (d) => _qb(d)
      .table('users')
      .select(['foo'])
      .select(['bar'])
      .select(['baz', 'boom'])
      ,
  'select/distinct-then-select': (d) =>
      _qb(d).table('users').distinct().select(['foo', 'bar']),
  'select/alias-map': (d) =>
      _qb(d).table('users').select({'bar': 'foo'}),
  'select/alias-map-multi': (d) =>
      _qb(d).table('users').select({'bar': 'foo', 'baz': 'qux'}),
  'select/alias-map-raw': (d) => _qb(d).table('users').select({
    'answer': _qb(d).client.raw('?', [42]),
  }),
  'select/alias-map-subquery': (d) => _qb(d).table('users').select({
    'order_id': _qb(d).table('orders').select(['id']).where('total', '>', 100),
  }),
  'select/alias-array-mixed': (d) => _qb(d).table('users').select([
    'baz',
    {'bar': 'foo'},
  ]),
  'select/old-style-alias': (d) =>
      _qb(d).table('users').select(['foo as bar']),
  'select/alias-trim-spaces': (d) =>
      _qb(d).table('users').select([' foo   as bar ']),
  'select/alias-case-insensitive': (d) =>
      _qb(d).table('users').select([' foo   aS bar ']),
  'select/alias-dotted': (d) =>
      _qb(d).table('users').select(['foo as bar.baz']),
  'table/dotted-schema': (d) =>
      _qb(d).table('public.users').select(['*']),

  'clear/select-basic': (d) =>
      _qb(d).table('users').select(['id', 'email']).clearSelect(),
  'clear/select-then-reselect': (d) => _qb(
    d,
  ).table('users').select(['id']).clearSelect().select(['email']),
  'clear/where-basic': (d) => _qb(
    d,
  ).table('users').select(['id']).where('id', '=', 1).clearWhere(),
  'clear/where-then-rewhere': (d) => _qb(d)
      .table('users')
      .select(['id'])
      .where('id', '=', 1)
      .clearWhere()
      .where('id', '=', 2)
      ,
  'clear/group-basic': (d) =>
      _qb(d).table('users').groupBy('name').clearGroup(),
  'clear/group-then-regroup': (d) =>
      _qb(d).table('users').groupBy('name').clearGroup().groupBy('id'),
  'clear/order-basic': (d) =>
      _qb(d).table('users').orderBy('name', 'desc').clearOrder(),
  'clear/order-then-reorder': (d) => _qb(d)
      .table('users')
      .orderBy('name', 'desc')
      .clearOrder()
      .orderBy('id', 'asc')
      ,
  'clear/having-then-rehaving': (d) => _qb(d)
      .table('users')
      .having('id', '>', 100)
      .clearHaving()
      .having('id', '>', 10)
      ,
  'clear/counters': (d) => _qb(d)
      .table('users')
      .where('id', '=', 1)
      .update({'email': 'foo@bar.com'})
      .increment('balance', 10)
      .clearCounters()
      .decrement('value', 50)
      .clearCounters()
      ,

  // Batch 2 (HAVING) — mined from knex.js test/unit/query/builder.js lines
  // 3547-5949.

  // ── HAVING ────────────────────────────────────────────────────────────
  'having/nested': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .havingWrapped((q) => q.having('email', '>', 1))
      ,
  'having/nested-or': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .havingWrapped(
        (q) => q.having('email', '>', 10).orHaving('email', '=', 7),
      )
      ,
  'having/grouped': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .groupBy(['email'])
      .having('email', '>', 1)
      ,
  'having/from-alias': (d) => _qb(d)
      .table('users')
      .select(['email as foo_email'])
      .having('foo_email', '>', 1)
      ,
  // JS: having(raw(...)) — Dart's having() requires a String column, so this
  // is adapted to havingRaw(), which compiles to identical SQL.
  'having/raw': (d) => _qb(
    d,
  ).table('users').select(['*']).havingRaw('user_foo < user_bar'),
  'having/raw-or': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .having('baz', '=', 1)
      .orHavingRaw('user_foo < user_bar')
      ,
  'having/null': (d) =>
      _qb(d).table('users').select(['*']).havingNull('baz'),
  'having/or-null': (d) => _qb(
    d,
  ).table('users').select(['*']).havingNull('baz').orHavingNull('foo'),
  'having/not-null': (d) =>
      _qb(d).table('users').select(['*']).havingNotNull('baz'),
  'having/or-not-null': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .havingNotNull('baz')
      .orHavingNotNull('foo')
      ,
  'having/exists': (d) => _qb(d).table('users').select(['*']).havingExists((q) {
    q.select(['baz']).table('users');
  }),
  'having/or-exists': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .havingExists((q) {
        q.select(['baz']).table('users');
      })
      .orHavingExists((q) {
        q.select(['foo']).table('users');
      })
      ,
  'having/not-exists': (d) =>
      _qb(d).table('users').select(['*']).havingNotExists((q) {
        q.select(['baz']).table('users');
      }),
  'having/or-not-exists': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .havingNotExists((q) {
        q.select(['baz']).table('users');
      })
      .orHavingNotExists((q) {
        q.select(['foo']).table('users');
      })
      ,
  'having/between': (d) =>
      _qb(d).table('users').select(['*']).havingBetween('baz', [5, 10]),
  'having/or-between': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .havingBetween('baz', [5, 10])
      .orHavingBetween('baz', [20, 30])
      ,
  'having/not-between': (d) => _qb(
    d,
  ).table('users').select(['*']).havingNotBetween('baz', [5, 10]),
  'having/or-not-between': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .havingNotBetween('baz', [5, 10])
      .orHavingNotBetween('baz', [20, 30])
      ,
  'having/in': (d) =>
      _qb(d).table('users').select(['*']).havingIn('baz', [5, 10, 37]),
  'having/or-in': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .havingIn('baz', [5, 10, 37])
      .orHavingIn('foo', ['Batman', 'Joker'])
      ,
  'having/not-in': (d) => _qb(
    d,
  ).table('users').select(['*']).havingNotIn('baz', [5, 10, 37]),
  'having/or-not-in': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .havingNotIn('baz', [5, 10, 37])
      .orHavingNotIn('foo', ['Batman', 'Joker'])
      ,

  // ── Batch 3 (lines 5950-8353) — insert edge cases, update/counter
  // overwrite semantics, locks, joins in DML, misc operators/raw, and
  // denseRank/rank null-alias variants.

  // Insert edge cases
  'insert/ragged-defaults-3col': (d) => _qb(d).table('table').insert([
    {'a': 1},
    {'b': 2},
    {'a': 2, 'c': 3},
  ]),
  'insert/empty-array-noop': (d) => _qb(d).table('users').insert([]),
  'insert/empty-object-returning': (d) =>
      _qb(d).table('users').insert([{}], ['id']),
  'insert/raw-value': (d) => _qb(d).table('users').insert({
    'email': _qb(d).client.raw('CURRENT TIMESTAMP'),
  }),

  // update() basic variations
  'update/two-cols': (d) => _qb(d)
      .update({'email': 'foo', 'name': 'bar'})
      .table('users')
      .where('id', '=', 1)
      ,
  'update/null-value': (d) => _qb(d)
      .update({'email': null, 'name': 'bar'})
      .table('users')
      .where('id', 1)
      ,
  'update/from-where-then-update': (d) => _qb(d)
      .table('users')
      .where('id', '=', 1)
      .update({'email': 'foo', 'name': 'bar'})
      ,
  'update/raw-value': (d) => _qb(d).table('users').where('id', '=', 1).update({
    'email': _qb(d).client.raw('foo'),
    'name': 'bar',
  }),

  // update() + orderBy/limit/join — probing whether they're honored
  'update/orderby-limit': (d) => _qb(d)
      .table('users')
      .where('id', '=', 1)
      .orderBy('foo', 'desc')
      .limit(5)
      .update({'email': 'foo', 'name': 'bar'})
      ,
  'update/join-mysql': (d) => _qb(d)
      .table('users')
      .join('orders', 'users.id', 'orders.user_id')
      .where('users.id', '=', 1)
      .update({'email': 'foo', 'name': 'bar'})
      ,
  'update/limit-mysql': (d) => _qb(d)
      .table('users')
      .where('users.id', '=', 1)
      .update({'email': 'foo', 'name': 'bar'})
      .limit(1)
      ,
  'update/join-mysql-qualified-col': (d) => _qb(d)
      .table('tblPerson')
      .update({'tblPerson.City': 'Boonesville'})
      .join(
        'tblPersonData',
        (j) => j.on('tblPersonData.PersonId', '=', 'tblPerson.PersonId'),
      )
      .where('tblPersonData.DataId', 1)
      .where('tblPerson.PersonId', 5)
      ,

  // Batch 4 — mined from knex.js test/unit/query/builder.js lines 8354-end.
  // Mirrors run_js.mjs 1:1 by id.

  // ── Window functions (representative shapes) ────────────────────────────
  'window/rank-callback-orderby-only': (d) => _qb(d)
      .table('accounts')
      .select(['*'])
      .rank(null, (a) => a.orderBy('email'))
      ,
  'window/rank-callback-alias-partition': (d) => _qb(d)
      .table('accounts')
      .select(['*'])
      .rank('test_alias', (a) => a.orderBy('email').partitionBy('address'))
      ,
  'window/rank-callback-arrays': (d) => _qb(d)
      .table('accounts')
      .select(['*'])
      .rank(
        'test_alias',
        (a) => a.orderBy(['email', 'name']).partitionBy(['address', 'phone']),
      )
      ,
  'window/rank-chained-multiple': (d) => _qb(d)
      .table('accounts')
      .select(['*'])
      .rank('first_alias', 'email')
      .rank('second_alias', 'address')
      ,
  'window/rank-raw-alias': (d) => _qb(d)
      .table('accounts')
      .select(['*'])
      .rank(
        'test_alias',
        _qb(d).client.raw('partition by address order by email'),
      )
      ,
  'window/row-number-no-partition': (d) =>
      _qb(d).table('accounts').select(['*']).rowNumber(null, 'email'),

  // ── Insert / subqueries ───────────────────────────────────────────────
  'insert/value-subselect': (d) => _qb(d).table('entries').insert({
    'secret': 123,
    'sequence': _qb(d).table('entries').count('*').where('secret', 123),
  }),
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
        ;
  },

  // ── select() / where() extras ────────────────────────────────────────
  'select/fromraw': (d) => _qb(
    d,
  ).select(['*']).fromRaw('(select * from users where age > 18)'),
  'select/modify-callback': (d) => _qb(d)
      .select(['foo_id'])
      .table('foos')
      .modify((QueryBuilder qb, String table, String fk) {
        qb.leftJoin('bars', '$table.$fk', 'bars.id').select(['bars.*']);
      }, ['foos', 'bar_id'])
      ,
  'where/empty-callback': (d) =>
      _qb(d).select(['foo']).table('tbl').where((q) {}),
  'where/not-raw': (d) => _qb(
    d,
  ).table('testtable').whereNot(_qb(d).client.raw('is_active')),
  'where/or-raw': (d) => _qb(
    d,
  ).table('users').where('a', 1).orWhere(_qb(d).client.raw('b = 2')),
  'where/named-binding-array': (d) => _qb(d)
      .select(['*'])
      .table('users')
      .whereIn(
        'id',
        _qb(d).client.raw('select (:test)', {
          'test': [1, 2, 3],
        }),
      )
      ,
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
      ,
  'jsonb/pipe-op': (d) =>
      _qb(d).table('users').select(['*']).where('id', '?|', 1),
  'jsonb/amp-op': (d) =>
      _qb(d).table('users').select(['*']).where('id', '?&', 1),
  'select/numeric-literal': (d) => _qb(d).select([0]),

  // ── CTE + simple UPDATE/DELETE ───────────────────────────────────────
  'cte/update-simple': (d) => _qb(d)
      .withQuery('withClause', _qb(d).select(['foo']).table('users'))
      .update({'foo': 'updatedFoo'})
      .where('email', '=', 'foo')
      .table('users')
      ,
  'cte/delete-simple': (d) => _qb(d)
      .withQuery('withClause', _qb(d).select(['email']).table('users'))
      .delete()
      .where('foo', '=', 'updatedFoo')
      .table('users')
      ,

  // ── knex.ref() ────────────────────────────────────────────────────────
  'ref/where-column': (d) => _qb(d)
      .table('sometable')
      .where(
        'sometable.column',
        _qb(d).client.ref('someothertable.someothercolumn'),
      )
      .select(['*'])
      ,
  'ref/select-alias': (d) => _qb(d).table('sometable').select([
    'one',
    _qb(d).client.ref('sometable.two').as('Two'),
  ]),

  // ── .first() chained onto a non-select method — must throw ────────────
  'errors/first-on-update': (d) =>
      _qb(d).table('sometable').update({'column': 'value'}).first(),
  'errors/first-on-insert': (d) =>
      _qb(d).table('sometable').insert({'column': 'value'}).first(),
  'errors/first-on-delete': (d) =>
      _qb(d).table('sometable').delete().first(),

  // ── DELETE + JOIN ─────────────────────────────────────────────────────
  'delete/join-single': (d) => _qb(d)
      .table('users')
      .delete()
      .join('photos', 'photos.id', 'users.id')
      .where('user.email', 'mock@example.com')
      ,
  'delete/join-multi': (d) => _qb(d)
      .table('users')
      .delete()
      .join('photos', 'photos.id', 'users.id')
      .join('docs', 'docs.id', 'users.id')
      .where('user.email', 'mock@example.com')
      ,
  'delete/join-no-where': (d) => _qb(
    d,
  ).table('users').delete().join('photos', 'photos.id', 'users.id'),
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
      ,

  // ── JSON where family (adapted: knex-dart has no "Not" variant of these,
  // so both sides use the plain/OR forms only) ────────────────────────────
  'json/where-object': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .whereJsonObject('address', {'street': 'street1', 'number': 5})
      .orWhereJsonObject('address', {'street': 'street2', 'number': 7})
      ,
  'json/where-path': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .whereJsonPath('address', r'$.street.number', '>', 5)
      .orWhereJsonPath('address', r'$.street.number', '<', 8)
      ,
  'json/where-superset-object': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .whereJsonSupersetOf('address', {'test': 'value'})
      .orWhereJsonSupersetOf('address', {'test': 'value2'})
      ,
  'json/where-superset-string': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .whereJsonSupersetOf('address', 'test')
      .orWhereJsonSupersetOf('address', 'test2')
      ,
  'json/where-subset': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .whereJsonSubsetOf('address', {'test': 'value'})
      .orWhereJsonSubsetOf('address', {'test': 'value2'})
      ,

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
      ], wrap: true),
  'unionAll/wrapped-array': (d) =>
      _qb(d).table('users').select(['*']).where('id', 1).unionAll([
        (QueryBuilder qb) {
          qb.table('users').select(['*']).where('id', 2);
        },
        (QueryBuilder qb) {
          qb.table('users').select(['*']).where('id', 3);
        },
      ], wrap: true),
  'intersect/wrapped-array': (d) =>
      _qb(d).table('users').select(['*']).where('id', 1).intersect([
        (QueryBuilder qb) {
          qb.table('users').select(['*']).where('id', 2);
        },
        (QueryBuilder qb) {
          qb.table('users').select(['*']).where('id', 3);
        },
      ], wrap: true),
  'except/wrapped-array': (d) =>
      _qb(d).table('users').select(['*']).where('id', 1).except([
        (QueryBuilder qb) {
          qb.table('users').select(['*']).where('id', 2);
        },
        (QueryBuilder qb) {
          qb.table('users').select(['*']).where('id', 3);
        },
      ], wrap: true),

  // ── whereColumn, whereNotBetween ────────────────────────────────────
  'where/column': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .whereColumn('users.id', '=', 'users.otherId')
      ,
  'where/not-between': (d) =>
      _qb(d).table('users').select(['*']).whereNotBetween('id', [1, 2]),
  'where/not-between-alt': (d) => _qb(
    d,
  ).table('users').select(['*']).where('id', 'not between ', [1, 2]),

  // ── countDistinct multi-column (pg wraps in extra parens) ───────────
  'agg/count-distinct-multi-col': (d) =>
      _qb(d).table('users').countDistinct(['foo', 'bar']),

  // ── Raw group/order ─────────────────────────────────────────────────
  'group/raw': (d) =>
      _qb(d).table('users').select(['*']).groupByRaw('id, email'),
  'order/raw': (d) => _qb(
    d,
  ).table('users').select(['*']).orderByRaw('col NULLS LAST DESC'),
  'order/raw-with-binding': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .orderByRaw('col NULLS LAST ?', ['dEsc'])
      ,

  // ── JOIN family: cross, full-outer, right, joins with raw ───────────
  'join/cross-multi': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .crossJoin('contracts')
      .crossJoin('photos')
      ,
  // knex.js supports `crossJoin('t', 'a', 'b')` (CROSS JOIN ... ON); dart's
  // crossJoin() is intentionally cross-product only (no ON). No API
  // equivalent — `join/cross-on` deliberately not mined here. See the audit
  // punchlist: noted as a real API gap, separate from parity-bug territory.
  'join/full-outer': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .fullOuterJoin('contacts', 'users.id', 'contacts.id')
      ,
  'join/right-and-right-outer': (d) => _qb(d)
      .table('users')
      .select(['*'])
      .rightJoin('contacts', 'users.id', 'contacts.id')
      .rightOuterJoin('photos', 'users.id', 'photos.id')
      ,
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
      ,

  // ── on-* family in JOIN clause ──────────────────────────────────────
  'on/null': (d) => _qb(d).table('users').select(['*']).join('contacts', (j) {
    j.on('users.id', '=', 'contacts.id').onNull('contacts.address');
  }),
  'on/or-null': (d) =>
      _qb(d).table('users').select(['*']).join('contacts', (j) {
        j
            .on('users.id', '=', 'contacts.id')
            .onNull('contacts.address')
            .orOnNull('contacts.phone');
      }),
  'on/not-null': (d) =>
      _qb(d).table('users').select(['*']).join('contacts', (j) {
        j.on('users.id', '=', 'contacts.id').onNotNull('contacts.address');
      }),
  'on/or-not-null': (d) =>
      _qb(d).table('users').select(['*']).join('contacts', (j) {
        j
            .on('users.id', '=', 'contacts.id')
            .onNotNull('contacts.address')
            .orOnNotNull('contacts.phone');
      }),
  'on/in': (d) => _qb(d).table('users').select(['*']).join('contacts', (j) {
    j.onIn('users.id', [1, 2, 3]);
  }),
  'on/or-in': (d) => _qb(d).table('users').select(['*']).join('contacts', (j) {
    j.onIn('users.id', [1, 2, 3]).orOnIn('users.id', [4, 5]);
  }),
  'on/not-in': (d) => _qb(d).table('users').select(['*']).join('contacts', (j) {
    j.onNotIn('users.id', [1, 2, 3]);
  }),
  'on/between': (d) =>
      _qb(d).table('users').select(['*']).join('contacts', (j) {
        j.onBetween('users.id', [1, 5]);
      }),
  'on/not-between': (d) =>
      _qb(d).table('users').select(['*']).join('contacts', (j) {
        j.onNotBetween('users.id', [1, 5]);
      }),
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
  }),
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
      }),
  'on/val': (d) => _qb(d).table('users').select(['*']).join('contacts', (j) {
    j
        .on('users.id', '=', 'contacts.id')
        .onVal('contacts.status', '=', 'active');
  }),
  'on/or-val': (d) => _qb(d).table('users').select(['*']).join('contacts', (j) {
    j
        .on('users.id', '=', 'contacts.id')
        .onVal('contacts.status', '=', 'active')
        .orOnVal('contacts.status', '=', 'pending');
  }),
  'on/and-between': (d) =>
      _qb(d).table('users').select(['*']).join('contacts', (j) {
        j.andOnBetween('contacts.score', [1, 5]);
      }),
  'on/or-between': (d) =>
      _qb(d).table('users').select(['*']).join('contacts', (j) {
        j.onBetween('contacts.score', [1, 5]).orOnBetween('contacts.score', [
          10,
          20,
        ]);
      }),
  'on/and-not-between': (d) =>
      _qb(d).table('users').select(['*']).join('contacts', (j) {
        j.andOnNotBetween('contacts.score', [1, 5]);
      }),
  'on/or-not-between': (d) =>
      _qb(d).table('users').select(['*']).join('contacts', (j) {
        j.onNotBetween('contacts.score', [1, 5]).orOnNotBetween(
          'contacts.score',
          [10, 20],
        );
      }),

  // ── row-level lock modes ──────────────────────────────────────────────
  'lock/for-update': (d) =>
      _qb(d).table('users').select(['*']).forUpdate(),
  'lock/for-update-tables': (d) =>
      _qb(d).table('users').select(['*']).forUpdate(['users']),
  'lock/for-share': (d) =>
      _qb(d).table('users').select(['*']).forShare(),
  'lock/for-no-key-update': (d) =>
      _qb(d).table('users').select(['*']).forNoKeyUpdate(),
  'lock/for-key-share': (d) =>
      _qb(d).table('users').select(['*']).forKeyShare(),
  'lock/for-update-skip-locked': (d) =>
      _qb(d).table('users').select(['*']).forUpdate().skipLocked(),
  'lock/for-update-no-wait': (d) =>
      _qb(d).table('users').select(['*']).forUpdate().noWait(),
  'lock/for-share-skip-locked': (d) =>
      _qb(d).table('users').select(['*']).forShare().skipLocked(),

  // ── Batch 7: aggregate/raw/pluck + remaining ON family ──────────────
  'agg/count-array': (d) => _qb(d).table('t').count(['id', 'name']),
  'agg/count-map': (d) =>
      _qb(d).table('t').count({'total': 'id', 'cnt': 'name'}),
  'agg/count-raw': (d) =>
      _qb(d).table('t').count(_qb(d).client.raw('coalesce(?, 0)', [1])),
  'pluck/basic': (d) => _qb(d).table('t').pluck('name'),
  'on/raw': (d) => _qb(d).table('users').select(['*']).join('contacts', (j) {
    j.onRaw(
      _qb(d).client.raw(
        '"users"."id" = "contacts"."user_id" and "contacts"."active" = ?',
        [true],
      ),
    );
  }),
  'on/bare-string': (d) =>
      _qb(d).table('users').select(['*']).join('contacts', (j) {
        j.on('users.id = contacts.user_id');
      }),
  'on/or-not-exists': (d) =>
      _qb(d).table('users').select(['*']).join('contacts', (j) {
        j.on('users.id', '=', 'contacts.user_id').orOnNotExists((inner) {
          inner
              .select(['*'])
              .table('phones')
              .where(
                'phones.contact_id',
                '=',
                _qb(d).client.raw('??', ['contacts.id']),
              );
        });
      }),
  'on/and-val-direct': (d) =>
      _qb(d).table('users').select(['*']).join('contacts', (j) {
        j
            .on('users.id', '=', 'contacts.user_id')
            .andOnVal('contacts.status', '=', 'active');
      }),
  'on/or-map': (d) => _qb(d).table('users').select(['*']).join('contacts', (j) {
    j.on('users.id', '=', 'contacts.user_id').orOn({
      'contacts.active': 'users.active',
      'contacts.admin': 'users.admin',
    });
  }),
  'on/or-val-map': (d) =>
      _qb(d).table('users').select(['*']).join('contacts', (j) {
        j.on('users.id', '=', 'contacts.user_id').orOnVal({
          'contacts.status': 'active',
          'contacts.role': 'vip',
        });
      }),
  'on/wrapped': (d) =>
      _qb(d).table('users').select(['*']).join('contacts', (j) {
        j.on('users.id', '=', 'contacts.user_id').on((nested) {
          nested
              .on('contacts.active', '=', 'users.active')
              .orOn('contacts.admin', '=', 'users.admin');
        });
      }),
  'on/using': (d) => _qb(d).table('users').select(['*']).join('contacts', (j) {
    j.using(['user_id', 'tenant_id']);
  }),
  'on/json-path-equals': (d) => _qb(d).table('users').select(['*']).join(
    'contacts',
    (j) {
      j.onJsonPathEquals('users.meta', r'$.id', 'contacts.meta', r'$.user_id');
    },
  ),
  'on/in-tuple': (d) =>
      _qb(d).table('users').select(['*']).join('contacts', (j) {
        j.onIn(
          ['contacts.tenant_id', 'contacts.user_id'],
          [
            [1, 2],
            [3, 4],
          ],
        );
      }),
  'on/in-subquery': (d) =>
      _qb(d).table('users').select(['*']).join('contacts', (j) {
        j.onIn(
          'contacts.user_id',
          _qb(d).table('admins').select(['user_id']).where('enabled', true),
        );
      }),
  'on/in-raw': (d) => _qb(d).table('users').select(['*']).join('contacts', (j) {
    j.onIn('contacts.user_id', _qb(d).client.raw('select ? as "user_id"', [1]));
  }),
  'on/in-variants': (d) =>
      _qb(d).table('users').select(['*']).join('contacts', (j) {
        j
            .on('users.id', '=', 'contacts.user_id')
            .andOnIn('contacts.kind', [1])
            .orOnIn('contacts.kind', [2])
            .andOnNotIn('contacts.state', [3])
            .orOnNotIn('contacts.state', [4]);
      }),
  'on/null-and-variants': (d) =>
      _qb(d).table('users').select(['*']).join('contacts', (j) {
        j
            .on('users.id', '=', 'contacts.user_id')
            .andOnNull('contacts.deleted_at')
            .andOnNotNull('contacts.email');
      }),
  'on/exists-variants': (d) =>
      _qb(d).table('users').select(['*']).join('contacts', (j) {
        j
            .on('users.id', '=', 'contacts.user_id')
            .andOnExists(
              (q) => q.select(['*']).table('phones').where('active', true),
            )
            .orOnExists(
              (q) => q.select(['*']).table('emails').where('verified', true),
            )
            .andOnNotExists(
              (q) => q.select(['*']).table('blocks').where('blocked', true),
            );
      }),
  'on/json-path-equals-variants': (d) =>
      _qb(d).table('users').select(['*']).join('contacts', (j) {
        j
            .onJsonPathEquals(
              'users.meta',
              r'$.id',
              'contacts.meta',
              r'$.user_id',
            )
            .andOnJsonPathEquals(
              'users.meta',
              r'$.tenant',
              'contacts.meta',
              r'$.tenant_id',
            )
            .orOnJsonPathEquals(
              'users.meta',
              r'$.org',
              'contacts.meta',
              r'$.org_id',
            );
      }),

  // ── Batch 8: coverage-guided QueryBuilder / JoinClause mining ───────
  'agg/avg': (d) => _qb(d).table('t').avg('amount'),
  'agg/distinct-sum-avg': (d) =>
      _qb(d).table('t').sumDistinct('amount').avgDistinct('score'),
  'where/direct-null-and-or': (d) => _qb(d)
      .table('t')
      .where('a', 1)
      .whereNull('deleted_at')
      .orWhereNull('archived_at')
      ,
  'where/direct-column-and-or': (d) => _qb(
    d,
  ).table('t').whereColumn('a', '=', 'b').orWhereColumn('c', '=', 'd'),
  'where/or-between': (d) => _qb(d)
      .table('t')
      .where('x', 1)
      .orWhereBetween('age', [18, 65])
      .orWhereNotBetween('score', [0, 50])
      ,
  'where/or-not': (d) =>
      _qb(d).table('t').where('x', 1).orWhereNot('status', 'banned'),
  'where/or-not-in-null': (d) => _qb(d)
      .table('t')
      .where('x', 1)
      .orWhereNotIn('id', [1, 2])
      .orWhereNotNull('email')
      ,
  'from/alias': (d) => _qb(d).from('users').select(['id']),
  'update/two-arg-returning': (d) =>
      _qb(d).table('t').where('id', 1).update({'name': 'Bob'}, ['id']),
  'delete/two-arg-returning': (d) =>
      _qb(d).table('t').where('id', 1).delete(['id']),
  'select/bare-raw': (d) =>
      _qb(d).table('t').select(_qb(d).client.raw('count(*) as total')),
  'join/left-outer-and-outer': (d) => _qb(d)
      .table('a')
      .leftOuterJoin('b', 'a.id', 'b.a_id')
      .outerJoin('c', 'a.id', 'c.a_id')
      ,
  'on/map-columns': (d) => _qb(d).table('a').join('b', (j) {
    j.on({'a.id': 'b.id', 'a.x': 'b.x'});
  }),
  'on-val/map': (d) => _qb(d).table('a').join('b', (j) {
    j.onVal({'a.status': 'active'});
  }),

  // ── distinctOn() — Postgres-family only ──────────────────────────────
  'select/distinct-on-single': (d) =>
      _qb(d).table('t').distinctOn(['author_id']).select(['*']),
  'select/distinct-on-multi': (d) => _qb(
    d,
  ).table('t').distinctOn(['author_id', 'category']).select(['*']),
};

/// Explicit, independently-declared expected method per case id — derived
/// empirically (built every case against the 'postgres' dialect and read
/// back its real `.method`), then reviewed case-by-case for anything a
/// naive category-prefix guess would have gotten wrong before being frozen
/// here. Two real examples that guessing would have missed:
///  - `clear/counters` looks like a read-only `clear*()` case by category,
///    but its body calls `.update(...)` before the counters it clears —
///    the correct expectation is `update`, not `select`.
///  - `cte/delete-source` looks like a delete case by name, but the DELETE
///    happens inside a *referenced* CTE — the outer query object itself is
///    a bare `select`. Guessing `delete` from the id would have made every
///    future correct build of this case fail validation.
/// Any id not listed here defaults to [QueryMethod.select]. `null` marks
/// the three `errors/*` cases, which are expected to throw a [StateError]
/// during [QueryCorpusCase.build] itself (`.first()` chained onto a
/// non-select method) — there is no successful method to validate.
const Map<String, QueryMethod?> _expectedMethodOverrides = {
  'query/truncate': QueryMethod.truncate,
  'insert/single': QueryMethod.insert,
  'insert/multi-ragged': QueryMethod.insert,
  'update/set': QueryMethod.update,
  'delete/where': QueryMethod.delete,
  'upsert/merge': QueryMethod.insert,
  'upsert/merge-columns': QueryMethod.insert,
  'returning/insert': QueryMethod.insert,
  'update/increment': QueryMethod.update,
  'delete/all': QueryMethod.delete,
  'delete/limit-mysql': QueryMethod.delete,
  'cte/insert-multi-source': QueryMethod.insert,
  'cte/update-source': QueryMethod.update,
  'dml/onconflict-ignore': QueryMethod.insert,
  'dml/onconflict-composite-ignore': QueryMethod.insert,
  'dml/onconflict-merge-explicit': QueryMethod.insert,
  'dml/onconflict-merge-implicit-multi': QueryMethod.insert,
  'dml/onconflict-raw-target': QueryMethod.insert,
  'dml/onconflict-merge-where': QueryMethod.insert,
  'dml/returning-multi-insert': QueryMethod.insert,
  'dml/returning-update': QueryMethod.update,
  'dml/returning-delete': QueryMethod.delete,
  'clear/counters': QueryMethod.update,
  'insert/ragged-defaults-3col': QueryMethod.insert,
  'insert/empty-array-noop': QueryMethod.insert,
  'insert/empty-object-returning': QueryMethod.insert,
  'insert/raw-value': QueryMethod.insert,
  'update/two-cols': QueryMethod.update,
  'update/null-value': QueryMethod.update,
  'update/from-where-then-update': QueryMethod.update,
  'update/raw-value': QueryMethod.update,
  'update/orderby-limit': QueryMethod.update,
  'update/join-mysql': QueryMethod.update,
  'update/limit-mysql': QueryMethod.update,
  'update/join-mysql-qualified-col': QueryMethod.update,
  'insert/value-subselect': QueryMethod.insert,
  'cte/update-simple': QueryMethod.update,
  'cte/delete-simple': QueryMethod.delete,
  'errors/first-on-update': null,
  'errors/first-on-insert': null,
  'errors/first-on-delete': null,
  'delete/join-single': QueryMethod.delete,
  'delete/join-multi': QueryMethod.delete,
  'delete/join-no-where': QueryMethod.delete,
  'delete/join-oncallback-where': QueryMethod.delete,
  'pluck/basic': QueryMethod.pluck,
  'update/two-arg-returning': QueryMethod.update,
  'delete/two-arg-returning': QueryMethod.delete,
};

QueryMethod? _expectedMethodFor(String id) => _expectedMethodOverrides
    .containsKey(id)
    ? _expectedMethodOverrides[id]
    : QueryMethod.select;

/// The full query corpus: every case id paired with its builder and its
/// declared expected method, keyed by id (matching the pre-reshape
/// `parityCases` map shape for easy id-based lookup by both consumers).
final Map<String, QueryCorpusCase> queryCorpusCases = {
  for (final entry in _builders.entries)
    entry.key: QueryCorpusCase(
      entry.key,
      _expectedMethodFor(entry.key),
      entry.value,
    ),
};
