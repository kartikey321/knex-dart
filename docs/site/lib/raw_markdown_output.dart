import 'package:jaspr/server.dart';
import 'package:jaspr_content/jaspr_content.dart';

/// Exposes each docs page as raw markdown under `/raw/...`.
class RawMarkdownOutput extends SecondaryOutput {
  RawMarkdownOutput({this.createHeader});

  final String Function(Page page)? createHeader;

  @override
  Pattern get pattern => RegExp(r'.*\.mdx?$');

  @override
  String createRoute(String route) {
    if (route == '/') {
      return '/raw/index.md';
    }

    final normalized = route.endsWith('/')
        ? route.substring(0, route.length - 1)
        : route;
    return '/raw$normalized.md';
  }

  @override
  Component build(Page page) {
    return Builder(
      builder: (context) {
        final pageContent = StringBuffer();
        if (createHeader case final createHeader?) {
          pageContent.writeln(createHeader(page));
        }
        pageContent.writeln(page.content);

        context.setHeader('Content-Type', 'text/markdown');
        context.setStatusCode(200, responseBody: pageContent.toString());
        return const Component.text('');
      },
    );
  }
}
