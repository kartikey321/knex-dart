import 'schema_ast.dart';

/// Maps JSON Schema documents into [KnexSchemaAst].
///
/// Supported shapes:
/// 1) Single table:
///    `{ "type": "object", "title": "users", "properties": { ... } }`
/// 2) Multi-table extension:
///    `{ "x-knex": { "tables": { "users": { ... }, "orders": { ... } } } }`
///
/// Per-property extensions are accepted under `x-knex`:
/// - `primary`, `unique`, `unsigned`
/// - `type` (Knex logical type override, e.g. `timestamp`, `jsonb`)
/// - `foreign`: `{ "table": "users", "column": "id", "onDelete": "cascade" }`
class JsonSchemaAdapter implements SchemaFormatAdapter {
  @override
  String get formatId => 'json-schema';

  @override
  bool canParse(dynamic input) {
    if (input is! Map) return false;
    if (input.containsKey(r'$schema')) return true;
    if (input.containsKey('properties')) return true;
    final xKnex = input['x-knex'];
    return xKnex is Map && xKnex['tables'] is Map;
  }

  @override
  KnexSchemaAst parse(dynamic input) {
    if (input is! Map) {
      throw ArgumentError('JSON schema input must be a Map');
    }

    final xKnex = input['x-knex'];
    if (xKnex is Map && xKnex['tables'] is Map) {
      final tables = <KnexTableAst>[];
      final tableMap = xKnex['tables'] as Map;
      tableMap.forEach((name, schema) {
        if (name is! String || schema is! Map) return;
        tables.add(
          _parseSingleTableSchema(
            schema.cast<String, dynamic>(),
            fallbackTableName: name,
          ),
        );
      });
      return KnexSchemaAst(tables: tables);
    }

    return KnexSchemaAst(
      tables: [_parseSingleTableSchema(input.cast<String, dynamic>())],
    );
  }

  KnexTableAst _parseSingleTableSchema(
    Map<String, dynamic> schema, {
    String? fallbackTableName,
  }) {
    final xKnex = schema['x-knex'];
    final tableFromExt = xKnex is Map ? xKnex['table'] : null;
    final title = schema['title'];
    final tableName =
        (tableFromExt is String && tableFromExt.isNotEmpty)
        ? tableFromExt
        : (title is String && title.isNotEmpty)
        ? title
        : fallbackTableName;

    if (tableName == null || tableName.isEmpty) {
      throw ArgumentError(
        'JSON schema table name missing. Provide title or x-knex.table.',
      );
    }

    final requiredSet = <String>{};
    final required = schema['required'];
    if (required is List) {
      for (final r in required) {
        if (r is String) requiredSet.add(r);
      }
    }

    final props = schema['properties'];
    if (props is! Map) {
      throw ArgumentError('JSON schema for table "$tableName" has no properties');
    }

    final columns = <KnexColumnAst>[];
    props.forEach((name, rawProp) {
      if (name is! String || rawProp is! Map) return;
      columns.add(_parseProperty(name, rawProp.cast<String, dynamic>(), requiredSet));
    });

    return KnexTableAst(name: tableName, columns: columns);
  }

  KnexColumnAst _parseProperty(
    String name,
    Map<String, dynamic> prop,
    Set<String> requiredSet,
  ) {
    final xKnex = prop['x-knex'];
    final x = xKnex is Map ? xKnex.cast<String, dynamic>() : const <String, dynamic>{};

    final type = _resolveColumnType(prop, x);
    final nullable = !_isRequiredNonNull(prop, requiredSet.contains(name));

    KnexForeignKeyAst? fk;
    final foreign = x['foreign'];
    if (foreign is Map) {
      final table = foreign['table'];
      final column = foreign['column'];
      if (table is String && column is String) {
        fk = KnexForeignKeyAst(
          table: table,
          column: column,
          onDelete: foreign['onDelete'] as String?,
          onUpdate: foreign['onUpdate'] as String?,
        );
      }
    }

    return KnexColumnAst(
      name: name,
      type: type,
      nullable: nullable,
      primary: x['primary'] == true,
      unique: x['unique'] == true,
      unsigned: x['unsigned'] == true,
      defaultValue: prop.containsKey('default') ? prop['default'] : null,
      length: prop['maxLength'] is int ? prop['maxLength'] as int : null,
      precision: x['precision'] is int ? x['precision'] as int : null,
      scale: x['scale'] is int ? x['scale'] as int : null,
      foreignKey: fk,
    );
  }

  KnexColumnType _resolveColumnType(
    Map<String, dynamic> prop,
    Map<String, dynamic> xKnex,
  ) {
    final override = xKnex['type'];
    if (override is String) {
      final mapped = _typeFromOverride(override);
      if (mapped != null) return mapped;
    }

    final jsonType = _extractJsonType(prop['type']);
    final format = prop['format'];

    if (jsonType == 'string') {
      if (format == 'uuid') return KnexColumnType.uuid;
      if (format == 'date') return KnexColumnType.date;
      if (format == 'date-time') return KnexColumnType.datetime;
      if (format == 'time') return KnexColumnType.time;
      if (prop['maxLength'] is int) return KnexColumnType.string;
      return KnexColumnType.text;
    }
    if (jsonType == 'integer') return KnexColumnType.integer;
    if (jsonType == 'number') return KnexColumnType.doublePrecision;
    if (jsonType == 'boolean') return KnexColumnType.boolean;
    if (jsonType == 'object' || jsonType == 'array') return KnexColumnType.json;

    return KnexColumnType.text;
  }

  String? _extractJsonType(dynamic typeValue) {
    if (typeValue is String) return typeValue;
    if (typeValue is List) {
      for (final t in typeValue) {
        if (t is String && t != 'null') return t;
      }
    }
    return null;
  }

  bool _isRequiredNonNull(Map<String, dynamic> prop, bool requiredByParent) {
    final typeValue = prop['type'];
    if (typeValue is List && typeValue.contains('null')) return false;
    return requiredByParent;
  }

  KnexColumnType? _typeFromOverride(String value) {
    switch (value) {
      case 'increments':
        return KnexColumnType.increments;
      case 'integer':
        return KnexColumnType.integer;
      case 'bigInteger':
        return KnexColumnType.bigInteger;
      case 'string':
        return KnexColumnType.string;
      case 'text':
        return KnexColumnType.text;
      case 'boolean':
        return KnexColumnType.boolean;
      case 'date':
        return KnexColumnType.date;
      case 'datetime':
        return KnexColumnType.datetime;
      case 'timestamp':
        return KnexColumnType.timestamp;
      case 'time':
        return KnexColumnType.time;
      case 'float':
        return KnexColumnType.floatType;
      case 'double':
        return KnexColumnType.doublePrecision;
      case 'decimal':
        return KnexColumnType.decimal;
      case 'binary':
        return KnexColumnType.binary;
      case 'json':
        return KnexColumnType.json;
      case 'jsonb':
        return KnexColumnType.jsonb;
      case 'uuid':
        return KnexColumnType.uuid;
      default:
        return null;
    }
  }
}
