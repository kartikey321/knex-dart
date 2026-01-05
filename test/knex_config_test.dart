import 'package:test/test.dart';
import 'package:knex_dart/src/client/knex_config.dart';

void main() {
  group('KnexConfig', () {
    test('should create with required parameters', () {
      final config = KnexConfig(
        client: 'postgres',
        connection: {'host': 'localhost'},
      );

      expect(config.client, 'postgres');
      expect(config.connection, {'host': 'localhost'});
      expect(config.useNullAsDefault, false);
      expect(config.debug, false);
    });

    test('should create with all parameters', () {
      final config = KnexConfig(
        client: 'mysql',
        connection: {'host': 'localhost'},
        useNullAsDefault: true,
        debug: true,
        pool: PoolConfig(min: 1, max: 5),
      );

      expect(config.useNullAsDefault, true);
      expect(config.debug, true);
      expect(config.pool?.min, 1);
      expect(config.pool?.max, 5);
    });

    test('should copy with new values', () {
      final config1 = KnexConfig(
        client: 'postgres',
        connection: {'host': 'localhost'},
      );

      final config2 = config1.copyWith(client: 'mysql', debug: true);

      expect(config2.client, 'mysql');
      expect(config2.debug, true);
      // Original connection should be preserved
      expect(config2.connection, {'host': 'localhost'});
    });
  });

  group('PoolConfig', () {
    test('should create with defaults', () {
      final pool = PoolConfig();

      expect(pool.min, 2);
      expect(pool.max, 10);
      expect(pool.acquireTimeoutMillis, 60000);
    });

    test('should create with custom values', () {
      final pool = PoolConfig(
        min: 5,
        max: 20,
        acquireTimeoutMillis: 30000,
        idleTimeoutMillis: 10000,
      );

      expect(pool.min, 5);
      expect(pool.max, 20);
      expect(pool.acquireTimeoutMillis, 30000);
      expect(pool.idleTimeoutMillis, 10000);
    });
  });

  group('MigrationConfig', () {
    test('should create with defaults', () {
      final config = MigrationConfig();

      expect(config.directory, './migrations');
      expect(config.tableName, 'knex_migrations');
      expect(config.schemaName, null);
      expect(config.disableTransactions, false);
    });

    test('should create with custom values', () {
      final config = MigrationConfig(
        directory: './db/migrations',
        tableName: 'migrations',
        schemaName: 'public',
        disableTransactions: true,
      );

      expect(config.directory, './db/migrations');
      expect(config.tableName, 'migrations');
      expect(config.schemaName, 'public');
      expect(config.disableTransactions, true);
    });
  });
}
