import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:jaspr_content/components/code_block.dart' as content;
import 'package:jaspr_content/jaspr_content.dart';
import 'package:syntax_highlight_lite/syntax_highlight_lite.dart';

import 'playground_link.dart';

/// Defensive code block component:
/// - Highlights only languages we explicitly load grammars for.
/// - Falls back to plain <pre><code> for everything else.
/// - Adds a "Try in Playground" button for dart blocks that are complete programs
///   OR have the `playground` attribute set.
class SafeCodeBlock extends CustomComponent {
  SafeCodeBlock({required this.grammars, this.defaultLanguage = 'dart'}) : super.base();

  final Map<String, String> grammars;
  final String defaultLanguage;

  bool _initialized = false;
  HighlighterTheme? _theme;

  @override
  Component? create(Node node, NodesBuilder builder) {
    if (node
        case ElementNode(tag: 'Code' || 'CodeBlock', :final children, :final attributes) ||
            ElementNode(tag: 'pre', children: [ElementNode(tag: 'code', :final children, :final attributes)])) {
      var language = attributes['language'];
      if (language == null && (attributes['class']?.startsWith('language-') ?? false)) {
        language = attributes['class']!.substring('language-'.length);
      }
      final resolvedLang = language ?? defaultLanguage;
      final hasGrammar = resolvedLang == 'dart' || grammars.containsKey(resolvedLang);

      if (!_initialized) {
        Highlighter.initialize(['dart']);
        grammars.forEach(Highlighter.addLanguage);
        _initialized = true;
      }

      final source = children?.map((c) => c.innerText).join(' ') ?? '';

      // Show "Try in Playground" for all dart blocks unless opted out with playground="false"
      final isDart = resolvedLang == 'dart';
      final showPlayground = isDart && attributes['playground'] != 'false';
      final dialect = attributes['dialect'] ?? 'postgres';

      return AsyncBuilder(
        builder: (_) async {
          final highlighter = hasGrammar
              ? Highlighter(
                  language: resolvedLang,
                  theme: _theme ??= await HighlighterTheme.loadDarkTheme(),
                )
              : null;
          final block = content.CodeBlock.from(source: source, highlighter: highlighter);

          if (!showPlayground) return block;

          return div(classes: 'code-with-playground', [
            block,
            div(classes: 'playground-link-row', [
              PlaygroundLink(code: source, dialect: dialect),
            ]),
          ]);
        },
      );
    }
    return null;
  }
}
