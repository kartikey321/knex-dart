/// Assembles a [DialectReport] from the roadmap, optionally folding in real
/// execution/behavioral results keyed by case id.
///
/// With no results supplied, every roadmap id gets [MechanicalStatus.
/// unclassified] — this is the honest, complete report before any adapter
/// exists: every id in the roadmap is accounted for, and none of them have
/// been claimed as covered. Once a driver adapter exists, its execution
/// results plug into the same function — this collector doesn't change
/// shape when that happens, only its inputs do.
library;

import 'report.dart';
import 'roadmap.dart';

DialectReport collectDialectReport({
  required ExecutableCasesRoadmap roadmap,
  required String dialect,
  Map<String, MechanicalResult> queryResults = const {},
  Map<String, MechanicalResult> schemaResults = const {},
  Map<String, List<BehavioralResult>> queryBehavioral = const {},
  Map<String, List<BehavioralResult>> schemaBehavioral = const {},
}) {
  final dialectRoadmap = roadmap.forDialect(dialect);

  return DialectReport(
    dialect: dialect,
    queryRows: [
      for (final id in dialectRoadmap.executableQueryIds)
        CaseReportRow(
          id: id,
          track: CorpusTrack.query,
          mechanical: queryResults[id] ?? MechanicalResult.unclassified,
          behavioral: queryBehavioral[id] ?? const [],
        ),
    ],
    schemaRows: [
      for (final id in dialectRoadmap.executableSchemaIds)
        CaseReportRow(
          id: id,
          track: CorpusTrack.schema,
          mechanical: schemaResults[id] ?? MechanicalResult.unclassified,
          behavioral: schemaBehavioral[id] ?? const [],
        ),
    ],
  );
}
