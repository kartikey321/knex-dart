
import 'package:jaspr/server.dart';
import 'package:jaspr_content/components/code_block.dart' as content;
import 'package:jaspr_content/jaspr_content.dart';
import 'package:syntax_highlight_lite/syntax_highlight_lite.dart';

/// Defensive code block component:
/// - Highlights only languages we explicitly load grammars for.
/// - Falls back to plain <pre><code> for everything else.
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

      return AsyncBuilder(
        builder: (_) async {
          final highlighter = hasGrammar
              ? Highlighter(
                  language: resolvedLang,
                  theme: _theme ??= await HighlighterTheme.loadDarkTheme(),
                )
              : null;
          return content.CodeBlock.from(source: source, highlighter: highlighter);
        },
      );
    }
    return null;
  }
}

