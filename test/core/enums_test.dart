import 'package:knex_dart/src/util/enums.dart';
import 'package:test/test.dart';

void main() {
  group('Enums Tests', () {
    test('IsolationLevel toString() returns correct SQL keywords', () {
      expect(IsolationLevel.readUncommitted.toString(), 'read uncommitted');
      expect(IsolationLevel.readCommitted.toString(), 'read committed');
      expect(IsolationLevel.snapshot.toString(), 'snapshot');
      expect(IsolationLevel.repeatableRead.toString(), 'repeatable read');
      expect(IsolationLevel.serializable.toString(), 'serializable');
    });

    test('LockMode toSQL() returns correct SQL keywords', () {
      expect(LockMode.forUpdate.toSQL(), 'FOR UPDATE');
      expect(LockMode.forShare.toSQL(), 'FOR SHARE');
      expect(LockMode.forNoKeyUpdate.toSQL(), 'FOR NO KEY UPDATE');
      expect(LockMode.forKeyShare.toSQL(), 'FOR KEY SHARE');
    });

    test('WaitMode toSQL() returns correct SQL keywords', () {
      expect(WaitMode.noWait.toSQL(), 'NOWAIT');
      expect(WaitMode.skipLocked.toSQL(), 'SKIP LOCKED');
    });

    test('JoinType toSQL() returns correct SQL keywords', () {
      expect(JoinType.inner.toSQL(), 'INNER JOIN');
      expect(JoinType.left.toSQL(), 'LEFT JOIN');
      expect(JoinType.leftOuter.toSQL(), 'LEFT OUTER JOIN');
      expect(JoinType.right.toSQL(), 'RIGHT JOIN');
      expect(JoinType.rightOuter.toSQL(), 'RIGHT OUTER JOIN');
      expect(JoinType.outer.toSQL(), 'OUTER JOIN');
      expect(JoinType.fullOuter.toSQL(), 'FULL OUTER JOIN');
      expect(JoinType.cross.toSQL(), 'CROSS JOIN');
    });

    test('ComparisonOperator toString() returns correct SQL operators', () {
      expect(ComparisonOperator.equals.toString(), '=');
      expect(ComparisonOperator.notEquals.toString(), '!=');
      expect(ComparisonOperator.lessThan.toString(), '<');
      expect(ComparisonOperator.lessThanOrEqual.toString(), '<=');
      expect(ComparisonOperator.greaterThan.toString(), '>');
      expect(ComparisonOperator.greaterThanOrEqual.toString(), '>=');
      expect(ComparisonOperator.like.toString(), 'LIKE');
      expect(ComparisonOperator.ilike.toString(), 'ILIKE');
      expect(ComparisonOperator.notLike.toString(), 'NOT LIKE');
      expect(ComparisonOperator.notILike.toString(), 'NOT ILIKE');
    });

    test('OrderDirection toString() returns correct SQL keywords', () {
      expect(OrderDirection.asc.toString(), 'ASC');
      expect(OrderDirection.desc.toString(), 'DESC');
    });

    test('ForeignKeyAction toString() returns correct SQL keywords', () {
      expect(ForeignKeyAction.cascade.toString(), 'CASCADE');
      expect(ForeignKeyAction.restrict.toString(), 'RESTRICT');
      expect(ForeignKeyAction.setNull.toString(), 'SET NULL');
      expect(ForeignKeyAction.setDefault.toString(), 'SET DEFAULT');
      expect(ForeignKeyAction.noAction.toString(), 'NO ACTION');
    });
  });
}
