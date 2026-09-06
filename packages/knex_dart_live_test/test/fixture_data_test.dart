import 'package:knex_dart_live_test/knex_dart_live_test.dart';
import 'package:test/test.dart';

void main() {
  // Every dialect that has fixture-linking work at all — new dialects
  // extend this set automatically since both maps are keyed by dialect,
  // so a new dialect's data gets the same standing checks for free.
  final dialects = {
    ...fixtureLinksByDialect.keys,
    ...unsupportedEngineAllowlist.keys,
  };

  group('fixture data', () {
    for (final dialect in dialects) {
      test('$dialect fixture links and unsupported-engine allowlist are '
          'internally consistent with the real corpus', () {
        validateFixtureData(
          dialect: dialect,
          corpusIds: queryCorpusCases.keys.toSet(),
        );
      });

      test('every fixture-linked id for $dialect is not also in the '
          'unsupported-engine allowlist', () {
        final links = fixtureLinksByDialect[dialect] ?? const {};
        final allowlist = unsupportedEngineAllowlist[dialect] ?? const {};
        expect(
          links.keys.toSet().intersection(allowlist.keys.toSet()),
          isEmpty,
        );
      });
    }

    test('table/dotted-schema is deliberately unlinked for postgres — '
        'explicit schema qualifiers bypass search_path isolation', () {
      final links = fixtureLinksByDialect['postgres']!;
      expect(links.containsKey('table/dotted-schema'), false);
    });
  });
}
