/// Base exception class for all Knex errors
class KnexException implements Exception {
  final String message;
  final StackTrace? stackTrace;
  final Object? cause;

  const KnexException(this.message, {this.stackTrace, this.cause});

  @override
  String toString() {
    final buffer = StringBuffer('KnexException: $message');
    if (cause != null) {
      buffer.write('\nCaused by: $cause');
    }
    if (stackTrace != null) {
      buffer.write('\n$stackTrace');
    }
    return buffer.toString();
  }
}

/// Exception thrown when query times out
class KnexTimeoutException extends KnexException {
  const KnexTimeoutException(super.message, {super.stackTrace, super.cause});
}

/// Exception thrown when connection cannot be acquired
class KnexConnectionException extends KnexException {
  const KnexConnectionException(super.message, {super.stackTrace, super.cause});
}

/// Exception thrown when transaction fails
class KnexTransactionException extends KnexException {
  const KnexTransactionException(
    super.message, {
    super.stackTrace,
    super.cause,
  });
}

/// Exception thrown when migration fails
class KnexMigrationException extends KnexException {
  const KnexMigrationException(super.message, {super.stackTrace, super.cause});
}

/// Exception thrown when migration table is locked
class KnexMigrationLockException extends KnexMigrationException {
  const KnexMigrationLockException(
    super.message, {
    super.stackTrace,
    super.cause,
  });
}

/// Exception thrown for invalid query construction
class KnexQueryException extends KnexException {
  const KnexQueryException(super.message, {super.stackTrace, super.cause});
}
