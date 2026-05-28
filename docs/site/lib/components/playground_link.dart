import 'dart:convert';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

// URL of the deployed playground. Override via PLAYGROUND_URL env var at build time.
const _playgroundUrl = String.fromEnvironment(
  'PLAYGROUND_URL',
  defaultValue: 'https://playground.knex.mahawarkartikey.in',
);

const _boilerplate = "import 'dart:convert';\n"
    "import 'package:knex_dart/knex_dart.dart';\n"
    "import 'package:knex_dart_capabilities/knex_dart_capabilities.dart';\n"
    "\n"
    "void sql(SqlString s) =>\n"
    "    print(jsonEncode({'sql': s.sql, 'bindings': s.bindings}));\n"
    "\n"
    "void schema(List<Map<String, dynamic>> stmts) {\n"
    "  for (final s in stmts) {\n"
    "    print(jsonEncode({'sql': s['sql'] as String, 'bindings': []}));\n"
    "  }\n"
    "}\n"
    "\n";

/// Maps a dialect string to its KnexDialect enum literal for the boilerplate.
String _dialectEnum(String dialect) => switch (dialect) {
      'sqlite'  => 'KnexDialect.sqlite',
      'mysql'   => 'KnexDialect.mysql',
      'mssql'   => 'KnexDialect.mssql',
      _         => 'KnexDialect.postgres',
    };

/// Preamble injected at the top of main() — sets up `db`.
String _mainPreamble(String dialect) =>
    "  final db = KnexQuery.forDialect(${_dialectEnum(dialect)});\n";

/// Encodes [code] as URL-safe base64 (no padding) for the playground hash.
String _encode(String code) {
  final bytes = utf8.encode(code);
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// Builds the full playground URL for a snippet, including the active dialect.
/// Wraps the snippet in boilerplate if it isn't already a complete program.
String playgroundUrl(String snippet, {String dialect = 'postgres'}) {
  String code;
  if (snippet.contains('void main(')) {
    code = snippet;
  } else {
    // Only inject `final db = ...` if the snippet doesn't already declare it.
    final preamble = snippet.contains('final db = KnexQuery.forDialect')
        ? ''
        : '${_mainPreamble(dialect)}\n';
    code = '${_boilerplate}void main() {\n$preamble$snippet\n}';
  }
  return '$_playgroundUrl#code=${_encode(code)}&dialect=$dialect';
}

/// Inline "Try in Playground ↗" link — drop next to any code block.
class PlaygroundLink extends StatelessComponent {
  const PlaygroundLink({required this.code, this.dialect = 'postgres', super.key});

  final String code;
  final String dialect;

  @override
  Component build(BuildContext context) {
    return a(
      href: playgroundUrl(code, dialect: dialect),
      target: Target.blank,
      attributes: {'rel': 'noopener noreferrer'},
      classes: 'playground-link',
      [text('Try in Playground ↗')],
    );
  }

  @css
  static List<StyleRule> get styles => [
    css('.playground-link').styles(
      display: Display.inlineBlock,
      fontSize: .75.rem,
      padding: Padding.symmetric(horizontal: .6.rem, vertical: .25.rem),
      raw: {
        'color': '#22c55e',
        'border': '1px solid #22c55e44',
        'border-radius': '4px',
        'text-decoration': 'none',
        'font-weight': '500',
        'margin-top': '4px',
      },
    ),
    css('.playground-link:hover').styles(
      raw: {'background': '#22c55e18'},
    ),
  ];
}
