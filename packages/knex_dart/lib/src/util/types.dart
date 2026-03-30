/// Type definitions for Knex Dart
///
/// These types replace generic `dynamic` with more specific types
/// for better type safety and IDE support.
library;

/// Connection configuration
/// Can be a Map for connection parameters or a String for connection URI
typedef ConnectionConfig = Object;

/// Result from a database query
/// This is intentionally dynamic as different drivers return different types,
/// but will be typed per-driver in Phase 2
typedef QueryResult = List<Map<String, dynamic>>;

/// Raw query result (driver-specific)
/// Will be refined per-dialect in Phase 2
typedef RawQueryResult = dynamic;

/// Database connection
/// Type depends on the driver (pg.Connection, mysql.Connection, etc.)
/// Will be refined per-dialect in Phase 2
typedef DatabaseConnection = dynamic;

/// Value for SQL binding
/// Can be String, num, bool, List, Map, DateTime, null
typedef BindingValue = Object?;

/// List of binding values
typedef BindingList = List<BindingValue>;

/// Query context for post-processing
typedef QueryContext = Map<String, dynamic>;
