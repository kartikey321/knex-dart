import 'package:knex_dart/knex_dart.dart';
import 'package:test/test.dart';

import '../mocks/mock_client.dart';

void main() {
  group('SchemaAdapterRegistry', () {
    test('registerExternal resolves adapter for input', () {
      final registry = SchemaAdapterRegistry();
      registry.registerExternal(JsonSchemaAdapter());

      final input = <String, dynamic>{
        r'$schema': 'https://json-schema.org/draft/2020-12/schema',
        'title': 'users',
        'type': 'object',
        'properties': {
          'id': {'type': 'integer'},
        },
      };

      final adapter = registry.resolve(input);
      expect(adapter.formatId, 'json-schema');
      expect(registry.parse(input).tables.single.name, 'users');
    });
  });

  group('JsonSchemaAdapter', () {
    test('parses single-table JSON schema into KnexSchemaAst', () {
      final adapter = JsonSchemaAdapter();
      final input = <String, dynamic>{
        r'$schema': 'https://json-schema.org/draft/2020-12/schema',
        'title': 'users',
        'type': 'object',
        'required': ['id', 'email'],
        'properties': {
          'id': {
            'type': 'integer',
            'x-knex': {'primary': true},
          },
          'email': {'type': 'string', 'maxLength': 255},
          'is_active': {'type': 'boolean', 'default': true},
          'profile': {'type': 'object'},
        },
      };

      final ast = adapter.parse(input);
      expect(ast.tables.length, 1);
      expect(ast.tables.first.name, 'users');
      expect(ast.tables.first.columns.length, 4);

      final id = ast.tables.first.columns.firstWhere((c) => c.name == 'id');
      expect(id.type, KnexColumnType.integer);
      expect(id.primary, isTrue);
      expect(id.nullable, isFalse);

      final email = ast.tables.first.columns.firstWhere(
        (c) => c.name == 'email',
      );
      expect(email.type, KnexColumnType.string);
      expect(email.length, 255);
      expect(email.nullable, isFalse);

      final profile = ast.tables.first.columns.firstWhere(
        (c) => c.name == 'profile',
      );
      expect(profile.type, KnexColumnType.json);
      expect(profile.nullable, isTrue);
    });

    test('parses x-knex multi-table extension', () {
      final adapter = JsonSchemaAdapter();
      final input = <String, dynamic>{
        'x-knex': {
          'tables': {
            'users': {
              'type': 'object',
              'properties': {
                'id': {
                  'type': 'integer',
                  'x-knex': {'primary': true},
                },
              },
            },
            'orders': {
              'type': 'object',
              'properties': {
                'id': {'type': 'integer'},
                'user_id': {
                  'type': 'integer',
                  'x-knex': {
                    'foreign': {'table': 'users', 'column': 'id'},
                  },
                },
              },
            },
          },
        },
      };

      final ast = adapter.parse(input);
      expect(ast.tables.map((t) => t.name), containsAll(['users', 'orders']));
      final orders = ast.tables.firstWhere((t) => t.name == 'orders');
      final userId = orders.columns.firstWhere((c) => c.name == 'user_id');
      expect(userId.foreignKey, isNotNull);
      expect(userId.foreignKey!.table, 'users');
      expect(userId.foreignKey!.column, 'id');
    });
  });

  group('SchemaAstProjector', () {
    test('projects AST into SchemaBuilder createTable flow', () {
      final ast = KnexSchemaAst(
        tables: [
          KnexTableAst(
            name: 'users',
            columns: const [
              KnexColumnAst(
                name: 'id',
                type: KnexColumnType.increments,
                nullable: false,
              ),
              KnexColumnAst(
                name: 'email',
                type: KnexColumnType.string,
                length: 150,
                nullable: false,
                unique: true,
              ),
              KnexColumnAst(name: 'created_at', type: KnexColumnType.datetime),
            ],
          ),
        ],
      );

      final client = MockClient(driverName: 'pg');
      final schema = client.schemaBuilder();
      SchemaAstProjector.projectToCreateTables(schema, ast);
      final sql = schema.toSQL();

      expect(sql, isNotEmpty);
      expect(sql.first['sql'], contains('create table "users"'));
      expect(sql.first['sql'], contains('"email" varchar(150) not null'));
    });
  });
}
