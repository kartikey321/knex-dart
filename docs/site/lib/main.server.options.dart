// dart format off
// ignore_for_file: type=lint

// GENERATED FILE, DO NOT MODIFY
// Generated with jaspr_builder

import 'package:jaspr/server.dart';
import 'package:jaspr_content/components/_internal/code_block_copy_button.dart'
    as _code_block_copy_button;
import 'package:jaspr_content/components/_internal/zoomable_image.dart'
    as _zoomable_image;
import 'package:jaspr_content/components/callout.dart' as _callout;
import 'package:jaspr_content/components/code_block.dart' as _code_block;
import 'package:jaspr_content/components/image.dart' as _image;
import 'package:jaspr_content/components/sidebar_toggle_button.dart'
    as _sidebar_toggle_button;
import 'package:jaspr_content/components/theme_toggle.dart' as _theme_toggle;
import 'package:site/components/github_button.dart' as _github_button;
import 'package:site/components/toc_highlighter.dart' as _toc_highlighter;

/// Default [ServerOptions] for use with your Jaspr project.
///
/// Use this to initialize Jaspr **before** calling [runApp].
///
/// Example:
/// ```dart
/// import 'main.server.options.dart';
///
/// void main() {
///   Jaspr.initializeApp(
///     options: defaultServerOptions,
///   );
///
///   runApp(...);
/// }
/// ```
ServerOptions get defaultServerOptions => ServerOptions(
  clientId: 'main.client.dart.js',
  clients: {
    _code_block_copy_button.CodeBlockCopyButton:
        ClientTarget<_code_block_copy_button.CodeBlockCopyButton>(
          'jaspr_content:code_block_copy_button',
        ),
    _zoomable_image.ZoomableImage: ClientTarget<_zoomable_image.ZoomableImage>(
      'jaspr_content:zoomable_image',
      params: __zoomable_imageZoomableImage,
    ),
    _sidebar_toggle_button.SidebarToggleButton:
        ClientTarget<_sidebar_toggle_button.SidebarToggleButton>(
          'jaspr_content:sidebar_toggle_button',
        ),
    _theme_toggle.ThemeToggle: ClientTarget<_theme_toggle.ThemeToggle>(
      'jaspr_content:theme_toggle',
    ),
    _github_button.MyGitHubButton: ClientTarget<_github_button.MyGitHubButton>(
      'github_button',
      params: __github_buttonMyGitHubButton,
    ),
    _toc_highlighter.TocHighlighter:
        ClientTarget<_toc_highlighter.TocHighlighter>('toc_highlighter'),
  },
  styles: () => [
    ..._zoomable_image.ZoomableImage.styles,
    ..._callout.Callout.styles,
    ..._code_block.CodeBlock.styles,
    ..._image.Image.styles,
    ..._theme_toggle.ThemeToggleState.styles,
    ..._github_button.MyGitHubButton.styles,
    ..._toc_highlighter.TocHighlighter.styles,
  ],
);

Map<String, Object?> __zoomable_imageZoomableImage(
  _zoomable_image.ZoomableImage c,
) => {'src': c.src, 'alt': c.alt, 'caption': c.caption};
Map<String, Object?> __github_buttonMyGitHubButton(
  _github_button.MyGitHubButton c,
) => {'repo': c.repo};
