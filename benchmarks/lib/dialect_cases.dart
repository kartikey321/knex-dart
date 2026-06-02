import 'package:knex_dart/knex_dart.dart';

import 'benchmark_case.dart';

final sqlGenerationCases = <BenchmarkCase>[
  BenchmarkCase(
    id: 'select_simple',
    name: 'SELECT simple',
    category: 'select',
    mode: BenchmarkMode.queryGeneration,
    complexity: 'basic',
    features: ['select', 'projection'],
    build: (dialect) => BenchmarkOutput.fromSqlString(
      KnexQuery.forDialect(
        dialect,
      ).from('users').select(['id', 'name', 'email']).toSQL(),
    ),
  ),
  BenchmarkCase(
    id: 'select_complex',
    name: 'SELECT complex',
    category: 'select',
    mode: BenchmarkMode.queryGeneration,
    complexity: 'medium',
    features: ['select', 'where', 'order_by', 'limit', 'offset'],
    build: (dialect) => BenchmarkOutput.fromSqlString(
      KnexQuery.forDialect(dialect)
          .from('users')
          .select(['*'])
          .where('age', '>', 25)
          .where('active', '=', true)
          .orderBy('name', 'asc')
          .limit(50)
          .offset(100)
          .toSQL(),
    ),
  ),
  BenchmarkCase(
    id: 'insert_single',
    name: 'INSERT single',
    category: 'mutation',
    mode: BenchmarkMode.queryGeneration,
    complexity: 'basic',
    features: ['insert'],
    build: (dialect) => BenchmarkOutput.fromSqlString(
      KnexQuery.forDialect(dialect).from('users').insert({
        'name': 'Alice',
        'age': 30,
        'email': 'a@example.com',
      }).toSQL(),
    ),
  ),
  BenchmarkCase(
    id: 'insert_batch',
    name: 'INSERT batch',
    category: 'mutation',
    mode: BenchmarkMode.queryGeneration,
    complexity: 'medium',
    features: ['insert', 'batch_values'],
    build: (dialect) => BenchmarkOutput.fromSqlString(
      KnexQuery.forDialect(dialect).from('users').insert([
        {'name': 'Alice', 'age': 30, 'email': 'a@example.com'},
        {'name': 'Bob', 'age': 31, 'email': 'b@example.com'},
        {'name': 'Cara', 'age': 32, 'email': 'c@example.com'},
      ]).toSQL(),
    ),
  ),
  BenchmarkCase(
    id: 'update_where',
    name: 'UPDATE where',
    category: 'mutation',
    mode: BenchmarkMode.queryGeneration,
    complexity: 'basic',
    features: ['update', 'where'],
    build: (dialect) => BenchmarkOutput.fromSqlString(
      KnexQuery.forDialect(dialect).from('users').where('id', '=', 1).update({
        'name': 'Bob',
        'age': 31,
      }).toSQL(),
    ),
  ),
  BenchmarkCase(
    id: 'delete_where',
    name: 'DELETE where',
    category: 'mutation',
    mode: BenchmarkMode.queryGeneration,
    complexity: 'basic',
    features: ['delete', 'where'],
    build: (dialect) => BenchmarkOutput.fromSqlString(
      KnexQuery.forDialect(
        dialect,
      ).from('users').where('id', '=', 1).delete().toSQL(),
    ),
  ),
  BenchmarkCase(
    id: 'where_wrapped_between_null',
    name: 'WHERE wrapped/between/null',
    category: 'where',
    mode: BenchmarkMode.queryGeneration,
    complexity: 'medium',
    features: ['where_wrapped', 'where_between', 'where_null'],
    build: (dialect) => BenchmarkOutput.fromSqlString(
      KnexQuery.forDialect(dialect)
          .from('users')
          .select(['id'])
          .whereWrapped((qb) {
            qb.where('age', '>=', 18).orWhere('verified', '=', true);
          })
          .whereBetween('created_at', ['2026-01-01', '2026-12-31'])
          .whereNull('deleted_at')
          .toSQL(),
    ),
  ),
  BenchmarkCase(
    id: 'where_exists',
    name: 'WHERE exists',
    category: 'where',
    mode: BenchmarkMode.queryGeneration,
    complexity: 'medium',
    features: ['where_exists', 'where_raw'],
    build: (dialect) {
      final client = KnexQuery.forDialect(dialect);
      return BenchmarkOutput.fromSqlString(
        client.from('users').whereExists((qb) {
          qb
              .from('orders')
              .select(['id'])
              .where(
                client.queryBuilder().client.raw('orders.user_id = users.id'),
              );
        }).toSQL(),
      );
    },
  ),
  BenchmarkCase(
    id: 'aggregate_group_having',
    name: 'Aggregate group/having',
    category: 'aggregate',
    mode: BenchmarkMode.queryGeneration,
    complexity: 'medium',
    features: ['sum', 'count', 'group_by', 'having'],
    build: (dialect) => BenchmarkOutput.fromSqlString(
      KnexQuery.forDialect(dialect)
          .from('orders')
          .select(['customer_id'])
          .sum('amount as total')
          .count('id as count')
          .groupBy('customer_id')
          .having('total', '>', 1000)
          .having('count', '>=', 5)
          .toSQL(),
    ),
  ),
  BenchmarkCase(
    id: 'join_advanced',
    name: 'JOIN advanced',
    category: 'join',
    mode: BenchmarkMode.queryGeneration,
    complexity: 'medium',
    features: ['join', 'join_callback', 'where'],
    build: (dialect) => BenchmarkOutput.fromSqlString(
      KnexQuery.forDialect(dialect)
          .from('users')
          .select(['users.*', 'orders.total'])
          .join('orders', (JoinClause join) {
            join
                .on('users.id', '=', 'orders.user_id')
                .andOn('orders.status', '=', 'users.status');
          })
          .where('orders.total', '>', 100)
          .toSQL(),
    ),
  ),
  BenchmarkCase(
    id: 'subquery_where_in',
    name: 'Subquery whereIn',
    category: 'subquery',
    mode: BenchmarkMode.queryGeneration,
    complexity: 'medium',
    features: ['subquery', 'where_in'],
    build: (dialect) => BenchmarkOutput.fromSqlString(
      KnexQuery.forDialect(dialect).from('users').whereIn('id', (
        QueryBuilder qb,
      ) {
        qb.from('orders').select(['user_id']).where('total', '>', 500);
      }).toSQL(),
    ),
  ),
  BenchmarkCase(
    id: 'cte_multiple',
    name: 'CTE multiple',
    category: 'cte',
    mode: BenchmarkMode.queryGeneration,
    complexity: 'complex',
    features: ['cte', 'join', 'subquery'],
    build: (dialect) {
      final client = KnexQuery.forDialect(dialect);
      final sales = client
          .queryBuilder()
          .table('orders')
          .select(['*'])
          .where('status', '=', 'completed');
      final returns = client.queryBuilder().table('refunds').select(['*']);
      return BenchmarkOutput.fromSqlString(
        client
            .queryBuilder()
            .withQuery('sales', sales)
            .withQuery('returns', returns)
            .select(['*'])
            .from('sales')
            .join('returns', 'sales.id', 'returns.order_id')
            .toSQL(),
      );
    },
  ),
  BenchmarkCase(
    id: 'cte_recursive',
    name: 'CTE recursive',
    category: 'cte',
    mode: BenchmarkMode.queryGeneration,
    complexity: 'complex',
    features: ['recursive_cte', 'union', 'join'],
    build: (dialect) {
      final client = KnexQuery.forDialect(dialect);
      final recursive = client
          .queryBuilder()
          .table('nodes')
          .select(['*'])
          .where('parent_id', '=', null)
          .union([
            client
                .queryBuilder()
                .table('nodes as n')
                .select(['n.*'])
                .join('tree as t', 'n.parent_id', 't.id'),
          ]);
      return BenchmarkOutput.fromSqlString(
        client
            .queryBuilder()
            .withRecursive('tree', recursive)
            .select(['*'])
            .from('tree')
            .toSQL(),
      );
    },
  ),
  BenchmarkCase(
    id: 'union_intersect_except',
    name: 'Union/intersect/except',
    category: 'set',
    mode: BenchmarkMode.queryGeneration,
    complexity: 'complex',
    features: ['union', 'intersect', 'except'],
    build: (dialect) {
      final client = KnexQuery.forDialect(dialect);
      final active = client
          .queryBuilder()
          .table('users')
          .select(['id'])
          .where('active', '=', true);
      final paid = client
          .queryBuilder()
          .table('orders')
          .select(['user_id'])
          .where('total', '>', 100);
      final banned = client.queryBuilder().table('bans').select(['user_id']);
      return BenchmarkOutput.fromSqlString(
        active.union([paid]).except([banned]).toSQL(),
      );
    },
  ),
  BenchmarkCase(
    id: 'window_row_number',
    name: 'Window rowNumber',
    category: 'window',
    mode: BenchmarkMode.queryGeneration,
    complexity: 'medium',
    features: ['window_function', 'row_number'],
    build: (dialect) => BenchmarkOutput.fromSqlString(
      KnexQuery.forDialect(dialect)
          .from('employees')
          .select(['name', 'department', 'salary'])
          .rowNumber('rn', 'salary', 'department')
          .toSQL(),
    ),
  ),
  BenchmarkCase(
    id: 'window_rank_dense_rank',
    name: 'Window rank/denseRank',
    category: 'window',
    mode: BenchmarkMode.queryGeneration,
    complexity: 'complex',
    features: ['window_function', 'rank', 'dense_rank'],
    build: (dialect) => BenchmarkOutput.fromSqlString(
      KnexQuery.forDialect(dialect)
          .from('employees')
          .select(['name', 'department', 'salary'])
          .rank('ranked', 'salary', 'department')
          .denseRank('dense_ranked', 'salary', 'department')
          .toSQL(),
    ),
  ),
  BenchmarkCase(
    id: 'on_conflict_merge',
    name: 'onConflict merge',
    category: 'insert',
    mode: BenchmarkMode.queryGeneration,
    complexity: 'medium',
    features: ['insert', 'on_conflict', 'merge'],
    dialects: {
      KnexDialect.postgres,
      KnexDialect.mysql,
      KnexDialect.sqlite,
      KnexDialect.mariadb,
    },
    build: (dialect) => BenchmarkOutput.fromSqlString(
      KnexQuery.forDialect(dialect)
          .from('users')
          .insert({'email': 'a@b.com', 'name': 'Alice'})
          .onConflict('email')
          .merge()
          .toSQL(),
    ),
  ),
  BenchmarkCase(
    id: 'returning_insert',
    name: 'INSERT returning',
    category: 'insert',
    mode: BenchmarkMode.queryGeneration,
    complexity: 'medium',
    features: ['insert', 'returning'],
    dialects: {KnexDialect.postgres, KnexDialect.mssql},
    build: (dialect) => BenchmarkOutput.fromSqlString(
      KnexQuery.forDialect(dialect)
          .from('users')
          .insert({'email': 'a@b.com', 'name': 'Alice'})
          .returning(['id', 'name'])
          .toSQL(),
    ),
  ),
  BenchmarkCase(
    id: 'locking_skip_locked',
    name: 'Locking skipLocked',
    category: 'locking',
    mode: BenchmarkMode.queryGeneration,
    complexity: 'medium',
    features: ['for_update', 'skip_locked'],
    dialects: {
      KnexDialect.postgres,
      KnexDialect.mysql,
      KnexDialect.mariadb,
      KnexDialect.redshift,
    },
    build: (dialect) => BenchmarkOutput.fromSqlString(
      KnexQuery.forDialect(
        dialect,
      ).from('users').select(['*']).forUpdate().skipLocked().toSQL(),
    ),
  ),
  BenchmarkCase(
    id: 'from_raw',
    name: 'fromRaw',
    category: 'raw',
    mode: BenchmarkMode.queryGeneration,
    complexity: 'medium',
    features: ['from_raw', 'raw_bindings'],
    build: (dialect) => BenchmarkOutput.fromSqlString(
      KnexQuery.forDialect(dialect)
          .queryBuilder()
          .fromRaw('(select * from users where active = ?) as active_users', [
            true,
          ])
          .select(['id', 'email'])
          .where('email', 'like', '%@example.com')
          .toSQL(),
    ),
  ),
  BenchmarkCase(
    id: 'raw_standalone',
    name: 'Raw standalone',
    category: 'raw',
    mode: BenchmarkMode.rawGeneration,
    complexity: 'basic',
    features: ['raw', 'identifier_bindings', 'value_bindings'],
    build: (dialect) => BenchmarkOutput.fromSqlString(
      KnexQuery.forDialect(dialect).queryBuilder().client.raw(
        'select ?? from ?? where ?? = ?',
        ['id', 'users', 'active', true],
      ).toSQL(),
    ),
  ),
  BenchmarkCase(
    id: 'schema_create_table',
    name: 'Schema createTable',
    category: 'schema',
    mode: BenchmarkMode.schemaGeneration,
    complexity: 'medium',
    features: ['schema', 'create_table', 'column_types', 'timestamps'],
    build: (dialect) {
      final schema = KnexQuery.forDialect(dialect).schemaBuilder();
      schema.createTable('users', (table) {
        table.increments('id');
        table.string('name');
        table.string('email', 255).unique();
        table.integer('age');
        table.boolean('active').defaultTo(true);
        table.timestamps(true, true);
      });
      return BenchmarkOutput.fromSchema(schema.toSQL());
    },
  ),
  BenchmarkCase(
    id: 'schema_alter_table',
    name: 'Schema alterTable',
    category: 'schema',
    mode: BenchmarkMode.schemaGeneration,
    complexity: 'medium',
    features: ['schema', 'alter_table', 'add_column', 'drop_column'],
    build: (dialect) {
      final schema = KnexQuery.forDialect(dialect).schemaBuilder();
      schema.alterTable('users', (table) {
        table.string('phone');
        table.dropColumn('legacy_code');
      });
      return BenchmarkOutput.fromSchema(schema.toSQL());
    },
  ),
];

final matrixCoverageMetadata = <Map<String, dynamic>>[
  for (final benchmarkCase in sqlGenerationCases)
    benchmarkCase.toMetadataJson(),
  {
    'id': 'json_public_api_gap',
    'name': 'JSON where helpers',
    'category': 'json',
    'mode': BenchmarkMode.queryGeneration.name,
    'complexity': 'medium',
    'features': ['where_json_path', 'where_json_superset', 'where_json_subset'],
    'status': 'not_benchmarked',
    'notes':
        'The JSON extension is implemented under src/ and is not exported '
        'by package:knex_dart/knex_dart.dart yet.',
  },
  {
    'id': 'live_driver_matrix_gap',
    'name': 'Live driver execution matrix',
    'category': 'live',
    'mode': 'live_execution',
    'complexity': 'system',
    'features': ['driver_execution', 'network', 'pool', 'transactions'],
    'status': 'planned',
    'notes':
        'This first matrix covers generation cost. Live driver execution '
        'needs service orchestration per database.',
  },
];
