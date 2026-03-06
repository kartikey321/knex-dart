import 'package:knex_dart_capabilities/knex_dart_capabilities.dart';
import 'package:test/test.dart';

void main() {
  group('supportsCapability', () {
    test('returning is supported on postgres only', () {
      expect(
        supportsCapability(KnexDialect.postgres, SqlCapability.returning),
        isTrue,
      );
      expect(
        supportsCapability(KnexDialect.mysql, SqlCapability.returning),
        isFalse,
      );
      expect(
        supportsCapability(KnexDialect.sqlite, SqlCapability.returning),
        isFalse,
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
    });

    test('returns null for unknown driver', () {
      expect(dialectFromDriverName('mssql'), isNull);
      expect(dialectFromDriverName(null), isNull);
    });
  });
}
