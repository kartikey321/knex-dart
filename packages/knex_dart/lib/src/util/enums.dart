/// Enums for type-safe Knex operations
///
/// to provide better type safety and IDE support in Dart.
library;

/// Query method types
enum QueryMethod { select, insert, update, delete, first, pluck, truncate }

/// Transaction isolation levels
enum IsolationLevel {
  readUncommitted('read uncommitted'),
  readCommitted('read committed'),
  snapshot('snapshot'),
  repeatableRead('repeatable read'),
  serializable('serializable');

  final String sql;
  const IsolationLevel(this.sql);

  @override
  String toString() => sql;
}

/// Row-level lock modes
enum LockMode {
  forUpdate,
  forShare,
  forNoKeyUpdate, // PostgreSQL-specific
  forKeyShare; // PostgreSQL-specific

  String toSQL() {
    switch (this) {
      case LockMode.forUpdate:
        return 'FOR UPDATE';
      case LockMode.forShare:
        return 'FOR SHARE';
      case LockMode.forNoKeyUpdate:
        return 'FOR NO KEY UPDATE';
      case LockMode.forKeyShare:
        return 'FOR KEY SHARE';
    }
  }
}

/// Lock wait modes
enum WaitMode {
  noWait,
  skipLocked;

  String toSQL() {
    switch (this) {
      case WaitMode.noWait:
        return 'NOWAIT';
      case WaitMode.skipLocked:
        return 'SKIP LOCKED';
    }
  }
}

/// Join types
enum JoinType {
  inner,
  left,
  leftOuter,
  right,
  rightOuter,
  outer,
  fullOuter,
  cross;

  String toSQL() {
    switch (this) {
      case JoinType.inner:
        return 'INNER JOIN';
      case JoinType.left:
        return 'LEFT JOIN';
      case JoinType.leftOuter:
        return 'LEFT OUTER JOIN';
      case JoinType.right:
        return 'RIGHT JOIN';
      case JoinType.rightOuter:
        return 'RIGHT OUTER JOIN';
      case JoinType.outer:
        return 'OUTER JOIN';
      case JoinType.fullOuter:
        return 'FULL OUTER JOIN';
      case JoinType.cross:
        return 'CROSS JOIN';
    }
  }
}

/// Comparison operators
enum ComparisonOperator {
  equals('='),
  notEquals('!='),
  lessThan('<'),
  lessThanOrEqual('<='),
  greaterThan('>'),
  greaterThanOrEqual('>='),
  like('LIKE'),
  ilike('ILIKE'), // PostgreSQL
  notLike('NOT LIKE'),
  notILike('NOT ILIKE'); // PostgreSQL

  final String sql;
  const ComparisonOperator(this.sql);

  @override
  String toString() => sql;
}

/// ORDER BY direction
enum OrderDirection {
  asc('ASC'),
  desc('DESC');

  final String sql;
  const OrderDirection(this.sql);

  @override
  String toString() => sql;
}

/// Foreign key actions
enum ForeignKeyAction {
  cascade('CASCADE'),
  restrict('RESTRICT'),
  setNull('SET NULL'),
  setDefault('SET DEFAULT'),
  noAction('NO ACTION');

  final String sql;
  const ForeignKeyAction(this.sql);

  @override
  String toString() => sql;
}

/// Column data types (for schema builder)
enum ColumnType {
  // Integers
  increments,
  integer,
  bigInteger,
  tinyInteger,
  smallInteger,
  mediumInteger,

  // Decimals
  decimal,
  float,
  double,

  // Strings
  string,
  text,
  char,
  varchar,

  // Binary
  binary,
  blob,
  longblob,
  mediumblob,
  tinyblob,

  // Dates
  date,
  datetime,
  time,
  timestamp,
  timestamps,

  // Boolean
  boolean,

  // JSON
  json,
  jsonb,

  // UUID
  uuid,

  // Enum
  enu,

  // Special
  specificType,
}

/// Conflict resolution strategies for ON CONFLICT
enum ConflictAction { merge, ignore }
