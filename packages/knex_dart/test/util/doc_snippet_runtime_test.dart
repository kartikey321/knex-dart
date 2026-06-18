import 'package:knex_dart/src/util/doc_snippet_runtime.dart';
import 'package:test/test.dart';

void main() {
  group('buildDocSnippetProgram', () {
    test('local wraps snippet body in async main', () {
      final code = '''
import 'package:knex_dart/knex_dart.dart';

final q = KnexQuery.forClient('mysql2');
print(q.from('users').toSQL().sql);
''';

      final program = buildDocSnippetProgram(
        code,
        target: DocSnippetTarget.local,
      );

      expect(program, contains("Future<void> main() async {"));
      expect(program, contains("final q = KnexQuery.forClient('mysql2');"));
    });

    test('local does not double-wrap explicit main', () {
      final code = '''
void main() {
  print('ok');
}
''';

      final program = buildDocSnippetProgram(
        code,
        target: DocSnippetTarget.local,
      );

      expect(
        RegExp(r'Future<void> main\(\) async \{').allMatches(program),
        isEmpty,
      );
      expect(RegExp(r'void main\(\)').allMatches(program).length, 1);
    });

    test('playground injects helpers and db preamble', () {
      final code = '''
sql(db.from('users').toSQL());
''';

      final program = buildDocSnippetProgram(
        code,
        target: DocSnippetTarget.playground,
        dialect: 'postgres',
      );

      expect(program, contains("import 'dart:convert';"));
      expect(program, contains('void sql(SqlString s) =>'));
      expect(
        program,
        contains('final db = KnexQuery.forDialect(KnexDialect.postgres);'),
      );
    });

    test('playground preserves explicit main without adding another', () {
      final code = '''
void main() {
  print('hello');
}
''';

      final program = buildDocSnippetProgram(
        code,
        target: DocSnippetTarget.playground,
      );

      expect(RegExp(r'void main\(\)').allMatches(program).length, 1);
    });
  });
}
