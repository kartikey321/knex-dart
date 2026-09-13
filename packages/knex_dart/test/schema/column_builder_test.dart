import 'package:knex_dart/src/schema/column_builder.dart';
import 'package:knex_dart/src/raw.dart';
import 'package:test/test.dart';

import '../mocks/mock_client.dart';

void main() {
  group('ColumnBuilder - modifiers', () {
    test('nullable() sets column back to nullable', () {
      final col = ColumnBuilder('email', 'varchar(255)')
        ..notNullable()
        ..nullable();
      // nullable is default — toSQL should not contain 'not null'
      expect(col.toSQL(), isNot(contains('not null')));
    });

    test('primary() sets isPrimary flag', () {
      final col = ColumnBuilder('id', 'integer')..primary();
      expect(col.isPrimary, isTrue);
    });

    test('unique() sets isUnique flag', () {
      final col = ColumnBuilder('email', 'varchar(255)')..unique();
      expect(col.isUnique, isTrue);
    });

    test('references() + inTable() set FK fields', () {
      final col = ColumnBuilder('user_id', 'integer')
        ..references('id')
        ..inTable('users');
      expect(col.referencesColumn, equals('id'));
      expect(col.referencesTable, equals('users'));
    });

    test('onDelete() uppercases and stores action', () {
      final col = ColumnBuilder('user_id', 'integer')..onDelete('cascade');
      expect(col.onDeleteAction, equals('CASCADE'));
    });

    test('onUpdate() uppercases and stores action', () {
      final col = ColumnBuilder('user_id', 'integer')..onUpdate('restrict');
      expect(col.onUpdateAction, equals('RESTRICT'));
    });
  });

  group('ColumnBuilder - toSQL default branches', () {
    test('defaultTo(null) emits "default null"', () {
      final col = ColumnBuilder('deleted_at', 'timestamptz')..defaultTo(null);
      expect(col.toSQL(), contains('default null'));
    });

    test('defaultTo(Raw) emits raw SQL expression', () {
      final client = MockClient();
      final col = ColumnBuilder('created_at', 'timestamptz')
        ..defaultTo(Raw(client).set('CURRENT_TIMESTAMP'));
      expect(col.toSQL(), contains('default CURRENT_TIMESTAMP'));
    });

    test('defaultTo(true) emits "default \'1\'"', () {
      final col = ColumnBuilder('active', 'boolean')..defaultTo(true);
      expect(col.toSQL(), contains("default '1'"));
    });

    test('defaultTo(false) emits "default \'0\'"', () {
      final col = ColumnBuilder('active', 'boolean')..defaultTo(false);
      expect(col.toSQL(), contains("default '0'"));
    });

    test('defaultTo(num) emits numeric literal', () {
      final col = ColumnBuilder('score', 'integer')..defaultTo(42);
      expect(col.toSQL(), contains('default 42'));
    });

    test('defaultTo(String) emits quoted string', () {
      final col = ColumnBuilder('status', 'varchar(50)')..defaultTo('active');
      expect(col.toSQL(), contains("default 'active'"));
    });

    test(
      'defaultTo with arbitrary object falls through to a quoted, '
      "escaped toString() (matches knex.js's _escapeBinding fallback)",
      () {
        final col = ColumnBuilder(
          'meta',
          'json',
        )..defaultTo(_Stringify('{}'));
        expect(col.toSQL(), contains("default '{}'"));
      },
    );

    test('defaultTo(String) with an embedded quote is escaped', () {
      final col = ColumnBuilder(
        'name',
        'varchar(50)',
      )..defaultTo("O'Brien");
      expect(col.toSQL(), contains("default 'O''Brien'"));
    });

    test('defaultTo(Map) on a json column JSON-encodes the value', () {
      final col = ColumnBuilder(
        'meta',
        'json',
        isJson: true,
      )..defaultTo({'active': true});
      expect(col.toSQL(), contains('default \'{"active":true}\''));
    });

    test('defaultTo(List) on a jsonb column JSON-encodes the value', () {
      final col = ColumnBuilder(
        'tags',
        'jsonb',
        isJson: true,
      )..defaultTo(['a', 'b']);
      expect(col.toSQL(), contains('default \'["a","b"]\''));
    });

    test(
      'defaultTo(Map) on a Redshift jsonb column (mapped to varchar(max)) '
      'still JSON-encodes — isJson tracks the logical type, not the mapped '
      'SQL type string (verified against real knex.js)',
      () {
        final col = ColumnBuilder(
          'c',
          'varchar(max)',
          isJson: true,
        )..defaultTo({
            'x': ['y'],
          });
        expect(
          col.toSQL(dialect: 'redshift'),
          contains('default \'{"x":["y"]}\''),
        );
      },
    );

    test(
      'defaultTo(String) with a backslash is escaped per-dialect: Postgres '
      "doubles it and adds an E-prefix (verified against real knex.js)",
      () {
        final col = ColumnBuilder('s', 'varchar(255)')..defaultTo(r'a\b');
        expect(col.toSQL(dialect: 'pg'), contains(r"default E'a\\b'"));
      },
    );

    test(
      'defaultTo(String) with a backslash on MySQL is escaped without an '
      'E-prefix (verified against real knex.js)',
      () {
        final col = ColumnBuilder('s', 'varchar(255)')..defaultTo(r'a\b');
        expect(col.toSQL(dialect: 'mysql'), contains(r"default 'a\\b'"));
      },
    );

    test(
      'defaultTo(String) with a newline on MySQL uses a C-style escape '
      '(verified against real knex.js)',
      () {
        final col = ColumnBuilder('s', 'varchar(255)')..defaultTo('a\nb');
        expect(col.toSQL(dialect: 'mysql'), contains(r"default 'a\nb'"));
      },
    );

    test(
      "defaultTo(String) with a backslash on SQLite is left unescaped — "
      'matches knex.js falling back to the base Client (no backslash '
      'handling) for dialects without their own _escapeBinding',
      () {
        final col = ColumnBuilder('s', 'varchar(255)')..defaultTo(r'a\b');
        expect(col.toSQL(dialect: 'sqlite'), contains(r"default 'a\b'"));
      },
    );
  });

  group('ColumnBuilder - toSQL dialect and wrap', () {
    test('unsigned added for mysql dialect', () {
      final col = ColumnBuilder('count', 'integer')..unsigned();
      expect(col.toSQL(dialect: 'mysql'), contains('unsigned'));
    });

    test('unsigned NOT added for pg dialect', () {
      final col = ColumnBuilder('count', 'integer')..unsigned();
      expect(col.toSQL(dialect: 'pg'), isNot(contains('unsigned')));
    });

    test('custom wrap function is applied to column name', () {
      final col = ColumnBuilder('name', 'varchar(255)');
      expect(col.toSQL(wrap: (v) => '[$v]'), startsWith('[name]'));
    });

    test('not null emitted when notNullable()', () {
      final col = ColumnBuilder('email', 'varchar(255)')..notNullable();
      expect(col.toSQL(), contains('not null'));
    });
  });
}

/// Helper to test the `else` branch in defaultTo (arbitrary object).
class _Stringify {
  final String _value;
  _Stringify(this._value);
  @override
  String toString() => _value;
}
