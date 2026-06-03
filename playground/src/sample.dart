import 'dart:convert';
import 'package:knex_dart/knex_dart.dart';
import 'package:knex_dart_capabilities/knex_dart_capabilities.dart';

// Emit a query sentinel — playground executes it against the embedded DB.
void sql(SqlString s) =>
    print(jsonEncode({'sql': s.sql, 'bindings': s.bindings}));

// Emit schema builder statements (toSQL() returns List<Map<String,dynamic>>).
void schema(List<Map<String, dynamic>> statements) {
  for (final s in statements) {
    print(
      jsonEncode({
        'sql': s['sql'] as String,
        'bindings': (s['bindings'] as List?)?.cast<dynamic>() ?? [],
      }),
    );
  }
}

void main() {
  final db = KnexQuery.forDialect(KnexDialect.postgres);

  sql(
    db
        .from('users')
        .select(['id', 'email', 'age'])
        .where('active', true)
        .orderBy('age', 'asc')
        .limit(10)
        .toSQL(),
  );
}
