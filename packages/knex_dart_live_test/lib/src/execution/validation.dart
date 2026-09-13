/// Cross-checks the roadmap against the corpus it's supposed to describe.
///
/// `EXECUTABLE_CASES.json` and the Dart corpus (`query_cases.dart`/
/// `schema_cases.dart`) are meant to stay in lockstep by construction (the
/// JS reference generator mirrors the Dart corpus 1:1 by id, and
/// `parity_test.dart`'s own drift-guard test already checks that pairing).
/// This is a second, independent check scoped to what the live-execution
/// runner actually needs: every *executable* id in the roadmap must
/// correspond to a real corpus entry, or the runner would silently have
/// nothing to build for it. A live-execution package might run without
/// `parity_test.dart` ever having run in the same process, so this isn't
/// redundant — it's the same invariant, enforced at the point that
/// actually depends on it.
library;

import 'roadmap.dart';

class RoadmapCorpusMismatch implements Exception {
  final String message;
  const RoadmapCorpusMismatch(this.message);

  @override
  String toString() => 'RoadmapCorpusMismatch: $message';
}

/// Throws [RoadmapCorpusMismatch] if [roadmap]'s executable ids for
/// [dialect] reference anything absent from [queryCorpusIds]/
/// [schemaCorpusIds].
void validateRoadmapAgainstCorpus({
  required ExecutableCasesRoadmap roadmap,
  required String dialect,
  required Set<String> queryCorpusIds,
  required Set<String> schemaCorpusIds,
}) {
  final dialectRoadmap = roadmap.forDialect(dialect);

  final missingQuery = dialectRoadmap.executableQueryIds
      .toSet()
      .difference(queryCorpusIds);
  final missingSchema = dialectRoadmap.executableSchemaIds
      .toSet()
      .difference(schemaCorpusIds);

  if (missingQuery.isEmpty && missingSchema.isEmpty) return;

  final parts = <String>[];
  if (missingQuery.isNotEmpty) {
    parts.add('query ids missing from the corpus: $missingQuery');
  }
  if (missingSchema.isNotEmpty) {
    parts.add('schema ids missing from the corpus: $missingSchema');
  }
  throw RoadmapCorpusMismatch(
    'Roadmap for "$dialect" references ids the corpus does not have — '
    'the roadmap and corpus have drifted apart (regenerate '
    'EXECUTABLE_CASES.json, or check for a stale/renamed corpus id): '
    '${parts.join("; ")}',
  );
}
