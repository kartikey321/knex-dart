import 'package:knex_dart_capabilities/knex_dart_capabilities.dart';
import 'package:test/test.dart';

void main() {
  group('supportsCapability', () {
    test('returning is supported on postgres and sqlite (not mysql)', () {
      expect(
        supportsCapability(KnexDialect.postgres, SqlCapability.returning),
        isTrue,
      );
      expect(
        supportsCapability(KnexDialect.mysql, SqlCapability.returning),
        isFalse,
      );
      // SQLite >=3.35 supports RETURNING on INSERT/UPDATE (verified against
      // real knex.js) — the DELETE-specific exception to that lives as a
      // dialect carve-out in knex_dart's QueryCompiler, not here.
      expect(
        supportsCapability(KnexDialect.sqlite, SqlCapability.returning),
        isTrue,
      );
    });

    test('onConflictMerge is supported on postgres, mysql, sqlite', () {
      expect(
        supportsCapability(KnexDialect.postgres, SqlCapability.onConflictMerge),
        isTrue,
      );
      expect(
        supportsCapability(KnexDialect.mysql, SqlCapability.onConflictMerge),
        isTrue,
      );
      expect(
        supportsCapability(KnexDialect.sqlite, SqlCapability.onConflictMerge),
        isTrue,
      );
    });
  });

  group('dialectFromDriverName', () {
    test('maps known driver aliases', () {
      expect(dialectFromDriverName('pg'), KnexDialect.postgres);
      expect(dialectFromDriverName('postgresql'), KnexDialect.postgres);
      expect(dialectFromDriverName('mysql2'), KnexDialect.mysql);
      expect(dialectFromDriverName('sqlite3'), KnexDialect.sqlite);
      expect(dialectFromDriverName('mssql'), KnexDialect.mssql);
    });

    test('returns null for unknown driver', () {
      expect(dialectFromDriverName('not-a-real-driver'), isNull);
      expect(dialectFromDriverName(null), isNull);
    });
  });
}
