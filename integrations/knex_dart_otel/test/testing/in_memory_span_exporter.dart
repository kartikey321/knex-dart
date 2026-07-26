/// A minimal in-memory [SpanExporter] for assertions in tests.
///
/// Not a copy-paste of production code: the SDK ships an identical helper
/// under its own `test/testing_utils/`, but that directory isn't part of
/// the published `dartastic_opentelemetry` package, so it isn't importable
/// here. This is the same ~40-line shape, reimplemented against the public
/// `SpanExporter` interface.
library;

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';

class InMemorySpanExporter implements SpanExporter {
  final List<Span> _spans = [];
  bool _isShutdown = false;

  List<Span> get spans => List.unmodifiable(_spans);

  void clear() => _spans.clear();

  @override
  Future<void> export(List<Span> spans) async {
    if (_isShutdown) {
      throw StateError('Exporter is shutdown');
    }
    _spans.addAll(spans);
  }

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {
    _isShutdown = true;
  }
}
