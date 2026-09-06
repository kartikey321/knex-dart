@Tags(['postgres'])
library;

import 'package:universal_io/io.dart';

import 'package:knex_dart_postgres/knex_dart_postgres.dart';
import 'package:knex_dart/src/query/query_builder.dart';
import 'package:knex_dart/src/schema/schema_builder.dart';
import 'package:test/test.dart';

import '../mocks/mock_client.dart';

void main() {
  late PostgresClient pgClient;
  final mockClient = MockClient();
  const testEmails = <String>[
    'test_insert@example.com',
    'on_conflict_test@example.com',
    'before_update@example.com',
    'to_delete@example.com',
    'trx_commit@example.com',
    'pre_rollback@example.com',
    'trx_rollback@example.com',
    'json_test@example.com',
    'json_test1@example.com',
    'json_test2@example.com',
    'outer_sp@example.com',
    'inner_sp@example.com',
    'inner_fail_sp@example.com',
    'outer_after_sp@example.com',
    'outer_bubble_sp@example.com',
    'inner_bubble_sp@example.com',
    'json_path_test@example.com',
    'json_object_test@example.com',
    'json_subset_test@example.com',
    'on_conflict_ignore_test@example.com',
    'or_json_object_a@example.com',
    'or_json_object_b@example.com',
  ];

  Future<void> cleanupTestUsers() async {
    final deleteQuery = mockClient
        .queryBuilder()
        .table('users')
        .whereIn('email', testEmails)
        .delete();
    await pgClient.delete(deleteQuery);

    // Scratch rows some tests insert into `orders`/`products` (not
    // `users`, so testEmails/whereIn above can't reach them). These run
    // in both setUpAll (recovers a killed prior run) and tearDownAll — a
    // test that throws before its own trailing inline delete would
    // otherwise leak a row that survives into the NEXT run and breaks
    // every hardcoded seed-count assertion (COUNT=5, 5 completed orders,
    // crossJoin's product count, etc).
    await pgClient.rawSql(
      "delete from orders where status in "
      "('fulljoin_scratch', 'having_null_scratch')",
      null,
    );
    await pgClient.rawSql(
      "delete from products where name in "
      "('Orphan Product', 'Increment Scratch')",
      null,
    );
  }

  Future<void> executeSchema(
    void Function(SchemaBuilder schema) callback,
  ) async {
    final schema = mockClient.schemaBuilder();
    callback(schema);
    final statements = schema.toSQL();
    for (final stmt in statements) {
      await pgClient.rawSql(
        stmt['sql'] as String,
        stmt['bindings'] as List<dynamic>?,
      );
    }
  }

  // Initialize connection before tests
  setUpAll(() async {
    final host = Platform.environment['PG_HOST'] ?? 'localhost';
    final port = int.parse(Platform.environment['PG_PORT'] ?? '5432');
    final database = Platform.environment['PG_DATABASE'] ?? 'knex_test';
    final username = Platform.environment['PG_USER'] ?? 'test';
    final password = Platform.environment['PG_PASSWORD'] ?? 'test';

    pgClient = await PostgresClient.connect(
      host: host,
      port: port,
      database: database,
      username: username,
      password: password,
    );
    await cleanupTestUsers();
    print('PostgreSQL Connection connects successfully');
  });

  // Close connection after tests
  tearDownAll(() async {
    await cleanupTestUsers();
    await pgClient.close();
  });

  group('Basic SELECT', () {
    test('SELECT *', () async {
      final query = mockClient.queryBuilder().table('users');

      final results = await pgClient.select(query);

      expect(results.length, greaterThan(0));
      expect(results.first.containsKey('id'), true);
      expect(results.first.containsKey('name'), true);
      expect(results.first.containsKey('email'), true);
    });

    test('SELECT specific columns', () async {
      final query = mockClient.queryBuilder().table('users').select([
        'id',
        'name',
        'email',
      ]);

      final results = await pgClient.select(query);

      expect(results.first.keys.length, 3);
      expect(results.first.containsKey('password'), false);
    });
  });

  group('WHERE Clauses', () {
    test('WHERE with single condition', () async {
      final query = mockClient
          .queryBuilder()
          .table('users')
          .where('active', '=', true);

      final results = await pgClient.select(query);

      expect(results.isNotEmpty, true);
      expect(results.first['active'], true); // Postgres bool is bool in Dart
    });

    test('WHERE with multiple conditions', () async {
      final query = mockClient
          .queryBuilder()
          .table('users')
          .where('active', '=', true)
          .where('role', '=', 'admin');

      final results = await pgClient.select(query);

      expect(results.isNotEmpty, true);
      expect(results.first['role'], 'admin');
    });

    test('WHERE IN', () async {
      final query = mockClient.queryBuilder().table('users').whereIn('role', [
        'admin',
        'moderator',
      ]);

      final results = await pgClient.select(query);

      expect(results.length, greaterThan(0));
      for (final row in results) {
        expect(['admin', 'moderator'], contains(row['role']));
      }
    });

    test('WHERE NULL', () async {
      final query = mockClient
          .queryBuilder()
          .table('users')
          .where('active', false);

      final results = await pgClient.select(query);
      for (final row in results) {
        expect(row['active'], false);
      }
    });

    test('whereIn() with a multi-column tuple list matches row-value pairs, '
        'not each column independently — proves the "(col1, col2) in ((a,b), '
        '(c,d))" row-value form, since matching each column separately '
        'would pull in extra rows this cannot', () async {
      final query = mockClient
          .queryBuilder()
          .table('orders')
          .select(['id'])
          .whereIn(
            ['user_id', 'status'],
            [
              [1, 'completed'],
              [2, 'pending'],
            ],
          );

      final results = await pgClient.select(query);
      final ids = results.map((r) => r['id']).toSet();

      // Seed: id1/id2 are (user_id=1, completed); id3 is (user_id=2,
      // pending); id4 is (user_id=2, completed) — matches user_id=2 alone
      // but NOT the (2, pending) tuple, so it must be excluded. A broken
      // implementation that degraded to matching user_id and status as
      // independent IN lists would incorrectly include id4.
      expect(ids, {1, 2, 3});
    });
  });

  group('JOINs', () {
    test('INNER JOIN', () async {
      final query = mockClient
          .queryBuilder()
          .table('orders')
          .join('users', 'users.id', 'orders.user_id')
          .select(['users.name', 'orders.amount', 'orders.status']);

      final results = await pgClient.select(query);

      expect(results.isNotEmpty, true);
      expect(results.first.containsKey('name'), true);
      expect(results.first.containsKey('amount'), true);
    });

    test('LEFT JOIN', () async {
      final query = mockClient
          .queryBuilder()
          .table('users')
          .leftJoin('orders', 'users.id', 'orders.user_id')
          .select(['users.name', 'orders.amount']);

      final results = await pgClient.select(query);

      expect(results.isNotEmpty, true);
    });

    test('crossJoin() produces a real cartesian product, not a filtered '
        'join — row count is the exact product of both table sizes', () async {
      // Table sizes are derived rather than hardcoded: package:test runs
      // suite files concurrently against the same database, and
      // postgres_trx_test.dart inserts/deletes rows in `users` mid-run —
      // a fixed "5 users" assumption here would be flaky in a way the
      // pre-existing COUNT test (which merely checks its own table) is
      // not, since this test depends on two tables at once.
      final userCount =
          (await pgClient.select(
            mockClient.queryBuilder().table('users').count('* as c'),
          )).single['c'];
      final productCount =
          (await pgClient.select(
            mockClient.queryBuilder().table('products').count('* as c'),
          )).single['c'];

      final query = mockClient
          .queryBuilder()
          .table('users')
          .select(['users.id', 'products.id'])
          .crossJoin('products');

      final results = await pgClient.select(query);

      // A cross join that silently degraded to any ON-conditioned join
      // would return a different (almost certainly smaller) count than
      // the exact product of both table sizes.
      expect(results.length, (userCount as int) * (productCount as int));
    });

    test('fullOuterJoin() includes unmatched rows from BOTH sides in one '
        'result set — the one behavior a left or right join cannot '
        'reproduce', () async {
      // orders.product_id has no FK constraint (unlike orders.user_id),
      // so we can insert an order referencing a product_id that doesn't
      // exist, giving an unmatched LEFT-side row. A scratch product with
      // no orders gives the unmatched RIGHT-side row. A left join would
      // drop the orphan product; a right join would drop the orphan
      // order; only a real full outer join keeps both.
      final orphanOrder = await pgClient.insert(
        mockClient
            .queryBuilder()
            .table('orders')
            .insert({
              'user_id': 1,
              'product_id': -1,
              'amount': 5.00,
              'status': 'fulljoin_scratch',
            })
            .returning(['id']),
      );
      final orphanOrderId = orphanOrder.first['id'];

      final orphanProduct = await pgClient.insert(
        mockClient
            .queryBuilder()
            .table('products')
            .insert({
              'name': 'Orphan Product',
              'category': 'Test',
              'price': 1.00,
            })
            .returning(['id']),
      );
      final orphanProductId = orphanProduct.first['id'];

      final query = mockClient
          .queryBuilder()
          .table('orders')
          .select(['orders.id as order_id', 'products.id as product_id'])
          .fullOuterJoin('products', 'orders.product_id', 'products.id')
          .where('orders.status', 'fulljoin_scratch')
          .orWhere('products.name', 'Orphan Product');

      final results = await pgClient.select(query);

      final unmatchedOrderRow = results.firstWhere(
        (r) => r['order_id'] == orphanOrderId,
      );
      expect(unmatchedOrderRow['product_id'], isNull);

      final unmatchedProductRow = results.firstWhere(
        (r) => r['product_id'] == orphanProductId,
      );
      expect(unmatchedProductRow['order_id'], isNull);

      await pgClient.delete(
        mockClient
            .queryBuilder()
            .table('orders')
            .where('status', 'fulljoin_scratch')
            .delete(),
      );
      await pgClient.delete(
        mockClient
            .queryBuilder()
            .table('products')
            .where('id', orphanProductId)
            .delete(),
      );
    });
  });

  group('Aggregates', () {
    test('COUNT', () async {
      final query = mockClient
          .queryBuilder()
          .table('users')
          .count('* as total');

      final results = await pgClient.select(query);

      expect(results.first['total'], 5);
    });

    test('SUM', () async {
      final query = mockClient
          .queryBuilder()
          .table('orders')
          .sum('amount as total')
          .where('status', '=', 'completed');

      final results = await pgClient.select(query);

      // PostgreSQL returns DECIMAL as string to preserve precision
      expect(results.first['total'], isA<String>());
      expect(num.parse(results.first['total']), greaterThan(0));
    });

    test('GROUP BY with HAVING (using havingRaw)', () async {
      final query = mockClient
          .queryBuilder()
          .table('orders')
          .select(['user_id'])
          .count('* as order_count')
          .groupBy('user_id')
          .havingRaw('count(*) > ?', [1]);

      final results = await pgClient.select(query);

      expect(results.isNotEmpty, true);
      for (final row in results) {
        expect(row['order_count'], greaterThan(1));
      }
    });
  });

  group('increment() / decrement()', () {
    test('increment() and decrement() apply a real relative delta '
        'server-side, not an absolute overwrite — proven by chaining both '
        'and checking the final arithmetic result', () async {
      final inserted = await pgClient.insert(
        mockClient
            .queryBuilder()
            .table('products')
            .insert({
              'name': 'Increment Scratch',
              'category': 'Test',
              'price': 100.00,
            })
            .returning(['id']),
      );
      final id = inserted.first['id'];

      await pgClient.update(
        mockClient
            .queryBuilder()
            .table('products')
            .where('id', id)
            .increment('price', 10),
      );
      await pgClient.update(
        mockClient
            .queryBuilder()
            .table('products')
            .where('id', id)
            .decrement('price', 25),
      );

      final rows = await pgClient.select(
        mockClient.queryBuilder().table('products').where('id', id),
      );
      // 100 + 10 - 25 = 85. If either call silently set an absolute value
      // instead of a relative delta, this wouldn't land exactly here.
      expect(num.parse(rows.single['price'].toString()), 85);

      await pgClient.delete(
        mockClient.queryBuilder().table('products').where('id', id).delete(),
      );
    });
  });

  group('ORDER BY and LIMIT', () {
    test('ORDER BY', () async {
      final query = mockClient
          .queryBuilder()
          .table('users')
          .select(['name'])
          .orderBy('name', 'asc');

      final results = await pgClient.select(query);

      final names = results.map((r) => r['name'] as String).toList();
      final sorted = List.of(names)..sort();
      expect(names, sorted);
    });

    test('LIMIT and OFFSET', () async {
      final query = mockClient.queryBuilder().table('users').limit(2).offset(1);

      final results = await pgClient.select(query);

      expect(results.length, 2);
    });
  });

  group('Subqueries', () {
    test('Subquery in WHERE', () async {
      final subquery = mockClient
          .queryBuilder()
          .table('orders')
          .select(['user_id'])
          .where('status', '=', 'completed');

      final query = mockClient
          .queryBuilder()
          .table('users')
          .select(['name'])
          .whereIn('id', subquery);

      final results = await pgClient.select(query);

      expect(results.isNotEmpty, true);
    });
  });

  group('UNION', () {
    test('UNION two queries', () async {
      final query1 = mockClient
          .queryBuilder()
          .table('users')
          .select(['name'])
          .where('role', 'admin');

      final query2 = mockClient
          .queryBuilder()
          .table('users')
          .select(['name'])
          .where('role', 'moderator');

      final query = query1.union([query2]);

      final results = await pgClient.select(query);

      expect(results.length, greaterThan(0));
      expect(results.any((r) => r['name'] == 'Alice Johnson'), true);
      expect(results.any((r) => r['name'] == 'Diana Prince'), true);
    });

    test('union() dedups the combined result, unionAll() preserves '
        'duplicates — the same underlying rows on both sides of the same '
        'set operator, only the keyword differs', () async {
      // Completed orders' user_id column has 5 rows collapsing to 3
      // distinct values (1, 1, 2, 4, 4) — deliberately duplicate-laden so
      // a real UNION vs UNION ALL produces genuinely different row counts,
      // not just "some rows came back."
      QueryBuilder completedUserIds() => mockClient
          .queryBuilder()
          .table('orders')
          .select(['user_id'])
          .where('status', 'completed');

      final unioned = await pgClient.select(
        completedUserIds().union([completedUserIds()]),
      );
      expect(unioned.length, 3);

      final unionedAll = await pgClient.select(
        completedUserIds().unionAll([completedUserIds()]),
      );
      // Each side contributes 5 rows; UNION ALL keeps all 10 — if it ever
      // silently deduped like plain UNION, this would come back as 3.
      expect(unionedAll.length, 10);
    });
  });

  group('Advanced Query APIs', () {
    test('Full-Text Search whereFullText', () async {
      final insertQuery = mockClient.queryBuilder().table('users').insert({
        'name': 'Johnathan Doe',
        'email': 'json_test1@example.com',
      });
      await pgClient.insert(insertQuery);

      final query = mockClient
          .queryBuilder()
          .table('users')
          .whereFullText('name', 'Johnathan')
          .orderBy('id');
      final results = await pgClient.select(query);
      expect(results, isNotEmpty);
      expect(results.first['name'], contains('Johnathan'));

      // Without this, the inserted row leaks into the shared `users` table
      // for the rest of the suite run (setUpAll/tearDownAll cleanup only
      // runs once, at the very start/end) — any other test doing a
      // full-table scan on `users` mid-run would see it.
      await pgClient.delete(
        mockClient
            .queryBuilder()
            .table('users')
            .where('email', 'json_test1@example.com')
            .delete(),
      );
    });

    test('JSON Operators: superset and subset', () async {
      try {
        await executeSchema((schema) {
          schema.alterTable('users', (t) {
            t.jsonb('metadata').defaultTo('{}');
          });
        });
      } catch (_) {
        // Ignore if column already exists
      }

      final insertQuery = mockClient.queryBuilder().table('users').insert({
        'name': 'JSON Tester',
        'email': 'json_test2@example.com',
        'metadata': '{"language": "en", "theme": "dark"}',
      });
      await pgClient.insert(insertQuery);

      final query = mockClient
          .queryBuilder()
          .table('users')
          .whereJsonSupersetOf('metadata', {'language': 'en'});
      final results = await pgClient.select(query);

      expect(results, isNotEmpty);

      await pgClient.delete(
        mockClient
            .queryBuilder()
            .table('users')
            .where('email', 'json_test2@example.com')
            .delete(),
      );
    });

    test('Advanced HAVING clauses: havingRaw', () async {
      final query = mockClient
          .queryBuilder()
          .table('orders')
          .select(['user_id', mockClient.raw('COUNT(id) as total')])
          .groupBy('user_id')
          .havingRaw('COUNT(id) > ?', [1])
          .orderBy('total', 'desc');

      final results = await pgClient.select(query);

      expect(results, isNotEmpty);
      expect(results.first['total'], greaterThan(1));
    });

    test('distinctOn() returns one row per distinct value, not deduped '
        'rows (proves it is a real DISTINCT ON, not client-side '
        'dedup — every seeded order has a distinct status/user_id pair '
        'except the ones sharing a status, so a plain row count check '
        'would pass even if distinctOn() silently no-opped)', () async {
      final query = mockClient
          .queryBuilder()
          .table('orders')
          .distinctOn(['status'])
          .select(['status', 'user_id'])
          .orderBy('status')
          .orderBy('id');

      final results = await pgClient.select(query);
      final statuses = results.map((r) => r['status']).toList();

      // Seed data has 3 distinct statuses (completed/pending/cancelled)
      // across 7 orders — a real DISTINCT ON collapses to 3 rows; if it
      // silently no-opped (compiled to a plain SELECT), this would return
      // all 7.
      expect(statuses.toSet().length, statuses.length);
      expect(statuses, containsAll(['completed', 'pending', 'cancelled']));
    });

    test('joinRaw() actually joins — a raw ON condition changes which '
        'rows come back, not just that the query executes', () async {
      final query = mockClient
          .queryBuilder()
          .table('orders')
          .select(['orders.id', 'users.name'])
          .joinRaw('inner join users on users.id = orders.user_id')
          .where('orders.status', 'completed')
          .orderBy('orders.id');

      final results = await pgClient.select(query);

      // The seed has exactly 5 'completed' orders — an exact count, not
      // just "not too many," so a wrong ON condition that happened to
      // return some other row count in between (not obviously a cross
      // join, but still wrong) would still fail this.
      expect(results.length, 5);
      for (final row in results) {
        expect(row['name'], isNotNull);
      }
    });
  });

  group('Window functions', () {
    test('rank() computes real per-partition rank values, not just '
        'valid SQL — partitioned by user_id, ordered by amount ascending, '
        'so a wrong PARTITION BY/ORDER BY would put the wrong rank on a '
        'specific known row rather than merely changing row count', () async {
      final query = mockClient
          .queryBuilder()
          .table('orders')
          .select(['id', 'user_id', 'amount'])
          .rank('rnk', 'amount', 'user_id')
          .orderBy('user_id')
          .orderBy('amount');

      final results = await pgClient.select(query);
      final byId = {for (final r in results) r['id'] as int: r};

      // user_id=1 has orders id=1 (999.99) and id=2 (29.99): ascending by
      // amount puts id=2 first (rank 1), id=1 second (rank 2).
      expect(byId[2]!['rnk'], 1);
      expect(byId[1]!['rnk'], 2);
      // user_id=5 has a single order (id=7): rank always starts at 1
      // regardless of what other partitions contain.
      expect(byId[7]!['rnk'], 1);
    });

    test('denseRank() computes correctly via the callback-built '
        '(AnalyticClause) partition/order form — a separate compiler path '
        'from the string/array form rank() uses above. The seed has no '
        'tied amounts within a partition, so this cannot distinguish '
        'dense_rank from rank by value; it exercises the callback path.',
        () async {
      final query = mockClient
          .queryBuilder()
          .table('orders')
          .select(['id', 'user_id', 'amount'])
          .denseRank(
            'drnk',
            (a) => a.partitionBy('user_id').orderBy('amount'),
          )
          .orderBy('user_id')
          .orderBy('amount');

      final results = await pgClient.select(query);
      final byId = {for (final r in results) r['id'] as int: r};

      expect(byId[2]!['drnk'], 1);
      expect(byId[1]!['drnk'], 2);
    });
  });

  group('WHERE EXISTS / NOT EXISTS', () {
    test('whereExists() only returns users with a real correlated match — '
        'users with at least one completed order', () async {
      final query = mockClient
          .queryBuilder()
          .table('users')
          .select(['name'])
          .whereExists(
            (qb) => qb
                .table('orders')
                .select(['*'])
                .where('orders.user_id', '=', mockClient.raw('users.id'))
                .where('orders.status', 'completed'),
          )
          .orderBy('name');

      final results = await pgClient.select(query);
      final names = results.map((r) => r['name']).toSet();

      // Alice(1), Bob(2), Diana(4) each have >=1 completed order.
      expect(names, {'Alice Johnson', 'Bob Smith', 'Diana Prince'});
      // Charlie has no orders at all, Eve's only order is cancelled — a
      // whereExists() that silently degraded to an unfiltered/always-true
      // subquery would incorrectly include them.
      expect(names.contains('Charlie Brown'), false);
      expect(names.contains('Eve Davis'), false);
    });

    test('whereNotExists() returns exactly the complement', () async {
      final query = mockClient
          .queryBuilder()
          .table('users')
          .select(['name'])
          .whereNotExists(
            (qb) => qb
                .table('orders')
                .select(['*'])
                .where('orders.user_id', '=', mockClient.raw('users.id'))
                .where('orders.status', 'completed'),
          )
          .orderBy('name');

      final results = await pgClient.select(query);
      final names = results.map((r) => r['name']).toSet();

      expect(names, {'Charlie Brown', 'Eve Davis'});
    });
  });

  group('Set operations: INTERSECT / EXCEPT', () {
    test('intersect() returns only rows satisfying BOTH queries', () async {
      final activeUsers = mockClient
          .queryBuilder()
          .table('users')
          .select(['name'])
          .where('active', true);
      final regularUsers = mockClient
          .queryBuilder()
          .table('users')
          .select(['name'])
          .where('role', 'user');

      final query = activeUsers.intersect([regularUsers]);
      final results = await pgClient.select(query);
      final names = results.map((r) => r['name']).toSet();

      // Bob and Eve are active AND role=user; Charlie is role=user but
      // inactive, so a real INTERSECT (not a silent UNION) excludes him.
      expect(names, {'Bob Smith', 'Eve Davis'});
    });

    test('except() returns rows in the first query but not the second', () async {
      final activeUsers = mockClient
          .queryBuilder()
          .table('users')
          .select(['name'])
          .where('active', true);
      final admins = mockClient
          .queryBuilder()
          .table('users')
          .select(['name'])
          .where('role', 'admin');

      final query = activeUsers.except([admins]);
      final results = await pgClient.select(query);
      final names = results.map((r) => r['name']).toSet();

      // Active users are Alice/Bob/Diana/Eve; excluding admin (Alice)
      // leaves exactly Bob/Diana/Eve.
      expect(names, {'Bob Smith', 'Diana Prince', 'Eve Davis'});
    });
  });

  group('Lock modes: forNoKeyUpdate / forKeyShare', () {
    // forShare() gets a real two-transaction concurrency test in
    // postgres_trx_test.dart (a row-count/name assertion here can't tell a
    // real "for share" from a plain unlocked SELECT — see skipLocked()'s
    // test for why). forNoKeyUpdate()/forKeyShare()'s distinguishing
    // behavior (not blocking a concurrent forShare/forKeyShare, but still
    // blocking a plain forUpdate) needs a foreign-key-referencing second
    // table to demonstrate meaningfully, so for now these two only assert
    // the compiled SQL text alongside execution — enough to catch either
    // clause silently dropping or being swapped for the other.
    test('forNoKeyUpdate() compiles the real lock clause and executes '
        'inside a transaction', () async {
      final query = mockClient
          .queryBuilder()
          .table('users')
          .select(['id', 'name'])
          .where('id', 2)
          .forNoKeyUpdate();
      expect(query.toSQL().sql, contains('for no key update'));

      await pgClient.trx((trx) async {
        final results = await trx.select(query);
        expect(results.single['name'], 'Bob Smith');
      });
    });

    test('forKeyShare() compiles the real lock clause and executes inside '
        'a transaction', () async {
      final query = mockClient
          .queryBuilder()
          .table('users')
          .select(['id', 'name'])
          .where('id', 4)
          .forKeyShare();
      expect(query.toSQL().sql, contains('for key share'));

      await pgClient.trx((trx) async {
        final results = await trx.select(query);
        expect(results.single['name'], 'Diana Prince');
      });
    });
  });

  group('JSON path queries', () {
    setUpAll(() async {
      try {
        await executeSchema((schema) {
          schema.alterTable('users', (t) {
            t.jsonb('metadata').defaultTo('{}');
          });
        });
      } catch (_) {
        // Column already added by an earlier test group in this run.
      }
    });

    test('whereJsonPath() filters on a real nested path value, not just '
        'presence of the top-level key', () async {
      const email = 'json_path_test@example.com';
      await pgClient.rawSql('delete from users where email = \$1', [email]);

      final insertQuery = mockClient.queryBuilder().table('users').insert({
        'name': 'Path Tester',
        'email': email,
        'metadata': '{"prefs": {"theme": "dark"}}',
      });
      await pgClient.insert(insertQuery);

      final matching = await pgClient.select(
        mockClient
            .queryBuilder()
            .table('users')
            .where('email', email)
            .whereJsonPath('metadata', r'$.prefs.theme', '=', 'dark'),
      );
      expect(matching, isNotEmpty);

      final nonMatching = await pgClient.select(
        mockClient
            .queryBuilder()
            .table('users')
            .where('email', email)
            .whereJsonPath('metadata', r'$.prefs.theme', '=', 'light'),
      );
      expect(nonMatching, isEmpty);

      await pgClient.rawSql('delete from users where email = \$1', [email]);
    });

    test('whereJsonObject() requires exact equality, not containment — a '
        'strict superset of the target value does NOT match, unlike '
        'whereJsonSupersetOf()', () async {
      const email = 'json_object_test@example.com';
      await pgClient.rawSql('delete from users where email = \$1', [email]);

      await pgClient.insert(
        mockClient.queryBuilder().table('users').insert({
          'name': 'Object Tester',
          'email': email,
          'metadata': '{"language": "en", "theme": "dark"}',
        }),
      );

      final exactMatch = await pgClient.select(
        mockClient
            .queryBuilder()
            .table('users')
            .where('email', email)
            .whereJsonObject('metadata', {'language': 'en', 'theme': 'dark'}),
      );
      expect(exactMatch, isNotEmpty);

      // Same key present, but the stored value has an extra key the target
      // doesn't — real JSON equality (`=`) fails here even though the row
      // would match a containment check like whereJsonSupersetOf().
      final partialMatch = await pgClient.select(
        mockClient
            .queryBuilder()
            .table('users')
            .where('email', email)
            .whereJsonObject('metadata', {'language': 'en'}),
      );
      expect(partialMatch, isEmpty);

      await pgClient.rawSql('delete from users where email = \$1', [email]);
    });

    test('whereJsonSubsetOf() matches when the stored value is contained '
        'by the target, not the other way around', () async {
      const email = 'json_subset_test@example.com';
      await pgClient.rawSql('delete from users where email = \$1', [email]);

      await pgClient.insert(
        mockClient.queryBuilder().table('users').insert({
          'name': 'Subset Tester',
          'email': email,
          'metadata': '{"language": "en"}',
        }),
      );

      // Stored {"language":"en"} IS contained by the larger target object.
      final contained = await pgClient.select(
        mockClient
            .queryBuilder()
            .table('users')
            .where('email', email)
            .whereJsonSubsetOf('metadata', {
              'language': 'en',
              'theme': 'dark',
            }),
      );
      expect(contained, isNotEmpty);

      // Stored {"language":"en"} is NOT contained by a target missing that
      // key — proves this checks real subset containment (<@), not just
      // "some overlap."
      final notContained = await pgClient.select(
        mockClient
            .queryBuilder()
            .table('users')
            .where('email', email)
            .whereJsonSubsetOf('metadata', {'theme': 'dark'}),
      );
      expect(notContained, isEmpty);

      await pgClient.rawSql('delete from users where email = \$1', [email]);
    });

    test('orWhereJsonObject() actually widens the result set via OR — a '
        'row that fails the first WHERE but matches the JSON-object '
        'equality must still be included, not silently ANDed away',
        () async {
      const emailA = 'or_json_object_a@example.com';
      const emailB = 'or_json_object_b@example.com';

      await pgClient.insert(
        mockClient.queryBuilder().table('users').insert({
          'name': 'Or Json A',
          'email': emailA,
          'metadata': '{"lang": "en"}',
        }),
      );
      await pgClient.insert(
        mockClient.queryBuilder().table('users').insert({
          'name': 'Or Json B',
          'email': emailB,
          'metadata': '{"lang": "fr"}',
        }),
      );

      final query = mockClient
          .queryBuilder()
          .table('users')
          .where('email', emailA)
          .orWhereJsonObject('metadata', {'lang': 'fr'});

      final results = await pgClient.select(query);
      final emails = results.map((r) => r['email']).toSet();

      // Row B fails `where('email', emailA)` outright — it only survives
      // because orWhereJsonObject() ORs in a second, independently true
      // condition. If that OR silently compiled as AND, B would vanish.
      expect(emails, {emailA, emailB});

      await pgClient.delete(
        mockClient
            .queryBuilder()
            .table('users')
            .whereIn('email', [emailA, emailB])
            .delete(),
      );
    });
  });

  group('HAVING variants: havingIn / havingNotIn / havingBetween', () {
    // havingIn/havingNotIn/havingBetween wrap their column argument as a
    // plain quoted identifier (see query_compiler.dart's havingBasic/
    // havingIn/havingBetween — formatter.wrap(statement['column'])), so
    // they can only reference a real grouped column, not an aggregate
    // expression like count(*) (Postgres itself doesn't allow SELECT-list
    // aliases in HAVING either). havingRaw() already covers aggregate
    // HAVING elsewhere in this file — these test the non-aggregate,
    // real-column form specifically.
    test('havingIn() keeps only the listed groups', () async {
      final query = mockClient
          .queryBuilder()
          .table('orders')
          .select(['status'])
          .groupBy('status')
          .havingIn('status', ['completed', 'pending'])
          .orderBy('status');

      // Filtering on the grouping key itself is row-level-equivalent to an
      // identical WHERE clause (WHERE status IN (...) GROUP BY status
      // returns the same rows) — the result-set assertion below can't
      // detect the clause landing in the wrong place, only this can.
      expect(
        query.toSQL().sql,
        contains('group by "status" having "status" in'),
      );

      final results = await pgClient.select(query);
      final statuses = results.map((r) => r['status']).toSet();

      // Seed has 3 status groups (completed/pending/cancelled) — havingIn
      // must drop the cancelled group entirely, not just filter its rows.
      expect(statuses, {'completed', 'pending'});
    });

    test('havingNotIn() keeps exactly the complementary groups', () async {
      final query = mockClient
          .queryBuilder()
          .table('orders')
          .select(['status'])
          .groupBy('status')
          .havingNotIn('status', ['completed', 'pending']);

      expect(
        query.toSQL().sql,
        contains('group by "status" having "status" not in'),
      );

      final results = await pgClient.select(query);
      final statuses = results.map((r) => r['status']).toSet();

      expect(statuses, {'cancelled'});
    });

    test('havingBetween() filters groups by a real range on the grouped '
        'column', () async {
      final query = mockClient
          .queryBuilder()
          .table('orders')
          .select(['user_id'])
          .groupBy('user_id')
          .havingBetween('user_id', [2, 4])
          .orderBy('user_id');

      expect(
        query.toSQL().sql,
        contains('group by "user_id" having "user_id" between'),
      );

      final results = await pgClient.select(query);
      final userIds = results.map((r) => r['user_id']).toSet();

      // Seed's order user_ids are {1, 2, 4, 5} — between 2 and 4 keeps
      // exactly {2, 4}, excluding both 1 (below) and 5 (above).
      expect(userIds, {2, 4});
    });

    test('havingExists() / havingNotExists() filter groups by a real '
        'correlated subquery — only Alice is an admin, so only her group '
        'survives havingExists, and everyone else survives '
        'havingNotExists', () async {
      QueryBuilder adminExistsSubquery(QueryBuilder qb) => qb
          .table('users')
          .select(['*'])
          .where('users.id', '=', mockClient.raw('orders.user_id'))
          .where('users.role', 'admin');

      QueryBuilder byAdminUser(bool not) {
        final builder = mockClient
            .queryBuilder()
            .table('orders')
            .select(['user_id'])
            .groupBy('user_id');
        return not
            ? builder.havingNotExists(adminExistsSubquery)
            : builder.havingExists(adminExistsSubquery);
      }

      final adminQuery = byAdminUser(false);
      // The correlation is on the grouping key itself, so filtering it
      // into WHERE instead of HAVING would produce the identical result
      // set — only the compiled clause position can catch that.
      expect(adminQuery.toSQL().sql, contains('group by "user_id" having exists'));
      final adminGroups = await pgClient.select(adminQuery);
      expect(
        adminGroups.map((r) => r['user_id']).toSet(),
        {1}, // Alice (user_id 1) is the only admin with orders.
      );

      final nonAdminQuery = byAdminUser(true);
      expect(
        nonAdminQuery.toSQL().sql,
        contains('group by "user_id" having not exists'),
      );
      final nonAdminGroups = await pgClient.select(nonAdminQuery);
      expect(
        nonAdminGroups.map((r) => r['user_id']).toSet(),
        {2, 4, 5},
      );
    });

    test('havingNull() / havingNotNull() filter groups by a real null '
        'vs non-null grouped-column value, not just clause presence',
        () async {
      const marker = 'having_null_scratch';
      await pgClient.insert(
        mockClient.queryBuilder().table('orders').insert({
          'user_id': 1,
          'product_id': null,
          'amount': 1.00,
          'status': marker,
        }),
      );
      await pgClient.insert(
        mockClient.queryBuilder().table('orders').insert({
          'user_id': 1,
          'product_id': 1,
          'amount': 1.00,
          'status': marker,
        }),
      );

      final nullQuery = mockClient
          .queryBuilder()
          .table('orders')
          .select(['product_id'])
          .where('status', marker)
          .groupBy('product_id')
          .havingNull('product_id');
      // Scoped by `where('status', marker)`, the identical clause in
      // WHERE instead of HAVING would return the same single null row —
      // only the compiled clause position proves this is really HAVING.
      expect(
        nullQuery.toSQL().sql,
        contains('group by "product_id" having "product_id" is null'),
      );
      final nullGroups = await pgClient.select(nullQuery);
      expect(nullGroups.single['product_id'], isNull);

      final notNullQuery = mockClient
          .queryBuilder()
          .table('orders')
          .select(['product_id'])
          .where('status', marker)
          .groupBy('product_id')
          .havingNotNull('product_id');
      expect(
        notNullQuery.toSQL().sql,
        contains('group by "product_id" having "product_id" is not null'),
      );
      final notNullGroups = await pgClient.select(notNullQuery);
      expect(notNullGroups.single['product_id'], 1);

      await pgClient.delete(
        mockClient
            .queryBuilder()
            .table('orders')
            .where('status', marker)
            .delete(),
      );
    });
  });

  group('truncate()', () {
    // Uses a scratch table (not `users`/`orders`) so this can't collide
    // with the shared seed data other tests depend on. setUp drops it
    // first (not just "if not exists") so a table left behind by a killed
    // prior run (tearDown never ran) can't leak stale rows into `before`.
    setUp(() async {
      await pgClient.rawSql('drop table if exists truncate_scratch', null);
      await pgClient.rawSql(
        'create table truncate_scratch (id serial primary key, val text)',
        null,
      );
      await pgClient.rawSql(
        "insert into truncate_scratch (val) values ('a'), ('b'), ('c')",
        null,
      );
    });

    tearDown(() async {
      await pgClient.rawSql('drop table if exists truncate_scratch', null);
    });

    test('actually empties the table and resets the identity sequence '
        '(restart identity — the postgres-specific behavior added this '
        'session)', () async {
      final before = await pgClient.select(
        mockClient.queryBuilder().table('truncate_scratch').select(['*']),
      );
      expect(before.length, 3);

      // Goes through the same builder-to-driver execute() path production
      // code would use, not a hand-extracted SQL string via rawSql() — a
      // bug in how execute()/the interceptor pipeline handles a
      // QueryMethod.truncate builder wouldn't be caught otherwise.
      await pgClient.execute(
        mockClient.queryBuilder().table('truncate_scratch').truncate(),
      );

      final after = await pgClient.select(
        mockClient.queryBuilder().table('truncate_scratch').select(['*']),
      );
      expect(after, isEmpty);

      // restart identity: a fresh insert should get id 1 again, not
      // continue from wherever the sequence was before truncation.
      await pgClient.rawSql(
        "insert into truncate_scratch (val) values ('fresh')",
        null,
      );
      final fresh = await pgClient.select(
        mockClient.queryBuilder().table('truncate_scratch').select(['*']),
      );
      expect(fresh.single['id'], 1);
    });
  });

  group('CTEs (WITH)', () {
    test('Basic CTE', () async {
      final cte = mockClient
          .queryBuilder()
          .table('orders')
          .select(['user_id'])
          .sum('amount as total')
          .groupBy('user_id');

      final query = mockClient
          .queryBuilder()
          .withQuery('user_totals', cte)
          .table('user_totals')
          .where('total', '>', 500);

      final results = await pgClient.select(query);

      expect(results.isNotEmpty, true);
    });

    test('withRecursive() actually recurses to a real fixed point — proof '
        'a SQL-text comparison structurally cannot give, since a recursive '
        'CTE that terminated after 1 iteration (a broken termination '
        'condition) still compiles to valid, identical-looking SQL',
        () async {
      final base = mockClient
          .queryBuilder()
          .select([mockClient.raw('1 as n')]);
      final recursiveTerm = mockClient
          .queryBuilder()
          .select([mockClient.raw('n + 1 as n')])
          .table('counter')
          .where('n', '<', 5);
      final cteBody = base.unionAll([recursiveTerm]);

      final query = mockClient
          .queryBuilder()
          .withRecursive('counter', cteBody)
          .select(['n'])
          .table('counter')
          .orderBy('n');

      final results = await pgClient.select(query);
      final values = results.map((r) => r['n']).toList();

      expect(values, [1, 2, 3, 4, 5]);
    });
  });

  // ─── Write Operation Tests ──────────────────────────────────────────────────
  group('Write Operations', () {
    test('INSERT a row and verify with SELECT', () async {
      final insertQ = mockClient
          .queryBuilder()
          .table('users')
          .insert({
            'name': 'Test Insert',
            'email': 'test_insert@example.com',
            'role': 'guest',
            'active': true,
          })
          .returning(['id', 'name']);
      final inserted = await pgClient.insert(insertQ);

      expect(inserted.length, 1);
      expect(inserted.first['name'], 'Test Insert');
      final id = inserted.first['id'];

      final selectQ = mockClient.queryBuilder().table('users').where('id', id);
      final rows = await pgClient.select(selectQ);
      expect(rows.length, 1);

      await pgClient.delete(
        mockClient.queryBuilder().table('users').where('id', id).delete(),
      );
    });

    test('should perform an upsert with onConflict.merge()', () async {
      final email = 'on_conflict_test@example.com';
      final query1 = mockClient.queryBuilder().table('users').insert({
        'name': 'Original Name',
        'email': email,
        'role': 'guest',
      });
      await pgClient.insert(query1);

      final query2 = mockClient
          .queryBuilder()
          .table('users')
          .insert({'name': 'Updated Name', 'email': email})
          .onConflict('email')
          .merge(['name']);

      await pgClient.insert(query2);

      final rows = await pgClient.select(
        mockClient.queryBuilder().table('users').where('email', email),
      );

      expect(rows.length, 1);
      expect(rows.first['name'], 'Updated Name');

      final deleteQuery = mockClient
          .queryBuilder()
          .table('users')
          .where('email', email)
          .delete();
      await pgClient.delete(deleteQuery);
    });

    test('onConflict().ignore() leaves the existing row untouched, unlike '
        'merge() — proves it is a real DO NOTHING, not a silent update',
        () async {
      const email = 'on_conflict_ignore_test@example.com';
      await pgClient.rawSql('delete from users where email = \$1', [email]);

      await pgClient.insert(
        mockClient.queryBuilder().table('users').insert({
          'name': 'Original Name',
          'email': email,
          'role': 'guest',
        }),
      );

      await pgClient.insert(
        mockClient
            .queryBuilder()
            .table('users')
            .insert({'name': 'Should Not Appear', 'email': email})
            .onConflict('email')
            .ignore(),
      );

      final rows = await pgClient.select(
        mockClient.queryBuilder().table('users').where('email', email),
      );

      expect(rows.length, 1);
      expect(rows.single['name'], 'Original Name');

      await pgClient.rawSql('delete from users where email = \$1', [email]);
    });

    test('UPDATE a row and verify', () async {
      final insertQ = mockClient
          .queryBuilder()
          .table('users')
          .insert({
            'name': 'Before Update',
            'email': 'before_update@example.com',
            'role': 'guest',
            'active': true,
          })
          .returning(['id']);
      final inserted = await pgClient.insert(insertQ);
      final id = inserted.first['id'];

      final updateQ = mockClient
          .queryBuilder()
          .table('users')
          .where('id', id)
          .update({'name': 'After Update'})
          .returning(['id', 'name']);
      final updated = await pgClient.update(updateQ);

      expect(updated.length, 1);
      expect(updated.first['name'], 'After Update');

      await pgClient.delete(
        mockClient.queryBuilder().table('users').where('id', id).delete(),
      );
    });

    test('DELETE a row and verify it is gone', () async {
      final insertQ = mockClient
          .queryBuilder()
          .table('users')
          .insert({
            'name': 'To Delete',
            'email': 'to_delete@example.com',
            'role': 'guest',
            'active': false,
          })
          .returning(['id']);
      final inserted = await pgClient.insert(insertQ);
      final id = inserted.first['id'];

      final deleteQ = mockClient
          .queryBuilder()
          .table('users')
          .where('id', id)
          .delete()
          .returning(['id']);
      final deleted = await pgClient.delete(deleteQ);
      expect(deleted.length, 1);
      expect(deleted.first['id'], id);

      final rows = await pgClient.select(
        mockClient.queryBuilder().table('users').where('id', id),
      );
      expect(rows.isEmpty, true);
    });
  });

  // ─── Transaction Tests ────────────────────────────────────────────────────
  group('Transactions', () {
    test('trx: COMMIT on success — changes are persisted', () async {
      final inserted = await pgClient.trx((trx) async {
        return trx.insert(
          mockClient
              .queryBuilder()
              .table('users')
              .insert({
                'name': 'Trx Commit Test',
                'email': 'trx_commit@example.com',
                'role': 'guest',
                'active': true,
              })
              .returning(['id', 'name']),
        );
      });

      expect(inserted.length, 1);
      expect(inserted.first['name'], 'Trx Commit Test');
      final id = inserted.first['id'];

      final rows = await pgClient.select(
        mockClient.queryBuilder().table('users').where('id', id),
      );
      expect(rows.length, 1);

      await pgClient.delete(
        mockClient.queryBuilder().table('users').where('id', id).delete(),
      );
    });

    test('trx: ROLLBACK on error — changes are reverted', () async {
      final preInsert = await pgClient.insert(
        mockClient
            .queryBuilder()
            .table('users')
            .insert({
              'name': 'Pre Rollback',
              'email': 'pre_rollback@example.com',
              'role': 'guest',
              'active': true,
            })
            .returning(['id']),
      );
      final preId = preInsert.first['id'];

      try {
        await pgClient.trx((trx) async {
          await trx.insert(
            mockClient.queryBuilder().table('users').insert({
              'name': 'Trx Rollback Test',
              'email': 'trx_rollback@example.com',
              'role': 'guest',
              'active': true,
            }),
          );
          throw Exception('Forced rollback');
        });
      } catch (_) {
        // Expected
      }

      final rows = await pgClient.select(
        mockClient
            .queryBuilder()
            .table('users')
            .where('email', 'trx_rollback@example.com'),
      );
      expect(rows.isEmpty, true);

      await pgClient.delete(
        mockClient.queryBuilder().table('users').where('id', preId).delete(),
      );
    });
  });

  // ─── Nested Transaction (Savepoint) Tests ─────────────────────────────────
  group('Nested Transactions (Savepoints)', () {
    test('nested trx: both succeed — both changes visible', () async {
      int? outerId, innerId;

      await pgClient.trx((outer) async {
        final r1 = await outer.insert(
          mockClient
              .queryBuilder()
              .table('users')
              .insert({
                'name': 'Outer SP',
                'email': 'outer_sp@example.com',
                'role': 'guest',
              })
              .returning(['id']),
        );
        outerId = r1.first['id'];

        await outer.trx((inner) async {
          final r2 = await inner.insert(
            mockClient
                .queryBuilder()
                .table('users')
                .insert({
                  'name': 'Inner SP',
                  'email': 'inner_sp@example.com',
                  'role': 'guest',
                })
                .returning(['id']),
          );
          innerId = r2.first['id'];
        });
      });

      final outerRows = await pgClient.select(
        mockClient.queryBuilder().table('users').where('id', outerId),
      );
      final innerRows = await pgClient.select(
        mockClient.queryBuilder().table('users').where('id', innerId),
      );
      expect(outerRows.length, 1);
      expect(innerRows.length, 1);

      await pgClient.delete(
        mockClient.queryBuilder().table('users').whereIn('email', [
          'outer_sp@example.com',
          'inner_sp@example.com',
        ]).delete(),
      );
    });

    test('nested trx: inner rollback, outer continues', () async {
      int? outerId;

      await pgClient.trx((outer) async {
        final r1 = await outer.insert(
          mockClient
              .queryBuilder()
              .table('users')
              .insert({
                'name': 'Outer After SP',
                'email': 'outer_after_sp@example.com',
                'role': 'guest',
              })
              .returning(['id']),
        );
        outerId = r1.first['id'];

        try {
          await outer.trx((inner) async {
            await inner.insert(
              mockClient.queryBuilder().table('users').insert({
                'name': 'Inner SP Fail',
                'email': 'inner_fail_sp@example.com',
                'role': 'guest',
              }),
            );
            throw Exception('force inner rollback');
          });
        } catch (_) {
          // Caught — outer continues
        }
      });

      final outerRows = await pgClient.select(
        mockClient.queryBuilder().table('users').where('id', outerId),
      );
      final innerRows = await pgClient.select(
        mockClient
            .queryBuilder()
            .table('users')
            .where('email', 'inner_fail_sp@example.com'),
      );
      expect(outerRows.length, 1); // outer committed
      expect(innerRows.isEmpty, true); // inner rolled back

      await pgClient.delete(
        mockClient.queryBuilder().table('users').where('id', outerId).delete(),
      );
    });

    test('nested trx: inner error bubbles — outer rolled back too', () async {
      try {
        await pgClient.trx((outer) async {
          await outer.insert(
            mockClient.queryBuilder().table('users').insert({
              'name': 'Outer Bubble',
              'email': 'outer_bubble_sp@example.com',
              'role': 'guest',
            }),
          );
          await outer.trx((inner) async {
            await inner.insert(
              mockClient.queryBuilder().table('users').insert({
                'name': 'Inner Bubble',
                'email': 'inner_bubble_sp@example.com',
                'role': 'guest',
              }),
            );
            throw Exception('bubble up');
          });
        });
      } catch (_) {}

      final outerRows = await pgClient.select(
        mockClient
            .queryBuilder()
            .table('users')
            .where('email', 'outer_bubble_sp@example.com'),
      );
      final innerRows = await pgClient.select(
        mockClient
            .queryBuilder()
            .table('users')
            .where('email', 'inner_bubble_sp@example.com'),
      );
      expect(outerRows.isEmpty, true);
      expect(innerRows.isEmpty, true);
    });
  });
}
