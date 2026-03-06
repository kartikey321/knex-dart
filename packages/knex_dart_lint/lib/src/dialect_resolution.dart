import 'package:analyzer/dart/ast/ast.dart';
import 'package:knex_dart_capabilities/knex_dart_capabilities.dart';

enum DialectConfidence { high, unknown }

class DialectInfo {
  const DialectInfo(this.dialect, this.confidence);

  final KnexDialect? dialect;
  final DialectConfidence confidence;

  bool get isHighConfidence => confidence == DialectConfidence.high;
}

DialectInfo resolveDialectForInvocation(MethodInvocation node) {
  final rootName = _extractRootIdentifier(node);
  if (rootName == null) {
    return const DialectInfo(null, DialectConfidence.unknown);
  }

  final scopedDialect = _resolveFromEnclosingFunctionBody(node, rootName);
  if (scopedDialect != null) {
    return DialectInfo(scopedDialect, DialectConfidence.high);
  }

  final unit = node.thisOrAncestorOfType<CompilationUnit>();
  if (unit == null) {
    return const DialectInfo(null, DialectConfidence.unknown);
  }

  final dialect = _resolveFromVariableDeclarations(unit, rootName);
  if (dialect == null) {
    return const DialectInfo(null, DialectConfidence.unknown);
  }

  return DialectInfo(dialect, DialectConfidence.high);
}

KnexDialect? _resolveFromEnclosingFunctionBody(AstNode node, String rootName) {
  final body = node.thisOrAncestorOfType<FunctionBody>();
  if (body == null) return null;
  return _resolveFromFunctionBody(body, rootName);
}

bool hasOnConflictInChain(MethodInvocation node) {
  Expression? current = node.target;
  while (current != null) {
    if (current is MethodInvocation) {
      if (current.methodName.name == 'onConflict') {
        return true;
      }
      current = current.target;
      continue;
    }

    if (current is FunctionExpressionInvocation) {
      final fn = current.function;
      if (fn is Identifier) return false;
      if (fn is PropertyAccess) {
        current = fn.target;
        continue;
      }
      return false;
    }

    if (current is PropertyAccess) {
      current = current.target;
      continue;
    }

    if (current is ParenthesizedExpression) {
      current = current.expression;
      continue;
    }

    return false;
  }

  return false;
}

String? _extractRootIdentifier(MethodInvocation node) {
  Expression? current = node;

  while (current != null) {
    if (current is MethodInvocation) {
      if (current.target == null) {
        // `db('users')` parses as MethodInvocation with no target where
        // methodName is the callable variable identifier.
        return current.methodName.name;
      }
      current = current.target;
      continue;
    }

    if (current is FunctionExpressionInvocation) {
      final fn = current.function;
      if (fn is SimpleIdentifier) return fn.name;
      if (fn is PrefixedIdentifier) return fn.identifier.name;
      if (fn is PropertyAccess && fn.propertyName.name == 'call') {
        final target = fn.target;
        if (target is SimpleIdentifier) return target.name;
        if (target is PrefixedIdentifier) return target.identifier.name;
      }
      return null;
    }

    if (current is PrefixedIdentifier) {
      return current.identifier.name;
    }

    if (current is PropertyAccess) {
      if (current.propertyName.name == 'call') {
        final target = current.target;
        if (target is SimpleIdentifier) return target.name;
        if (target is PrefixedIdentifier) return target.identifier.name;
      }
      current = current.target;
      continue;
    }

    if (current is ParenthesizedExpression) {
      current = current.expression;
      continue;
    }

    if (current is SimpleIdentifier) {
      return current.name;
    }

    return null;
  }

  return null;
}

KnexDialect? _resolveFromVariableDeclarations(
  CompilationUnit unit,
  String name,
) {
  // Only scan top-level variable declarations. Function-local variables are
  // already handled by _resolveFromEnclosingFunctionBody; scanning other
  // function bodies would produce false positives when multiple functions use
  // the same variable name (e.g. `db`) with different dialects.
  for (final declaration in unit.declarations) {
    if (declaration is TopLevelVariableDeclaration) {
      final dialect = _resolveFromVariableList(declaration.variables, name);
      if (dialect != null) return dialect;
    }
  }

  return null;
}

KnexDialect? _resolveFromFunctionBody(FunctionBody body, String name) {
  if (body is! BlockFunctionBody) return null;

  for (final statement in body.block.statements) {
    if (statement is VariableDeclarationStatement) {
      final dialect = _resolveFromVariableList(statement.variables, name);
      if (dialect != null) return dialect;
    }
  }

  return null;
}

KnexDialect? _resolveFromVariableList(
  VariableDeclarationList list,
  String name,
) {
  for (final variable in list.variables) {
    if (variable.name.lexeme != name) continue;
    final initializer = variable.initializer;
    if (initializer == null) return null;
    return _resolveDialectFromExpression(initializer);
  }

  return null;
}

KnexDialect? _resolveDialectFromExpression(Expression expression) {
  Expression value = expression;

  while (value is ParenthesizedExpression) {
    value = value.expression;
  }

  if (value is AwaitExpression) {
    return _resolveDialectFromExpression(value.expression);
  }

  if (value is MethodInvocation && value.methodName.name == 'connect') {
    final target = value.target;
    return _dialectFromConnectTarget(target);
  }

  return null;
}

KnexDialect? _dialectFromConnectTarget(Expression? target) {
  if (target == null) return null;

  String? className;
  if (target is SimpleIdentifier) {
    className = target.name;
  } else if (target is PrefixedIdentifier) {
    className = target.identifier.name;
  } else if (target is PropertyAccess) {
    className = target.propertyName.name;
  }

  switch (className) {
    case 'KnexPostgres':
      return KnexDialect.postgres;
    case 'KnexMySQL':
      return KnexDialect.mysql;
    case 'KnexSQLite':
      return KnexDialect.sqlite;
    default:
      return null;
  }
}
