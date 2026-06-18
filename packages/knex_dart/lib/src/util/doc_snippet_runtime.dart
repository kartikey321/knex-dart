enum DocSnippetTarget { local, playground }

class _SplitSnippet {
  final List<String> imports;
  final List<String> topLevel;
  final List<String> body;
  final bool hasTopLevelMain;

  const _SplitSnippet({
    required this.imports,
    required this.topLevel,
    required this.body,
    required this.hasTopLevelMain,
  });
}

const _playgroundHelperTopLevel =
    "void sql(SqlString s) =>\n"
    "    print(jsonEncode({'sql': s.sql, 'bindings': s.bindings}));\n"
    "\n"
    "void schema(List<Map<String, dynamic>> stmts) {\n"
    "  for (final s in stmts) {\n"
    "    print(jsonEncode({\n"
    "      'sql': s['sql'] as String,\n"
    "      'bindings': (s['bindings'] as List?)?.cast<dynamic>() ?? [],\n"
    "    }));\n"
    "  }\n"
    "}\n";

String buildDocSnippetProgram(
  String code, {
  required DocSnippetTarget target,
  String dialect = 'postgres',
}) {
  final parts = _splitSnippet(code);
  return switch (target) {
    DocSnippetTarget.local => _buildLocalProgram(parts),
    DocSnippetTarget.playground => _buildPlaygroundProgram(parts, dialect),
  };
}

_SplitSnippet _splitSnippet(String code) {
  final codeLines = code.split('\n');
  final imports = <String>[];
  final topLevel = <String>[];
  final body = <String>[];

  var inTopLevelBlock = false;
  var braceDepth = 0;

  for (final line in codeLines) {
    final trimmed = line.trim();

    if (trimmed.startsWith('import ') || trimmed.startsWith('export ')) {
      imports.add(line);
      continue;
    }

    final isTopLevelDecl = RegExp(
      r'^(void |Future|Stream|class |typedef |enum |extension |abstract )',
    ).hasMatch(trimmed);

    if (isTopLevelDecl && !inTopLevelBlock) {
      inTopLevelBlock = true;
      braceDepth = 0;
    }

    if (inTopLevelBlock) {
      topLevel.add(line);
      braceDepth += '{'.allMatches(line).length;
      braceDepth -= '}'.allMatches(line).length;
      if (braceDepth <= 0 && trimmed.endsWith('}')) {
        inTopLevelBlock = false;
      }
    } else {
      body.add(line);
    }
  }

  return _SplitSnippet(
    imports: imports,
    topLevel: topLevel,
    body: body,
    hasTopLevelMain: RegExp(r'\bmain\s*\(').hasMatch(topLevel.join('\n')),
  );
}

String _buildLocalProgram(_SplitSnippet parts) {
  final buf = StringBuffer();
  buf.writeln(
    '// ignore_for_file: unused_local_variable, unused_import, dead_code,',
  );
  buf.writeln(
    '// ignore_for_file: unawaited_futures, avoid_print, unused_element',
  );
  for (final imp in parts.imports) {
    buf.writeln(imp);
  }
  buf.writeln();
  for (final tl in parts.topLevel) {
    buf.writeln(tl);
  }
  if (parts.body.isNotEmpty && !parts.hasTopLevelMain) {
    buf.writeln('Future<void> main() async {');
    for (final b in parts.body) {
      buf.writeln('  $b');
    }
    buf.writeln('}');
  } else if (!parts.hasTopLevelMain) {
    buf.writeln('Future<void> main() async {}');
  }

  return buf.toString();
}

String _buildPlaygroundProgram(_SplitSnippet parts, String dialect) {
  final allImports = <String>{
    "import 'dart:convert';",
    "import 'package:knex_dart/knex_dart.dart';",
    "import 'package:knex_dart_capabilities/knex_dart_capabilities.dart';",
    ...parts.imports,
  };

  final buf = StringBuffer();
  for (final imp in allImports) {
    buf.writeln(imp);
  }
  buf.writeln();
  buf.writeln(_playgroundHelperTopLevel);
  for (final tl in parts.topLevel) {
    buf.writeln(tl);
  }

  if (!parts.hasTopLevelMain) {
    final needsDbPreamble = !(parts.body.join('\n').contains(
          'final db = KnexQuery.forDialect',
        ) ||
        parts.topLevel.join('\n').contains('final db = KnexQuery.forDialect'));
    buf.writeln('void main() {');
    if (needsDbPreamble) {
      buf.writeln(
        '  final db = KnexQuery.forDialect(${_dialectEnum(dialect)});',
      );
      buf.writeln();
    }
    for (final b in parts.body) {
      buf.writeln('  $b');
    }
    buf.writeln('}');
  }

  return buf.toString();
}

String _dialectEnum(String dialect) => switch (dialect) {
  'sqlite' => 'KnexDialect.sqlite',
  'mysql' => 'KnexDialect.mysql',
  _ => 'KnexDialect.postgres',
};
