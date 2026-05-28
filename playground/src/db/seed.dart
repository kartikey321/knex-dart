import 'dart:convert';
import 'package:knex_dart/knex_dart.dart';
import 'package:knex_dart_capabilities/knex_dart_capabilities.dart';

// Emits a SQL sentinel the playground picks up and executes.
void _sql(String sql, [List<dynamic> bindings = const []]) =>
    print(jsonEncode({'sql': sql, 'bindings': bindings}));

void _schema(List<Map<String, dynamic>> stmts) {
  for (final s in stmts) {
    _sql(s['sql'] as String);
  }
}

void main() {
  // Dialect is injected at runtime by the playground seed runner.
  // ignore: undefined_identifier
  final dialectStr = const String.fromEnvironment('DIALECT', defaultValue: 'sqlite');
  final dialect = dialectStr == 'postgres' ? KnexDialect.postgres
      : dialectStr == 'mysql' ? KnexDialect.mysql
      : KnexDialect.sqlite;

  final db = KnexQuery.forDialect(dialect);

  _schema(db.schemaBuilder().createTableIfNotExists('users', (t) {
    t.increments('id');
    t.string('email')..notNullable();
    t.integer('age')..notNullable();
    t.boolean('active')..notNullable()..defaultTo(true);
  }).toSQL());

  _schema(db.schemaBuilder().createTableIfNotExists('orders', (t) {
    t.increments('id');
    t.integer('customer_id')..notNullable();
    t.string('status')..notNullable();
    t.decimal('total', 10, 2)..notNullable();
    t.timestamp('created_at')..notNullable();
  }).toSQL());

  final insertUsers = db.from('users').insert([
    {'id': 1, 'email': 'a@x.com', 'age': 17, 'active': true},
    {'id': 2, 'email': 'b@x.com', 'age': 21, 'active': false},
    {'id': 3, 'email': 'c@x.com', 'age': 16, 'active': true},
  ]).toSQL();
  _sql(insertUsers.sql, insertUsers.bindings);

  final insertOrders = db.from('orders').insert([
    {'id': 1, 'customer_id': 1, 'status': 'open',   'total': 120.5, 'created_at': '2026-03-01T12:00:00Z'},
    {'id': 2, 'customer_id': 2, 'status': 'closed',  'total': 80.0,  'created_at': '2026-03-03T12:00:00Z'},
    {'id': 3, 'customer_id': 1, 'status': 'open',   'total': 500.0, 'created_at': '2026-03-05T12:00:00Z'},
  ]).toSQL();
  _sql(insertOrders.sql, insertOrders.bindings);
}
