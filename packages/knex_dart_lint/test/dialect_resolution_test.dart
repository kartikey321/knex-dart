import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:knex_dart_capabilities/knex_dart_capabilities.dart';
import 'package:knex_dart_lint/src/dialect_resolution.dart';
import 'package:test/test.dart';

void main() {
  test('a field whose name matches a dialect is not mistaken for one', () {
    // Only the trailing identifier used to be read, so any expression ending
    // in a dialect name was taken for that dialect. A field called `mssql`
    // holding a Postgres value resolved to MSSQL, and the dialect-aware rules
    // then reported Postgres code against SQL Server.
    final unit = _parse(r'''
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

  test('a prefixed import of KnexDialect still resolves', () {
    // `knex.KnexDialect.mssql` is a PropertyAccess rather than a
    // PrefixedIdentifier, so the qualifier check has to look through the
    // target instead of rejecting it.
    final unit = _parse(r'''
import 'package:knex_dart/knex_dart.dart' as knex;
void f() {
  final db = knex.KnexQuery.forDialect(knex.KnexDialect.mssql);
  db.queryBuilder().from('t').select(['*']);
}
''');

    final info = resolveDialectForInvocation(_findInvocation(unit, 'select'));
    expect(info.dialect, KnexDialect.mssql);
  });

  test('every KnexDialect resolves from KnexQuery.forDialect', () {
    // Guards against the drift that let `mssql` go unresolved: the resolver
    // was a hand-written switch listing ten of the eleven dialects, so
    // `forDialect(KnexDialect.mssql)` returned null and every dialect-aware
    // rule skipped that code silently. Iterating the enum here means adding a
    // dialect without teaching the resolver fails this test rather than
    // quietly disabling the lints for it.
    for (final dialect in KnexDialect.values) {
      // The resolver tracks the dialect through the variable a builder came
      // from, so the query has to be rooted in one.
      final unit = _parse('''
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

  test('infers postgres from KnexPostgres.connect', () {
    final unit = _parse(r'''
import 'package:knex_dart_postgres/knex_dart_postgres.dart';
Future<void> f() async {
  final db = await KnexPostgres.connect(host: 'localhost', database: 'x', user: 'u', password: 'p');
  db('users').insert({'name': 'A'}).returning(['id']);
}
''');

    final node = _findInvocation(unit, 'returning');
    final info = resolveDialectForInvocation(node);

    expect(info.isHighConfidence, isTrue);
    expect(info.dialect, KnexDialect.postgres);
  });

  test('infers mysql from KnexMySQL.connect', () {
    final unit = _parse(r'''
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

  test('returns unknown when dialect cannot be inferred', () {
    final unit = _parse(r'''
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

  test('detects onConflict in merge chain', () {
    final unit = _parse(r'''
Future<void> f() async {
  final db = await KnexSQLite.connect(filename: ':memory:');
  db('users').insert({'email': 'a@b.c'}).onConflict('email').merge({'name': 'x'});
}
''');

    final node = _findInvocation(unit, 'merge');
    expect(hasOnConflictInChain(node), isTrue);
  });

  test('uses nearest function scope when db variable names repeat', () {
    final unit = _parse(r'''
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

CompilationUnit _parse(String content) => parseString(content: content).unit;

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
