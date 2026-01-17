import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart'; // Added dom import for link() builder
import 'package:jaspr_content/jaspr_content.dart';

import '../components/toc_highlighter.dart';

/// Docs layout wrapper that injects the TOC highlighter client component so
/// the scrolling logic always mounts.
class DocsLayoutWithTocHighlighter extends DocsLayout {
  const DocsLayoutWithTocHighlighter({super.sidebar, super.header, super.footer});

  @override
  Component buildBody(Page page, Component child) {
    final body = super.buildBody(page, child);

    // Dynamic canonical URL based on current page path.
    // Falls back to root if path is not available or empty.
    var path = page.path;
    if (path.startsWith('/')) {
      path = path.substring(1);
    }
    final canonicalUrl = 'https://docs.fletch.mahawarkartikey.in/$path';

    return Component.fragment([
      Document.head(
        meta: {
          'description':
              'A lightweight, Express-inspired HTTP framework for Dart with routing, middleware, and support for isolated modules.',
          'keywords': 'dart, express, framework, http, routing, middleware, backend, api, server, fletch',
          // Using title directly if available on Page would be ideal, but falling back to defaults for safety
          'og:title': 'Fletch',
          'og:description': 'A lightweight, Express-inspired HTTP framework for Dart.',
          'og:url': canonicalUrl,
        },
        // Document.head doesn't seem to support children for link tags in older versions,
        // using adjacent link() component instead.
      ),
      // Inject canonical link
      link(rel: 'canonical', href: canonicalUrl),
      body,
      const TocHighlighter(),
    ]);
  }
}
