import 'package:knex_dart/src/util/knex_exception.dart';
import 'package:test/test.dart';

void main() {
  group('KnexException Tests', () {
    test('KnexException toString() formats correctly without cause/stack', () {
      const ex = KnexException('Test error');
      expect(ex.toString(), equals('KnexException: Test error'));
    });

    test('KnexException toString() includes cause', () {
      final cause = FormatException('Bad format');
      final ex = KnexException('Test error', cause: cause);
      expect(
        ex.toString(),
        equals(
          'KnexException: Test error\nCaused by: FormatException: Bad format',
        ),
      );
    });

    test('KnexException toString() includes stackTrace', () {
      final stack = StackTrace.fromString('stack_line_1\nstack_line_2');
      final ex = KnexException('Test error', stackTrace: stack);
      expect(
        ex.toString(),
        equals('KnexException: Test error\nstack_line_1\nstack_line_2'),
      );
    });

    test('KnexException toString() includes both cause and stackTrace', () {
      final cause = ArgumentError('Missing required arg');
      final stack = StackTrace.fromString('stack_frame_1\nstack_frame_2');
      final ex = KnexException(
        'Test multi error',
        cause: cause,
        stackTrace: stack,
      );
      expect(
        ex.toString(),
        equals(
          'KnexException: Test multi error\nCaused by: Invalid argument(s): Missing required arg\nstack_frame_1\nstack_frame_2',
        ),
      );
    });

    test('All subclasses inherit properly', () {
      expect(const KnexTimeoutException('Timeout'), isA<KnexException>());
      expect(const KnexConnectionException('Conn err'), isA<KnexException>());
      expect(const KnexTransactionException('Tx err'), isA<KnexException>());
      expect(const KnexMigrationException('Migr err'), isA<KnexException>());
      expect(
        const KnexMigrationLockException('Lock err'),
        isA<KnexMigrationException>(),
      );
      expect(const KnexQueryException('Query err'), isA<KnexException>());
    });
  });
}
