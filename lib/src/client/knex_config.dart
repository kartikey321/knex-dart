/// Configuration for Knex instance
class KnexConfig {
  /// Database client/dialect name (e.g., 'postgres', 'mysql', 'sqlite3')
  final String client;

  /// Connection configuration
  /// Can be a Map with connection parameters or a connection string
  final dynamic connection;

  /// Connection pool configuration
  final PoolConfig? pool;

  /// Whether to use null as default for undefined values
  /// If false, uses SQL DEFAULT
  final bool useNullAsDefault;

  /// Enable debug mode (logs all queries)
  final bool debug;

  /// Custom function to wrap identifiers
  final String Function(String value)? wrapIdentifier;

  /// Custom function to post-process query responses
  final dynamic Function(dynamic response, dynamic queryContext)?
  postProcessResponse;

  /// Migration configuration
  final MigrationConfig? migrations;

  /// Seed configuration
  final SeedConfig? seeds;

  const KnexConfig({
    required this.client,
    required this.connection,
    this.pool,
    this.useNullAsDefault = false,
    this.debug = false,
    this.wrapIdentifier,
    this.postProcessResponse,
    this.migrations,
    this.seeds,
  });

  KnexConfig copyWith({
    String? client,
    dynamic connection,
    PoolConfig? pool,
    bool? useNullAsDefault,
    bool? debug,
    String Function(String value)? wrapIdentifier,
    dynamic Function(dynamic response, dynamic queryContext)?
    postProcessResponse,
    MigrationConfig? migrations,
    SeedConfig? seeds,
  }) {
    return KnexConfig(
      client: client ?? this.client,
      connection: connection ?? this.connection,
      pool: pool ?? this.pool,
      useNullAsDefault: useNullAsDefault ?? this.useNullAsDefault,
      debug: debug ?? this.debug,
      wrapIdentifier: wrapIdentifier ?? this.wrapIdentifier,
      postProcessResponse: postProcessResponse ?? this.postProcessResponse,
      migrations: migrations ?? this.migrations,
      seeds: seeds ?? this.seeds,
    );
  }
}

/// Connection pool configuration
class PoolConfig {
  /// Minimum number of connections to maintain
  final int min;

  /// Maximum number of connections
  final int max;

  /// Timeout for acquiring a connection (milliseconds)
  final int acquireTimeoutMillis;

  /// Idle timeout before destroying a connection (milliseconds)
  final int? idleTimeoutMillis;

  /// Maximum age of a connection (milliseconds)
  final int? maxConnectionAge;

  /// Interval in milliseconds between idle-connection reaping checks.
  /// Matches tarn.js default of 1000 ms.
  final int reapIntervalMillis;

  /// Function called after creating a connection
  final Future<void> Function(dynamic connection)? afterCreate;

  const PoolConfig({
    this.min = 2,
    this.max = 10,
    this.acquireTimeoutMillis = 60000,
    this.idleTimeoutMillis,
    this.maxConnectionAge,
    this.reapIntervalMillis = 1000,
    this.afterCreate,
  });
}

/// Migration configuration
class MigrationConfig {
  /// Directory containing migration files
  final String directory;

  /// Table name for storing migration state
  final String tableName;

  /// Schema name for migration table
  final String? schemaName;

  /// Disable transactions for migrations
  final bool disableTransactions;

  const MigrationConfig({
    this.directory = './migrations',
    this.tableName = 'knex_migrations',
    this.schemaName,
    this.disableTransactions = false,
  });
}

/// Seed configuration
class SeedConfig {
  /// Directory containing seed files
  final String directory;

  const SeedConfig({this.directory = './seeds'});
}
