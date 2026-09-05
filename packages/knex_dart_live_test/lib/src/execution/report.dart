/// The live-execution report model: a typed, per-id accounting of every
/// case in the roadmap, kept strictly in two tiers that are never
/// conflated — "executed without error" (a real database accepted and
/// completed the built statement under a declared fixture) and
/// "behaviorally verified" (a human wrote and passed an assertion on an
/// observable property). A successful aggregate query does not prove its
/// aggregate value is correct; a successful lock statement does not prove
/// it blocks correctly. Every rendering of this report keeps both numbers
/// visible and separately labeled — neither is ever called "coverage" on
/// its own.
library;

import 'dart:convert';
import 'dart:io';

/// The mechanical outcome for one case id under one dialect. Every id in
/// the roadmap gets exactly one of these — there is no code path where an
/// id is simply absent from a report.
enum MechanicalStatus {
  /// A real database accepted and completed the built statement under its
  /// declared fixture. Proves nothing about the returned data being
  /// correct — see [BehavioralResult] for that.
  executedWithoutError,

  /// The database rejected the built statement, or it threw unexpectedly.
  /// This is the default read for any live failure — see
  /// [MechanicalStatus.unsupportedEngine] for the one legitimate exception.
  executionFailed,

  /// No fixture profile has been linked to this case id for this dialect
  /// yet. The honest default — never silently run against a guessed or
  /// overly-permissive schema.
  unclassified,

  /// A fixture profile decision was made and explicitly deferred, with a
  /// reason (e.g. the case needs a profile shape nobody has written yet).
  /// Distinct from [unclassified]: this is a reviewed, documented decision,
  /// not an oversight.
  deferredFixture,

  /// The case genuinely cannot run against this engine, and a reviewed,
  /// versioned entry exists explaining why (mirroring the parity harness's
  /// own allowlist ratchet — the entry must keep reproducing the same
  /// failure shape or the test fails, demanding re-triage). This status is
  /// NEVER a live adapter's own guess at failure time — self-reporting
  /// "unsupported" on any failure would let real defects launder
  /// themselves through this label. It exists to prevent this framework
  /// from becoming a place bugs go to hide.
  unsupportedEngine,

  /// No live connection exists for this dialect at all (missing
  /// credentials, no emulator, etc.) — an honest, visible infrastructure
  /// gap, not a silently missing row.
  environmentUnavailable,
}

/// Which corpus a case id came from — query-builder or schema-DDL. The two
/// tracks have different roadmap denominators and different validation
/// semantics (only query cases carry an `expectedMethod`).
enum CorpusTrack { query, schema }

/// The mechanical result for one case: its status plus whatever detail
/// explains it (the actual error text, the deferral reason, which fixture
/// profile it ran under). [detail] must always be present for anything
/// other than [MechanicalStatus.executedWithoutError] or
/// [MechanicalStatus.unclassified] — a bare "failed" with no evidence is
/// not an acceptable report row.
class MechanicalResult {
  final MechanicalStatus status;
  final String? detail;
  final String? fixtureProfile;

  const MechanicalResult(this.status, {this.detail, this.fixtureProfile});

  static const MechanicalResult unclassified = MechanicalResult(
    MechanicalStatus.unclassified,
  );

  Map<String, dynamic> toJson() => {
    'status': status.name,
    if (detail != null) 'detail': detail,
    if (fixtureProfile != null) 'fixtureProfile': fixtureProfile,
  };
}

/// One behavioral assertion's outcome — a case may have zero, one, or
/// several of these (e.g. one proving dedup, another proving row count),
/// independent of and in addition to its single [MechanicalResult].
class BehavioralResult {
  final String description;
  final bool passed;
  final String? failureDetail;

  const BehavioralResult({
    required this.description,
    required this.passed,
    this.failureDetail,
  });

  Map<String, dynamic> toJson() => {
    'description': description,
    'passed': passed,
    if (failureDetail != null) 'failureDetail': failureDetail,
  };
}

/// One roadmap id's full report row: its single mechanical status plus
/// however many behavioral results have been registered against it.
class CaseReportRow {
  final String id;
  final CorpusTrack track;
  final MechanicalResult mechanical;
  final List<BehavioralResult> behavioral;

  const CaseReportRow({
    required this.id,
    required this.track,
    required this.mechanical,
    this.behavioral = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'track': track.name,
    'mechanical': mechanical.toJson(),
    'behavioral': behavioral.map((b) => b.toJson()).toList(),
  };
}

/// Aggregate counts for one track (query or schema) within one dialect.
/// Deliberately flat and exhaustive — every roadmap id for this track
/// falls into exactly one mechanical bucket, so the buckets always sum to
/// [roadmapExecutable].
class TrackSummary {
  final int roadmapExecutable;
  final int executedWithoutError;
  final int executionFailed;
  final int unclassified;
  final int deferredFixture;
  final int unsupportedEngine;
  final int environmentUnavailable;
  final int behaviorSpecsRegistered;
  final int behaviorSpecsPassed;

  const TrackSummary({
    required this.roadmapExecutable,
    required this.executedWithoutError,
    required this.executionFailed,
    required this.unclassified,
    required this.deferredFixture,
    required this.unsupportedEngine,
    required this.environmentUnavailable,
    required this.behaviorSpecsRegistered,
    required this.behaviorSpecsPassed,
  });

