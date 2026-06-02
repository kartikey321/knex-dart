import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:test/test.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

CompilationUnit _parse(String src) =>
    parseString(content: src, throwIfDiagnostics: false).unit;

/// Returns all MapLiteralEntry nodes inside a named [method] call whose
/// key is a string ending with ':' and whose value is a NullLiteral.
List<MapLiteralEntry> _nullIdentifierEntries(
  CompilationUnit unit,
  String method,
) {
  final results = <MapLiteralEntry>[];
  unit.visitChildren(
    _Visitor((node) {
      if (node is MethodInvocation && node.methodName.name == method) {
        final args = node.argumentList.arguments;
        if (args.length < 2) return;
        final map = args[1];
        if (map is! SetOrMapLiteral) return;
        for (final el in map.elements) {
          if (el is! MapLiteralEntry) continue;
          final key = el.key;
          final val = el.value;
          if (key is SimpleStringLiteral &&
              key.value.trim().endsWith(':') &&
              val is NullLiteral) {
            results.add(el);
          }
        }
      }
    }),
  );
  return results;
}

class _Visitor extends GeneralizingAstVisitor<void> {
  final void Function(AstNode) _visit;
  _Visitor(this._visit);

  @override
  void visitNode(AstNode node) {
    _visit(node);
    super.visitNode(node);
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('RawNullIdentifierBindingRule detection', () {
    test('flags null value for :table: identifier binding in raw()', () {
      final unit = _parse(r'''
void f(dynamic db) {
  db.raw('SELECT * FROM :table:', {'table:': null});
}
''');
      final entries = _nullIdentifierEntries(unit, 'raw');
      expect(entries, hasLength(1));
      final key = (entries.first.key as SimpleStringLiteral).value;
      expect(key, endsWith(':'));
    });

    test('flags null value for :col: identifier binding in rawSql()', () {
      final unit = _parse(r'''
void f(dynamic db) {
  db.rawSql('ORDER BY :col: ASC', {'col:': null});
}
''');
      final entries = _nullIdentifierEntries(unit, 'rawSql');
      expect(entries, hasLength(1));
    });

    test('does NOT flag null value for :key value binding (no trailing colon)', () {
      final unit = _parse(r'''
void f(dynamic db) {
  db.raw('WHERE id = :id', {'id': null});
}
''');
      // :id is a value binding — null is valid and emits a placeholder.
      final entries = _nullIdentifierEntries(unit, 'raw');
      expect(entries, isEmpty);
    });

    test('does NOT flag non-null identifier bindings', () {
      final unit = _parse(r'''
void f(dynamic db) {
  db.raw('SELECT * FROM :table:', {'table:': 'users'});
}
''');
      final entries = _nullIdentifierEntries(unit, 'raw');
      expect(entries, isEmpty);
    });

    test('flags only the null entry when map has mixed null/non-null', () {
      final unit = _parse(r'''
void f(dynamic db) {
  db.raw('SELECT :col: FROM :table:', {'col:': 'id', 'table:': null});
}
''');
      final entries = _nullIdentifierEntries(unit, 'raw');
      expect(entries, hasLength(1));
      final key = (entries.first.key as SimpleStringLiteral).value;
      expect(key, 'table:');
    });
  });
}
