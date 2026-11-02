import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:knex_dart_capabilities/knex_dart_capabilities.dart';
import 'package:knex_dart_lint/src/dialect_resolution.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('a field whose name matches a dialect is not mistaken for one', () async {
    // Only the trailing identifier used to be read, so any expression ending
    // in a dialect name was taken for that dialect. A field called `mssql`
    // holding a Postgres value resolved to MSSQL, and the dialect-aware rules
    // then reported Postgres code against SQL Server.
    final unit = await _parse(r'''
import 'package:knex_dart/knex_dart.dart';
class Config { final mssql = KnexDialect.postgres; }
void f(Config config) {
  final db = KnexQuery.forDialect(config.mssql);
  db.queryBuilder().from('t').select(['*']);
}
''');

    final info = resolveDialectForInvocation(_findInvocation(unit, 'select'));

    expect(
      info.dialect,
      isNot(KnexDialect.mssql),
      reason: 'the qualifier is `config`, not `KnexDialect`, so the name must '
          'not be trusted — reporting MSSQL here would flag valid Postgres '
          'code against the wrong dialect',
    );
  });

  test('a prefixed import of KnexDialect still resolves', () async {
    // `knex.KnexDialect.mssql` is a PropertyAccess rather than a
    // PrefixedIdentifier, so the qualifier check has to look through the
    // target instead of rejecting it.
    final unit = await _parse(r'''
import 'package:knex_dart/knex_dart.dart' as knex;
void f() {
  final db = knex.KnexQuery.forDialect(knex.KnexDialect.mssql);
  db.queryBuilder().from('t').select(['*']);
}
''');

    final info = resolveDialectForInvocation(_findInvocation(unit, 'select'));
    expect(info.dialect, KnexDialect.mssql);
  });

  test('every KnexDialect resolves from KnexQuery.forDialect', () async {
    // Guards against the drift that let `mssql` go unresolved: the resolver
    // was a hand-written switch listing ten of the eleven dialects, so
    // `forDialect(KnexDialect.mssql)` returned null and every dialect-aware
    // rule skipped that code silently. Iterating the enum here means adding a
    // dialect without teaching the resolver fails this test rather than
    // quietly disabling the lints for it.
    for (final dialect in KnexDialect.values) {
      // The resolver tracks the dialect through the variable a builder came
      // from, so the query has to be rooted in one.
      final unit = await _parse('''
import 'package:knex_dart/knex_dart.dart';
void f() {
  final db = KnexQuery.forDialect(KnexDialect.${dialect.name});
  db.queryBuilder().from('t').select(['*']);
}
''');
      final node = _findInvocation(unit, 'select');
      final info = resolveDialectForInvocation(node);

      expect(
        info.dialect,
        dialect,
        reason: 'forDialect(KnexDialect.${dialect.name}) must resolve to it; '
            'null means the dialect-aware rules silently skip this code',
      );
      expect(info.isHighConfidence, isTrue, reason: dialect.name);
    }
  });

  test('infers postgres from KnexPostgres.connect', () async {
    final unit = await _parse(r'''
import 'package:knex_dart_postgres/knex_dart_postgres.dart';
Future<void> f() async {
  final db = await KnexPostgres.connect(host: 'localhost', database: 'x', username: 'u', password: 'p');
  db('users').insert({'name': 'A'}).returning(['id']);
}
''');

    final node = _findInvocation(unit, 'returning');
    final info = resolveDialectForInvocation(node);

    expect(info.isHighConfidence, isTrue);
    expect(info.dialect, KnexDialect.postgres);
  });

  test('infers mysql from KnexMySQL.connect', () async {
    final unit = await _parse(r'''
import 'package:knex_dart_mysql/knex_dart_mysql.dart';
Future<void> f() async {
  final db = await KnexMySQL.connect(host: 'localhost', database: 'x', user: 'u', password: 'p');
  db('users').fullOuterJoin('orders', 'users.id', 'orders.user_id');
}
''');

    final node = _findInvocation(unit, 'fullOuterJoin');
    final info = resolveDialectForInvocation(node);

    expect(info.isHighConfidence, isTrue);
    expect(info.dialect, KnexDialect.mysql);
  });

  test('returns unknown when dialect cannot be inferred', () async {
    final unit = await _parse(r'''
Future<void> f(dynamic factory) async {
  final db = await factory();
  db('users').returning(['id']);
}
''');

    final node = _findInvocation(unit, 'returning');
    final info = resolveDialectForInvocation(node);

    expect(info.confidence, DialectConfidence.unknown);
    expect(info.dialect, isNull);
  });

  test('detects onConflict in merge chain', () async {
    final unit = await _parse(r'''
import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';
Future<void> f() async {
  final db = await KnexSQLite.connect(filename: ':memory:');
  db('users').insert({'email': 'a@b.c'}).onConflict('email').merge({'name': 'x'});
}
''');

    final node = _findInvocation(unit, 'merge');
    expect(hasOnConflictInChain(node), isTrue);
  });

  test('uses nearest function scope when db variable names repeat', () async {
    final unit = await _parse(r'''
import 'package:knex_dart_mysql/knex_dart_mysql.dart';
import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';
Future<void> mysqlCase() async {
  final db = await KnexMySQL.connect(host: 'localhost', database: 'x', user: 'u', password: 'p');
  db.queryBuilder().table('users').returning(['id']);
}

Future<void> sqliteCase() async {
  final db = await KnexSQLite.connect(filename: ':memory:');
  db.queryBuilder().table('users').joinLateral('latest', (sub) {
    sub.table('orders').limit(1);
  });
}
''');

    final returningNode = _findInvocation(unit, 'returning');
    final lateralNode = _findInvocation(unit, 'joinLateral');

    final returningInfo = resolveDialectForInvocation(returningNode);
    final lateralInfo = resolveDialectForInvocation(lateralNode);

    expect(returningInfo.dialect, KnexDialect.mysql);
    expect(lateralInfo.dialect, KnexDialect.sqlite);
  });
}