  factory TrackSummary.from(List<CaseReportRow> rows) {
    int count(MechanicalStatus s) =>
        rows.where((r) => r.mechanical.status == s).length;
    return TrackSummary(
      roadmapExecutable: rows.length,
      executedWithoutError: count(MechanicalStatus.executedWithoutError),
      executionFailed: count(MechanicalStatus.executionFailed),
      unclassified: count(MechanicalStatus.unclassified),
      deferredFixture: count(MechanicalStatus.deferredFixture),
      unsupportedEngine: count(MechanicalStatus.unsupportedEngine),
      environmentUnavailable: count(MechanicalStatus.environmentUnavailable),
      behaviorSpecsRegistered: rows.fold(
        0,
        (sum, r) => sum + r.behavioral.length,
      ),
      behaviorSpecsPassed: rows.fold(
        0,
        (sum, r) => sum + r.behavioral.where((b) => b.passed).length,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'roadmapExecutable': roadmapExecutable,
    'executedWithoutError': executedWithoutError,
    'executionFailed': executionFailed,
    'unclassified': unclassified,
    'deferredFixture': deferredFixture,
    'unsupportedEngine': unsupportedEngine,
    'environmentUnavailable': environmentUnavailable,
    'behaviorSpecsRegistered': behaviorSpecsRegistered,
    'behaviorSpecsPassed': behaviorSpecsPassed,
  };
}

/// The full report for one dialect: every roadmap row for both tracks,
/// plus a computed summary per track.
class DialectReport {
  final String dialect;
  final List<CaseReportRow> queryRows;
  final List<CaseReportRow> schemaRows;

  const DialectReport({
    required this.dialect,
    required this.queryRows,
    required this.schemaRows,
  });

  TrackSummary get querySummary => TrackSummary.from(queryRows);
  TrackSummary get schemaSummary => TrackSummary.from(schemaRows);

  Map<String, dynamic> toJson() => {
    'dialect': dialect,
    'query': {
      'summary': querySummary.toJson(),
      'rows': queryRows.map((r) => r.toJson()).toList(),
    },
    'schema': {
      'summary': schemaSummary.toJson(),
      'rows': schemaRows.map((r) => r.toJson()).toList(),
    },
  };

  String toMarkdown() {
    final buf = StringBuffer();
    buf.writeln('## $dialect');
    buf.writeln();
    _writeTrackMarkdown(buf, 'Query', querySummary);
    _writeTrackMarkdown(buf, 'Schema', schemaSummary);
    return buf.toString();
  }

  void _writeTrackMarkdown(StringBuffer buf, String label, TrackSummary s) {
    buf.writeln('### $label');
    buf.writeln();
    buf.writeln('| Metric | Count |');
    buf.writeln('|---|---|');
    buf.writeln('| Roadmap executable | ${s.roadmapExecutable} |');
    buf.writeln('| **Executed without error** | ${s.executedWithoutError} |');
    buf.writeln('| Execution failed | ${s.executionFailed} |');
    buf.writeln('| Unclassified | ${s.unclassified} |');
    buf.writeln('| Deferred (fixture) | ${s.deferredFixture} |');
    buf.writeln('| Unsupported engine | ${s.unsupportedEngine} |');
    buf.writeln('| Environment unavailable | ${s.environmentUnavailable} |');
    buf.writeln(
      '| **Behaviorally verified** (passed / registered) | '
      '${s.behaviorSpecsPassed} / ${s.behaviorSpecsRegistered} |',
    );
    buf.writeln();
    buf.writeln(
      '"Executed without error" means the database accepted and completed '
      'the built statement under its declared fixture — it does NOT mean '
      'the returned data was verified correct. "Behaviorally verified" '
      'means a test asserted an observable property and passed. Neither '
      'number is "coverage" on its own.',
    );
    buf.writeln();
  }
}

/// The complete report across every dialect run.
class LiveExecutionReport {
  final String generatedAt;
  final String knexVersion;
  final List<DialectReport> dialectReports;

  const LiveExecutionReport({
    required this.generatedAt,
    required this.knexVersion,
    required this.dialectReports,
  });

  Map<String, dynamic> toJson() => {
    'generatedAt': generatedAt,
    'knexVersion': knexVersion,
    'dialects': dialectReports.map((d) => d.toJson()).toList(),
  };

  String toMarkdown() {
    final buf = StringBuffer();
    buf.writeln('# Live-execution report');
    buf.writeln();
    buf.writeln('Generated: $generatedAt · knex.js reference: $knexVersion');
    buf.writeln();
    for (final d in dialectReports) {
      buf.write(d.toMarkdown());
    }
    return buf.toString();
  }

  Future<void> writeTo({required String jsonPath, String? markdownPath}) async {
    final jsonFile = File(jsonPath);
    await jsonFile.parent.create(recursive: true);
    await jsonFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(toJson()),
    );
    if (markdownPath != null) {
      final mdFile = File(markdownPath);
      await mdFile.parent.create(recursive: true);
      await mdFile.writeAsString(toMarkdown());
    }
  }
}
