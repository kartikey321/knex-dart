import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_content/theme.dart';

import 'toc_observer_stub.dart' if (dart.library.html) 'toc_observer_web.dart';

/// Client-side TOC highlighter: marks the current section link as active.
@client
class TocHighlighter extends StatefulComponent {
  const TocHighlighter({super.key});

  @override
  State<TocHighlighter> createState() => _TocHighlighterState();

  @css
  static List<StyleRule> get styles => [
    css('.toc a.toc-active').styles(
      color: ThemeColors.blue.$400,
      fontWeight: FontWeight.w600,
      raw: {'transition': 'color 120ms ease'},
      textDecoration: const TextDecoration(line: TextDecorationLine.none),
    ),
    css('h2[id], h3[id], h4[id]').styles(
      raw: {'scroll-margin-top': '5rem'},
    ),
  ];
}

class _TocHighlighterState extends State<TocHighlighter> {
  @override
  void initState() {
    super.initState();
    setupTocObserver();
  }

  @override
  Component build(BuildContext context) {
    // Render a hidden marker so the client runtime mounts this component.
    return Component.element(
      tag: 'span',
      attributes: {
        'data-toc-highlighter': '',
        'aria-hidden': 'true',
        'style': 'display:none',
      },
    );
  }
}