/// Parses AND resolves [content], unlike `parseString`.
///
/// The resolver's qualifier check distinguishes the real `KnexDialect` enum
/// from an unrelated member sharing its name by resolving the qualifier to an
/// [Element] — see the comment in `_resolveFromForDialectArg`. `parseString`
/// never resolves anything, so every such [Element] came back `null` and the
/// check would have silently passed on every input, real or spoofed, making
/// these tests unable to tell a working check from a deleted one.
///
/// Written to a scratch file *inside* this package so `resolveFile` finds this
/// package's own `package_config.json` and resolves `package:knex_dart/...`
/// imports against the real `knex_dart_capabilities` already in the workspace.
Future<CompilationUnit> _parse(String content) async {
  final dir = Directory(p.join(Directory.current.path, '.dart_tool', 'dialect_resolution_test_scratch'));
  dir.createSync(recursive: true);
  final file = File(p.join(dir.path, 'case_${_scratchCounter++}.dart'));
  file.writeAsStringSync(content);
  addTearDown(() {
    if (file.existsSync()) file.deleteSync();
  });

  final result = await resolveFile(path: file.absolute.path);
  if (result is! ResolvedUnitResult) {
    throw StateError('Failed to resolve test source: $result');
  }
  if (result.diagnostics.isNotEmpty) {
    throw StateError(
      'Test source has analysis errors: ${result.diagnostics.join('\n')}',
    );
  }
  return result.unit;
}

int _scratchCounter = 0;

MethodInvocation _findInvocation(CompilationUnit unit, String methodName) {
  MethodInvocation? found;

  unit.visitChildren(
    _Visitor((node) {
      if (node.methodName.name == methodName) {
        found ??= node;
      }
    }),
  );

  if (found == null) {
    throw StateError('Method invocation "$methodName" not found');
  }

  return found!;
}

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this.onMethod);

  final void Function(MethodInvocation node) onMethod;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    onMethod(node);
    super.visitMethodInvocation(node);
  }
}
