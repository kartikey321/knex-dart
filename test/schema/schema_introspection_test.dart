library;

import 'package:knex_dart/src/client/client.dart';
import 'package:knex_dart/src/client/knex_config.dart';
import 'package:knex_dart/src/formatter/formatter.dart';
import 'package:knex_dart/src/query/query_builder.dart';
import 'package:knex_dart/src/query/query_compiler.dart';
import 'package:knex_dart/src/schema/schema_builder.dart';
import 'package:knex_dart/src/schema/schema_compiler.dart';
import 'package:knex_dart/src/transaction/transaction.dart';
import 'package:test/test.dart';

class _IntrospectionClient extends Client {
  final String _driver;
  dynamic nextRawResult;
  String? lastSql;
  List<dynamic>? lastBindings;

  _IntrospectionClient({required String driver, KnexConfig? config})
    : _driver = driver,
      super(config ?? KnexConfig(client: driver, connection: {}));

  @override
  String get driverName => _driver;

  @override
  void initializeDriver() {}

  @override
  void initializePool([PoolConfig? poolConfig]) {}

  @override
  QueryBuilder queryBuilder() => QueryBuilder(this);

  @override
  QueryCompiler queryCompiler(QueryBuilder builder) =>
      QueryCompiler(this, builder);

  @override
  dynamic formatter(dynamic builder) => Formatter(this, builder);

  @override
  SchemaBuilder schemaBuilder() => SchemaBuilder(this);

  @override
  SchemaCompiler schemaCompiler(SchemaBuilder builder) =>
      SchemaCompiler(this, builder);

  @override
  Future<Transaction> transaction([TransactionConfig? config]) =>
      throw UnimplementedError();

  @override
  Future<dynamic> rawQuery(String sql, List<dynamic> bindings) async {
    lastSql = sql;
    lastBindings = List<dynamic>.from(bindings);
    return nextRawResult;
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    dynamic connection,
    String sql,
    List<dynamic> bindings,
  ) => throw UnimplementedError();

  @override
  Stream<Map<String, dynamic>> streamQuery(
    dynamic connection,
    String sql,
    List<dynamic> bindings,
  ) => throw UnimplementedError();

  @override
  Future<dynamic> acquireConnection() => throw UnimplementedError();

  @override
  Future<void> releaseConnection(dynamic connection) async {}

  @override
  String wrapIdentifierImpl(String identifier) {
    if (identifier == '*') return identifier;
    if (_driver == 'mysql' || _driver == 'mysql2' || _driver == 'mariadb') {
      return '`$identifier`';
    }
    return '"$identifier"';
  }

  @override
  String parameterPlaceholder(int index) => '?';

  @override
  String formatValue(dynamic value) => value.toString();
}

void main() {
  group('Schema Introspection', () {
    test('hasTable (pg): uses current_schema() when no schema set', () async {
      final client = _IntrospectionClient(driver: 'pg')
        ..nextRawResult = {
          'rows': [{}],
        };
      final exists = await client.schemaBuilder().hasTable('users');

      expect(exists, isTrue);
      expect(
        client.lastSql,
        'select * from information_schema.tables where table_name = ? and table_schema = current_schema()',
      );
      expect(client.lastBindings, ['users']);
    });

    test('hasTable (pg): respects withSchema()', () async {
      final client = _IntrospectionClient(driver: 'pg')
        ..nextRawResult = {
          'rows': [{}],
        };
      final exists = await client
          .schemaBuilder()
          .withSchema('audit')
          .hasTable('events');

      expect(exists, isTrue);
      expect(
        client.lastSql,
        'select * from information_schema.tables where table_name = ? and table_schema = ?',
      );
      expect(client.lastBindings, ['events', 'audit']);
    });

    test('hasTable (mysql): uses database() when no schema set', () async {
      final client = _IntrospectionClient(driver: 'mysql')
        ..nextRawResult = [{}];
      final exists = await client.schemaBuilder().hasTable('users');

      expect(exists, isTrue);
      expect(
        client.lastSql,
        'select * from information_schema.tables where table_name = ? and table_schema = database()',
      );
      expect(client.lastBindings, ['users']);
    });

    test('hasTable (sqlite): checks sqlite_master', () async {
      final client = _IntrospectionClient(driver: 'sqlite3')
        ..nextRawResult = [{}];
      final exists = await client.schemaBuilder().hasTable('users');

      expect(exists, isTrue);
      expect(
        client.lastSql,
        "select * from sqlite_master where type = 'table' and name = ? limit 1",
      );
      expect(client.lastBindings, ['users']);
    });

    test('hasColumn (pg): uses current_schema() when no schema set', () async {
      final client = _IntrospectionClient(driver: 'pg')
        ..nextRawResult = {
          'rows': [{}],
        };
      final exists = await client.schemaBuilder().hasColumn('users', 'email');

      expect(exists, isTrue);
      expect(
        client.lastSql,
        'select * from information_schema.columns where table_name = ? and column_name = ? and table_schema = current_schema()',
      );
      expect(client.lastBindings, ['users', 'email']);
    });

    test(
      'hasColumn (sqlite): uses pragma table_info and is case-insensitive',
      () async {
        final client = _IntrospectionClient(driver: 'sqlite3')
          ..nextRawResult = [
            {'name': 'ID'},
            {'name': 'Email'},
          ];
        final exists = await client.schemaBuilder().hasColumn('users', 'email');

        expect(exists, isTrue);
        expect(client.lastSql, 'PRAGMA table_info("users")');
        expect(client.lastBindings, isEmpty);
      },
    );

    test('hasColumn (mysql): uses SHOW COLUMNS and checks Field', () async {
      final client = _IntrospectionClient(driver: 'mysql')
        ..nextRawResult = [
          {'Field': 'id'},
          {'Field': 'email'},
        ];
      final exists = await client.schemaBuilder().hasColumn('users', 'email');

      expect(exists, isTrue);
      expect(client.lastSql, 'show columns from `users`');
      expect(client.lastBindings, isEmpty);
    });

    test('hasColumn (mssql): uses sys.columns/object_id lookup', () async {
      final client = _IntrospectionClient(driver: 'mssql')
        ..nextRawResult = [{}];
      final exists = await client
          .schemaBuilder()
          .withSchema('dbo')
          .hasColumn('users', 'email');

      expect(exists, isTrue);
      expect(
        client.lastSql,
        'select object_id from sys.columns where name = ? and object_id = object_id(?)',
      );
      expect(client.lastBindings, ['email', '"dbo"."users"']);
    });

    test('hasTable returns false when no rows', () async {
      final client = _IntrospectionClient(driver: 'pg')
        ..nextRawResult = {'rows': []};
      final exists = await client.schemaBuilder().hasTable('missing_table');

      expect(exists, isFalse);
    });
  });
}
