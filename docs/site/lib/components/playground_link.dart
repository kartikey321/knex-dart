import 'dart:convert';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:knex_dart/src/util/doc_snippet_runtime.dart';

// URL of the deployed playground. Override via PLAYGROUND_URL env var at build time.
const _playgroundUrl = String.fromEnvironment(
  'PLAYGROUND_URL',
  defaultValue: 'https://playground.knex.mahawarkartikey.in',
);

String _playgroundDialect(String dialect) => switch (dialect) {
  'sqlite' => 'sqlite',
  'mysql' => 'mysql',
  _ => 'postgres',
};

/// Encodes [code] as URL-safe base64 (no padding) for the playground hash.
String _encode(String code) {
  final bytes = utf8.encode(code);
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// Builds the full playground URL for a snippet, including the active dialect.
String playgroundUrl(String snippet, {String dialect = 'postgres'}) {
  final playgroundDialect = _playgroundDialect(dialect);
  final code = buildDocSnippetProgram(
    snippet,
    target: DocSnippetTarget.playground,
    dialect: playgroundDialect,
  );
  final encodedDialect = Uri.encodeComponent(playgroundDialect);
  return '$_playgroundUrl#code=${_encode(code)}&dialect=$encodedDialect';
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
