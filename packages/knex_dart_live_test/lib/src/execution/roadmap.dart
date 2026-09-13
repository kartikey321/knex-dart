/// Loads `tool/parity/EXECUTABLE_CASES.json` — the per-dialect roadmap of
/// which corpus case ids compile to real SQL (and are therefore in scope
/// for live execution) versus which ones knex.js itself refuses outright
/// (nothing to execute for those; out of scope by construction, not
/// "not yet classified").
///
/// This is the ground-truth denominator the live-execution report is built
/// against: every id the mechanical runner iterates comes from here, never
/// from a hand-picked subset.
library;

import 'dart:convert';
import 'dart:io';

/// One dialect's slice of the roadmap: which query/schema case ids are
/// executable, and which are refused (with the reason knex.js gave).
class DialectRoadmap {
  final String dialect;
  final List<String> executableQueryIds;
  final Map<String, String> refusedQueryIds;
  final List<String> executableSchemaIds;
  final Map<String, String> refusedSchemaIds;

  const DialectRoadmap({
    required this.dialect,
    required this.executableQueryIds,
    required this.refusedQueryIds,
    required this.executableSchemaIds,
    required this.refusedSchemaIds,
  });

  factory DialectRoadmap.fromJson(String dialect, Map<String, dynamic> json) {
    Map<String, String> refusedOf(String track) {
      final refused = (json[track] as Map<String, dynamic>?)?['refused'];
      if (refused == null) return const {};
      return {
        for (final entry in (refused as List).cast<Map<String, dynamic>>())
          entry['id'] as String: entry['error'] as String,
      };
    }

    List<String> executableOf(String track) {
      final executable = (json[track] as Map<String, dynamic>?)?['executable'];
      if (executable == null) return const [];
      return (executable as List).cast<String>();
    }

    return DialectRoadmap(
      dialect: dialect,
      executableQueryIds: executableOf('query'),
      refusedQueryIds: refusedOf('query'),
      executableSchemaIds: executableOf('schema'),
      refusedSchemaIds: refusedOf('schema'),
    );
  }
}

/// The full roadmap: every dialect's [DialectRoadmap], plus the knex.js
/// version it was generated against.
class ExecutableCasesRoadmap {
  final String knexVersion;
  final String generatedAt;
  final Map<String, DialectRoadmap> dialects;

  const ExecutableCasesRoadmap({
    required this.knexVersion,
    required this.generatedAt,
    required this.dialects,
  });

  /// The roadmap for [dialect], or throws if the roadmap has never heard of
  /// it — a typo'd dialect name should fail loudly, not silently report an
  /// empty roadmap.
  DialectRoadmap forDialect(String dialect) {
    final roadmap = dialects[dialect];
    if (roadmap == null) {
      throw ArgumentError(
        'No roadmap entry for dialect "$dialect" — known dialects: '
        '${dialects.keys.join(", ")}',
      );
    }
    return roadmap;
  }

  static ExecutableCasesRoadmap load([String? explicitPath]) {
    final candidates = explicitPath != null
        ? [explicitPath]
        : [
            'tool/parity/EXECUTABLE_CASES.json',
            '../../tool/parity/EXECUTABLE_CASES.json',
            '../../../tool/parity/EXECUTABLE_CASES.json',
            '${Directory.current.path}/tool/parity/EXECUTABLE_CASES.json',
          ];
    for (final path in candidates) {
      final file = File(path);
      if (file.existsSync()) {
        return _parse(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
      }
    }
    throw StateError(
      'EXECUTABLE_CASES.json not found (looked in: ${candidates.join(", ")}). '
      'Generate it with: node tool/parity/tag_executable_cases.mjs',
    );
  }

  static ExecutableCasesRoadmap _parse(Map<String, dynamic> json) {
    final dialectsJson = json['dialects'] as Map<String, dynamic>;
    return ExecutableCasesRoadmap(
      knexVersion: json['knexVersion'] as String,
      generatedAt: json['generatedAt'] as String,
      dialects: {
        for (final entry in dialectsJson.entries)
          entry.key: DialectRoadmap.fromJson(
            entry.key,
            entry.value as Map<String, dynamic>,
          ),
      },
    );
  }
}
