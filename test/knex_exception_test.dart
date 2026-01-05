import 'package:test/test.dart';
import 'package:knex_dart/src/util/knex_exception.dart';

void main() {
  group('KnexException', () {
    test('should create with message', () {
      final exception = KnexException('Test error');
      expect(exception.message, 'Test error');
      expect(exception.stackTrace, null);
      expect(exception.cause, null);
    });

    test('should create with message and cause', () {
      final cause = Exception('Original error');
      final exception = KnexException('Test error', cause: cause);
      expect(exception.message, 'Test error');
      expect(exception.cause, cause);
    });

    test('should format toString correctly', () {
      final exception = KnexException('Test error');
      expect(exception.toString(), contains('KnexException: Test error'));
    });

    test('should include cause in toString', () {
      final cause = Exception('Original error');
      final exception = KnexException('Test error', cause: cause);
      expect(exception.toString(), contains('Caused by:'));
    });
  });

  group('KnexTimeoutException', () {
    test('should create timeout exception', () {
      final exception = KnexTimeoutException('Query timed out');
      expect(exception.message, 'Query timed out');
      expect(exception is KnexException, true);
    });
  });

  group('KnexConnectionException', () {
    test('should create connection exception', () {
      final exception = KnexConnectionException('Connection failed');
      expect(exception.message, 'Connection failed');
      expect(exception is KnexException, true);
    });
  });

  group('KnexTransactionException', () {
    test('should create transaction exception', () {
      final exception = KnexTransactionException('Transaction failed');
      expect(exception.message, 'Transaction failed');
      expect(exception is KnexException, true);
    });
  });

  group('KnexMigrationException', () {
    test('should create migration exception', () {
      final exception = KnexMigrationException('Migration failed');
      expect(exception.message, 'Migration failed');
      expect(exception is KnexException, true);
    });
  });

  group('KnexMigrationLockException', () {
    test('should create migration lock exception', () {
      final exception = KnexMigrationLockException('Migration locked');
      expect(exception.message, 'Migration locked');
      expect(exception is KnexMigrationException, true);
      expect(exception is KnexException, true);
    });
  });

  group('KnexQueryException', () {
    test('should create query exception', () {
      final exception = KnexQueryException('Invalid query');
      expect(exception.message, 'Invalid query');
      expect(exception is KnexException, true);
    });
  });
}
