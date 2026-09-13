/// Cross-checks the fixture-link table and the unsupported-engine allowlist
/// against the corpus and each other, so a stale or contradictory entry
/// fails loudly instead of silently misreporting.
library;

import 'fixture_links.dart';
import 'fixture_profile.dart';
import 'unsupported_engine_allowlist.dart';

class FixtureLinkMismatch implements Exception {
  final String message;
  const FixtureLinkMismatch(this.message);

  @override
  String toString() => 'FixtureLinkMismatch: $message';
}

/// Validates, for [dialect]:
/// - every linked case id exists in [corpusIds]
/// - every linked profile id is a known [FixtureProfileRef]
/// - every allowlisted case id exists in [corpusIds]
/// - no case id is both fixture-linked and allowlisted as unsupported —
///   those are contradictory claims about the same id.
void validateFixtureData({
  required String dialect,
  required Set<String> corpusIds,
}) {
  final links = fixtureLinksByDialect[dialect] ?? const {};
  final allowlist = unsupportedEngineAllowlist[dialect] ?? const {};
  final knownProfileIds = knownFixtureProfiles.map((p) => p.id).toSet();

  final problems = <String>[];

  final missingLinkedIds = links.keys.toSet().difference(corpusIds);
  if (missingLinkedIds.isNotEmpty) {
    problems.add(
      'fixture-linked ids missing from the corpus: $missingLinkedIds',
    );
  }

  final unknownProfiles = links.values.toSet().difference(knownProfileIds);
  if (unknownProfiles.isNotEmpty) {
    problems.add(
      'fixture links reference unknown profile ids: $unknownProfiles',
    );
  }

  final missingAllowlistIds = allowlist.keys.toSet().difference(corpusIds);
  if (missingAllowlistIds.isNotEmpty) {
    problems.add(
      'unsupportedEngine-allowlisted ids missing from the corpus: '
      '$missingAllowlistIds',
    );
  }

  final overlap = links.keys.toSet().intersection(allowlist.keys.toSet());
  if (overlap.isNotEmpty) {
    problems.add(
      'ids both fixture-linked and unsupportedEngine-allowlisted for '
      '"$dialect" — contradictory: $overlap',
    );
  }

  if (problems.isEmpty) return;
  throw FixtureLinkMismatch(
    'Fixture data for "$dialect" is inconsistent: ${problems.join("; ")}',
  );
}
