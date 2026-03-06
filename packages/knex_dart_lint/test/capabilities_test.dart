import 'package:knex_dart_capabilities/knex_dart_capabilities.dart';
import 'package:test/test.dart';

void main() {
  // ── Original 4 capabilities ───────────────────────────────────────────────

  test('postgres supports all MVP capabilities', () {
    expect(supportsCapability(KnexDialect.postgres, SqlCapability.returning), isTrue);
    expect(supportsCapability(KnexDialect.postgres, SqlCapability.fullOuterJoin), isTrue);
    expect(supportsCapability(KnexDialect.postgres, SqlCapability.lateralJoin), isTrue);
    expect(supportsCapability(KnexDialect.postgres, SqlCapability.onConflictMerge), isTrue);
  });

  test('mysql capability shape', () {
    expect(supportsCapability(KnexDialect.mysql, SqlCapability.returning), isFalse);
    expect(supportsCapability(KnexDialect.mysql, SqlCapability.fullOuterJoin), isFalse);
    expect(supportsCapability(KnexDialect.mysql, SqlCapability.lateralJoin), isTrue);
    expect(supportsCapability(KnexDialect.mysql, SqlCapability.onConflictMerge), isTrue);
  });

  test('sqlite capability shape', () {
    expect(supportsCapability(KnexDialect.sqlite, SqlCapability.returning), isFalse);
    expect(supportsCapability(KnexDialect.sqlite, SqlCapability.fullOuterJoin), isFalse);
    expect(supportsCapability(KnexDialect.sqlite, SqlCapability.lateralJoin), isFalse);
    expect(supportsCapability(KnexDialect.sqlite, SqlCapability.onConflictMerge), isTrue);
  });

  // ── Extended capabilities (cte, windowFunctions, json, intersectExcept) ───

  test('cte: all three dialects support it', () {
    expect(supportsCapability(KnexDialect.postgres, SqlCapability.cte), isTrue);
    expect(supportsCapability(KnexDialect.mysql, SqlCapability.cte), isTrue);
    expect(supportsCapability(KnexDialect.sqlite, SqlCapability.cte), isTrue);
  });

  test('windowFunctions: all three dialects support it', () {
    expect(supportsCapability(KnexDialect.postgres, SqlCapability.windowFunctions), isTrue);
    expect(supportsCapability(KnexDialect.mysql, SqlCapability.windowFunctions), isTrue);
    expect(supportsCapability(KnexDialect.sqlite, SqlCapability.windowFunctions), isTrue);
  });

  test('json: postgres and mysql support it, sqlite does not', () {
    expect(supportsCapability(KnexDialect.postgres, SqlCapability.json), isTrue);
    expect(supportsCapability(KnexDialect.mysql, SqlCapability.json), isTrue);
    expect(supportsCapability(KnexDialect.sqlite, SqlCapability.json), isFalse);
  });

  test('intersectExcept: postgres and sqlite support it, mysql does not', () {
    expect(supportsCapability(KnexDialect.postgres, SqlCapability.intersectExcept), isTrue);
    expect(supportsCapability(KnexDialect.mysql, SqlCapability.intersectExcept), isFalse);
    expect(supportsCapability(KnexDialect.sqlite, SqlCapability.intersectExcept), isTrue);
  });
}
