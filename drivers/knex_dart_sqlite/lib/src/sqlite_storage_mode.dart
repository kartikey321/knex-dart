const Set<String> kSQLiteWebStorageModes = {
  'memory',
  'indexedDb',
  'opfs',
  'auto',
};

void validateSQLiteWebStorageMode(String value) {
  if (!kSQLiteWebStorageModes.contains(value)) {
    throw ArgumentError(
      'Unsupported SQLite web storageMode "$value". '
      'Expected one of: memory, indexedDb, opfs, auto.',
    );
  }
}

void rejectSQLiteWebStorageModeOnNative(String? value) {
  if (value == null) return;
  validateSQLiteWebStorageMode(value);
  throw UnsupportedError(
    'SQLite webStorageMode is only supported on web/WASM. '
    'Remove webStorageMode when using the native sqlite3 driver.',
  );
}
