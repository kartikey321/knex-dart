import type { PlaygroundDialect } from './lint/types';

export interface Example {
  name: string;
  dialect: PlaygroundDialect;
  code: string;
}

const BOILERPLATE = `import 'dart:convert';
import 'package:knex_dart/knex_dart.dart';
import 'package:knex_dart_capabilities/knex_dart_capabilities.dart';

void sql(SqlString s) =>
    print(jsonEncode({'sql': s.sql, 'bindings': s.bindings}));

void schema(List<Map<String, dynamic>> stmts) {
  for (final s in stmts) {
    print(jsonEncode({'sql': s['sql'] as String, 'bindings': []}));
  }
}

`;

const PREAMBLE = `  final db = KnexQuery.forDialect(KnexDialect.postgres);
`;

export const EXAMPLES: Example[] = [
  {
    name: 'Basic SELECT',
    dialect: 'postgres',
    code: BOILERPLATE + `void main() {
${PREAMBLE}
  sql(
    db.from('users')
      .select(['id', 'email', 'age'])
      .where('active', true)
      .orderBy('age', 'asc')
      .limit(10)
      .toSQL(),
  );
}`,
  },

  {
    name: 'JOINs',
    dialect: 'postgres',
    code: BOILERPLATE + `void main() {
${PREAMBLE}
  // Users with total spend via LEFT JOIN
  sql(
    db.from('users')
      .select(['users.id', 'users.email'])
      .sum('orders.total as total_spent')
      .count('orders.id as order_count')
      .leftJoin('orders', 'users.id', 'orders.customer_id')
      .groupBy(['users.id', 'users.email'])
      .orderBy('total_spent', 'desc')
      .toSQL(),
  );
}`,
  },

  {
    name: 'WHERE Clauses',
    dialect: 'postgres',
    code: BOILERPLATE + `void main() {
${PREAMBLE}
  // whereIn + whereBetween
  sql(
    db.from('users')
      .whereIn('id', [1, 3])
      .whereBetween('age', [10, 20])
      .select(['id', 'email', 'age'])
      .toSQL(),
  );

  // orWhere
  sql(
    db.from('orders')
      .where('status', 'open')
      .orWhere('total', '>', 200)
      .select(['id', 'status', 'total'])
      .toSQL(),
  );
}`,
  },

  {
    name: 'Aggregation',
    dialect: 'postgres',
    code: BOILERPLATE + `void main() {
${PREAMBLE}
  // Orders per customer with total, filtered by HAVING
  sql(
    db.from('orders')
      .select(['customer_id'])
      .count('* as order_count')
      .sum('total as total_spent')
      .groupBy('customer_id')
      .having('total_spent', '>', 100)
      .orderBy('total_spent', 'desc')
      .toSQL(),
  );
}`,
  },

  {
    name: 'CTEs',
    dialect: 'postgres',
    code: BOILERPLATE + `void main() {
${PREAMBLE}
  // CTE: active users → ranked by age
  sql(
    db.queryBuilder()
      .withQuery(
        'active_users',
        db.from('users').where('active', true).select(['id', 'email', 'age']),
      )
      .from('active_users')
      .select('*')
      .orderBy('age', 'desc')
      .toSQL(),
  );
}`,
  },

  {
    name: 'Window Functions',
    dialect: 'postgres',
    code: BOILERPLATE + `void main() {
${PREAMBLE}
  // Rank users by age using row_number
  sql(
    db.from('users')
      .select(['id', 'email', 'age'])
      .rowNumber('age_rank', (a) => a.orderBy('age', 'desc'))
      .toSQL(),
  );
}`,
  },

  {
    name: 'Write Operations',
    dialect: 'postgres',
    code: BOILERPLATE + `void main() {
${PREAMBLE}
  // Insert a new user
  sql(db.from('users')
    .insert({'id': 10, 'email': 'new@example.com', 'age': 30, 'active': true})
    .toSQL());

  // Update an existing user
  sql(db.from('users')
    .where('id', 10)
    .update({'age': 31})
    .toSQL());

  // Verify
  sql(db.from('users')
    .where('id', 10)
    .select(['id', 'email', 'age'])
    .toSQL());
}`,
  },

  {
    name: 'Schema Builder',
    dialect: 'postgres',
    code: BOILERPLATE + `void main() {
${PREAMBLE}
  // Create a custom table
  schema(db.schemaBuilder().createTable('products', (t) {
    t.increments('id');
    t.string('name')..notNullable();
    t.decimal('price', 10, 2)..notNullable()..defaultTo(0);
    t.boolean('in_stock')..defaultTo(true);
  }).toSQL());

  // Seed it
  sql(db.from('products').insert([
    {'name': 'Widget',   'price': 9.99,  'in_stock': true},
    {'name': 'Gadget',   'price': 49.99, 'in_stock': false},
    {'name': 'Doohickey','price': 1.99,  'in_stock': true},
  ]).toSQL());

  // Query it
  sql(db.from('products')
    .where('in_stock', true)
    .orderBy('price', 'asc')
    .select('*')
    .toSQL());
}`,
  },

  {
    name: 'Subqueries',
    dialect: 'postgres',
    code: BOILERPLATE + `void main() {
${PREAMBLE}
  // Users who have at least one open order (WHERE IN subquery)
  sql(
    db.from('users')
      .whereIn(
        'id',
        db.from('orders').where('status', 'open').select(['customer_id']),
      )
      .select(['id', 'email'])
      .toSQL(),
  );
}`,
  },
];
