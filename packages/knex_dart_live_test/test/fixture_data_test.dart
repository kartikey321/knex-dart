import 'package:knex_dart_live_test/knex_dart_live_test.dart';
import 'package:test/test.dart';

void main() {
  group('fixture data', () {
    test('postgres fixture links and unsupported-engine allowlist are '
        'internally consistent with the real corpus', () {
      validateFixtureData(
        dialect: 'postgres',
        corpusIds: queryCorpusCases.keys.toSet(),
      );
    });

    test('every fixture-linked id for postgres is not also in the '
        'unsupported-engine allowlist', () {
      final links = fixtureLinksByDialect['postgres']!;
      final allowlist = unsupportedEngineAllowlist['postgres']!;
      expect(links.keys.toSet().intersection(allowlist.keys.toSet()), isEmpty);
    });

    test('table/dotted-schema is deliberately unlinked — explicit schema '
        'qualifiers bypass search_path isolation', () {
      final links = fixtureLinksByDialect['postgres']!;
      expect(links.containsKey('table/dotted-schema'), false);
    });
  });
}
