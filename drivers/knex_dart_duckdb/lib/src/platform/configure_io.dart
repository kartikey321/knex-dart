import 'dart:io';

import 'package:dart_duckdb/open.dart' as ddb_open;
import 'package:dart_duckdb/dart_duckdb.dart' show OperatingSystem;

/// Detects and configures the DuckDB native shared library for each platform.
///
/// Called once before the first [duckdb.open] call. A no-op on platforms
/// where [dart_duckdb] handles loading automatically (Android, iOS).
///
/// **macOS** (Dart-native / server-side):
///   Install via Homebrew: `brew install duckdb`
///   Looks in: `/opt/homebrew/lib` (Apple Silicon), `/usr/local/lib` (Intel)
///
/// **Linux**:
///   Install via package manager or download from https://duckdb.org/docs/installation
///   Looks in: `/usr/local/lib`, `/usr/lib`, arch-specific multilib paths
///
/// **Windows**:
///   Download `duckdb.dll` from https://github.com/duckdb/duckdb/releases
///   Looks in: `%LOCALAPPDATA%\DuckDB`, `C:\Program Files\DuckDB`, same dir as exe
///
/// **Android / iOS**:
///   Handled by the dart_duckdb Flutter plugin — no setup required.
///
/// To specify a custom path, call [ddb_open.open.overrideFor] before opening
/// any database.
void configureNativeLibrary() {
  if (Platform.isMacOS) {
    _configureMacOS();
  } else if (Platform.isLinux) {
    _configureLinux();
  } else if (Platform.isWindows) {
    _configureWindows();
  }
  // Android and iOS: dart_duckdb bundles libduckdb via Flutter plugin — no override needed.
}

void _configureMacOS() {
  final candidates = [
    '/opt/homebrew/lib/libduckdb.dylib', // Apple Silicon — `brew install duckdb`
    '/usr/local/lib/libduckdb.dylib', // Intel Mac Homebrew
    '/usr/lib/libduckdb.dylib', // system-wide manual install
  ];

  final path = _firstExisting(candidates);
  if (path != null) {
    ddb_open.open.overrideFor(OperatingSystem.macOS, path);
    return;
  }

  // Last resort: check if DuckDB is already loaded into the process
  // (e.g. user called DynamicLibrary.open themselves, or a Flutter embedder
  // bundled it). dart_duckdb's default macOS handler does this check, so
  // we only reach here if none of the above paths exist — leave it to
  // dart_duckdb's default behaviour (which will throw UnsupportedError if
  // DuckDB really isn't present).
}

void _configureLinux() {
  // Build the multiarch lib directory for the current CPU.
  final arch = _linuxMultiarch();

  final candidates = [
    '/usr/local/lib/libduckdb.so', // manual install / make install
    '/usr/lib/libduckdb.so', // distro package
    if (arch != null) '/usr/lib/$arch/libduckdb.so', // Debian/Ubuntu multiarch
    '/usr/lib64/libduckdb.so', // RHEL / Fedora / openSUSE
    '/opt/duckdb/lib/libduckdb.so', // custom prefix install
  ];

  final path = _firstExisting(candidates);
  if (path != null) {
    ddb_open.open.overrideFor(OperatingSystem.linux, path);
  }
}

void _configureWindows() {
  final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
  final programFiles = Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
  final programFilesX86 = Platform.environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)';

  // Executable directory — user may have placed duckdb.dll next to their app.
  final exeDir = File(Platform.resolvedExecutable).parent.path;

  final candidates = [
    if (localAppData.isNotEmpty) '$localAppData\\DuckDB\\duckdb.dll',
    '$programFiles\\DuckDB\\duckdb.dll',
    '$programFilesX86\\DuckDB\\duckdb.dll',
    '$exeDir\\duckdb.dll',
    r'C:\duckdb\duckdb.dll', // ad-hoc placement
  ];

  final path = _firstExisting(candidates);
  if (path != null) {
    ddb_open.open.overrideFor(OperatingSystem.windows, path);
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

String? _firstExisting(List<String> candidates) {
  for (final p in candidates) {
    if (File(p).existsSync()) return p;
  }
  return null;
}

/// Returns the Debian/Ubuntu multiarch tuple for the running CPU, or null if
/// the architecture is unrecognised or not needed.
String? _linuxMultiarch() {
  // `uname -m` output → Debian multiarch triplet
  final result = Process.runSync('uname', ['-m']);
  if (result.exitCode != 0) return null;
  final machine = (result.stdout as String).trim();
  switch (machine) {
    case 'x86_64':
      return 'x86_64-linux-gnu';
    case 'aarch64':
      return 'aarch64-linux-gnu';
    case 'armv7l':
      return 'arm-linux-gnueabihf';
    default:
      return null;
  }
}
