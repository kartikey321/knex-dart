import 'schema_builder.dart';
import 'table_builder.dart';

/// Canonical, dialect-neutral schema AST.
///
/// External schema formats (JSON Schema, OpenAPI, etc.) should map into this
/// structure first. SQL emission remains the responsibility of the existing
/// Knex schema compiler pipeline.
class KnexSchemaAst {
  final List<KnexTableAst> tables;

  const KnexSchemaAst({required this.tables});
}

/// One table in the schema AST.
class KnexTableAst {
  final String name;
  final List<KnexColumnAst> columns;

  const KnexTableAst({required this.name, required this.columns});
}

/// Supported logical column kinds.
enum KnexColumnType {
  increments,
  integer,
  bigInteger,
  string,
  text,
  boolean,
  date,
  datetime,
  timestamp,
  time,
  floatType,
  doublePrecision,
  decimal,
  binary,
  json,
  jsonb,
  uuid,
}

/// Optional foreign key reference metadata.
class KnexForeignKeyAst {
  final String table;
  final String column;
  final String? onDelete;
  final String? onUpdate;

  const KnexForeignKeyAst({
    required this.table,
    required this.column,
    this.onDelete,
    this.onUpdate,
  });
}

/// One column definition in the schema AST.
class KnexColumnAst {
  final String name;
  final KnexColumnType type;
  final bool nullable;
  final bool primary;
  final bool unique;
  final bool unsigned;
  final dynamic defaultValue;
  final int? length;
  final int? precision;
  final int? scale;
  final KnexForeignKeyAst? foreignKey;

  const KnexColumnAst({
    required this.name,
    required this.type,
    this.nullable = true,
    this.primary = false,
    this.unique = false,
    this.unsigned = false,
    this.defaultValue,
    this.length,
    this.precision,
    this.scale,
    this.foreignKey,
  });
}

/// Adapter contract for translating external schema formats into [KnexSchemaAst].
abstract class ExternalSchemaAdapter {
  /// Human-readable format id, e.g. `json-schema`.
  String get formatId;

  /// Whether this adapter can parse the given [input].
  bool canParse(dynamic input);

  /// Parse input and produce canonical Knex schema AST.
  KnexSchemaAst parse(dynamic input);
}

/// Backward-compatible alias for existing code and docs.
abstract class SchemaFormatAdapter implements ExternalSchemaAdapter {}

/// Simple adapter registry for plugin-style schema format resolution.
class SchemaAdapterRegistry {
  final List<ExternalSchemaAdapter> _adapters = [];

  void register(ExternalSchemaAdapter adapter) {
    _adapters.add(adapter);
  }

  void registerExternal(ExternalSchemaAdapter adapter) {
    _adapters.add(adapter);
  }

  ExternalSchemaAdapter resolve(dynamic input) {
    for (final adapter in _adapters) {
      if (adapter.canParse(input)) return adapter;
    }
    throw ArgumentError('No schema adapter could parse input');
  }

  KnexSchemaAst parse(dynamic input) {
    return resolve(input).parse(input);
  }
}

/// Projects [KnexSchemaAst] into the existing [SchemaBuilder] API.
class SchemaAstProjector {
  static SchemaBuilder projectToCreateTables(
    SchemaBuilder schema,
    KnexSchemaAst ast, {
    bool ifNotExists = false,
  }) {
    for (final table in ast.tables) {
      void build(TableBuilder t) {
        for (final col in table.columns) {
          final cb = _addColumn(t, col);
          if (!col.nullable) cb.notNullable();
          if (col.defaultValue != null) cb.defaultTo(col.defaultValue);
          if (col.unique) cb.unique();
          if (col.primary) cb.primary();
          if (col.unsigned) cb.unsigned();
          final fk = col.foreignKey;
          if (fk != null) {
            cb.references(fk.column).inTable(fk.table);
            if (fk.onDelete != null) cb.onDelete(fk.onDelete!);
            if (fk.onUpdate != null) cb.onUpdate(fk.onUpdate!);
          }
        }
      }

      if (ifNotExists) {
        schema.createTableIfNotExists(table.name, build);
      } else {
        schema.createTable(table.name, build);
      }
    }
    return schema;
  }

  static dynamic _addColumn(TableBuilder t, KnexColumnAst col) {
    switch (col.type) {
      case KnexColumnType.increments:
        return t.increments(col.name);
      case KnexColumnType.integer:
        return t.integer(col.name);
      case KnexColumnType.bigInteger:
        return t.bigInteger(col.name);
      case KnexColumnType.string:
        return t.string(col.name, col.length ?? 255);
      case KnexColumnType.text:
        return t.text(col.name);
      case KnexColumnType.boolean:
        return t.boolean(col.name);
      case KnexColumnType.date:
        return t.date(col.name);
      case KnexColumnType.datetime:
        return t.datetime(col.name);
      case KnexColumnType.timestamp:
        return t.timestamp(col.name);
      case KnexColumnType.time:
        return t.time(col.name);
      case KnexColumnType.floatType:
        return t.float(col.name);
      case KnexColumnType.doublePrecision:
        return t.doublePrecision(col.name);
      case KnexColumnType.decimal:
        return t.decimal(col.name, col.precision ?? 8, col.scale ?? 2);
      case KnexColumnType.binary:
        return t.binary(col.name);
      case KnexColumnType.json:
        return t.json(col.name);
      case KnexColumnType.jsonb:
        return t.jsonb(col.name);
      case KnexColumnType.uuid:
        return t.uuid(col.name);
    }
  }
}
