// Web entrypoint for DuckDB client.
//
// `dart_duckdb` automatically uses DuckDB WASM on web. The shared client
// implementation already conditionally configures native library loading via
// `configure_stub.dart`, which is a no-op on web.
export 'duckdb_client.dart';
