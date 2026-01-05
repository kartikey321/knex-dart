import 'client/client.dart';
import 'query/sql_string.dart';
import 'util/knex_exception.dart';
import 'formatter/raw_formatter.dart';

/// Represents a raw SQL query or expression
///
/// Raw queries bypass the query builder and are inserted directly into the SQL.
/// Supports both positional (`?`) and named (`:name`) parameter bindings.
///
/// Example:
/// ```dart
/// // Positional bindings
/// knex.raw('SELECT * FROM users WHERE id = ?', [1]);
///
/// // Named bindings
/// knex.raw('SELECT * FROM users WHERE id = :userId', {'userId': 1});
///
/// // Identifier interpolation (wrapped with quotes)
/// knex.raw('SELECT :column: FROM :table:', {
///   'column': 'name',
///   'table': 'users'
/// });
/// ```
class Raw {
  final Client _client;
  String _sql = '';
  dynamic _bindings =
      []; // Changed from List<dynamic> to dynamic to support both List and Map

  // Wrapping strings applied during toSQL() compilation
  // JS: lines 33-34, applied in toSQL() at lines 88-93
  String? _wrappedBefore;
  String? _wrappedAfter;

  /// Flag to identify Raw instances
  bool get isRawInstance => true;

  Raw(this._client);

  /// Set the SQL and bindings for this raw query
  ///
  /// JS Reference: lib/raw.js lines 40-48
  Raw set(String sql, [dynamic bindings]) {
    _sql = sql;

    if (bindings == null) {
      _bindings = [];
    } else if (bindings is List) {
      _bindings = bindings; // Keep as List for positional bindings
    } else if (bindings is Map) {
      _bindings = bindings; // Keep as Map for named bindings (FIXED)
    } else {
      _bindings = [bindings]; // Wrap single value in array
    }

    return this;
  }

  /// Get the SQL string
  String get sql => _sql;

  /// Get the bindings
  dynamic get bindings => _bindings;

  /// Get the client
  Client get client => _client;

  /// Wrap this raw query with before/after strings
  ///
  /// JS Reference: lib/raw.js lines 62-66
  /// Stores wrapping values to be applied during toSQL() compilation.
  /// This allows the same Raw object to be compiled multiple times.
  ///
  /// Example:
  /// ```dart
  /// raw('SELECT 1').wrap('(', ')')
  ///   .toSQL()  // Returns: '(SELECT 1)'
  /// ```
  Raw wrap(String before, String after) {
    _wrappedBefore = before; // Store for later (JS line 63)
    _wrappedAfter = after; // Store for later (JS line 64)
    return this; // Return this for chaining (JS line 65)
  }

  /// Compile to SQL with bindings
  ///
  /// JS Reference: lib/raw.js lines 74-128
  /// Returns SqlString object with compiled SQL, bindings, and metadata.
  /// This implementation covers basic behavior - binding replacement
  /// will be added in Steps 3-5.
  ///
  /// Example:
  /// ```dart
  /// raw('SELECT 1').wrap('(', ')').toSQL()
  ///   // Returns: SqlString(sql: '(SELECT 1)', bindings: [], method: 'raw')
  /// ```
  SqlString toSQL() {
    // JS Reference: lib/raw.js lines 74-128
    String compiledSql = _sql;
    List<dynamic> compiledBindings;

    // Step 1: Handle bindings based on type (JS lines 76-86)
    if (_bindings is List && (_bindings as List).isNotEmpty) {
      // Array bindings - use positional formatter
      final formatted = RawFormatter.replacePositionalBindings(
        _sql,
        _bindings as List<dynamic>,
        _client,
      );
      compiledSql = formatted.sql;
      compiledBindings = formatted.bindings;
    } else if (_bindings is Map && (_bindings as Map).isNotEmpty) {
      // Object bindings - use named formatter
      final formatted = RawFormatter.replaceNamedBindings(
        _sql,
        _bindings as Map<String, dynamic>,
        _client,
      );
      compiledSql = formatted.sql;
      compiledBindings = formatted.bindings;
    } else {
      // Empty or single value (JS lines 81-85)
      compiledBindings = _bindings is List ? _bindings as List<dynamic> : [];
    }

    // Step 2: Validate bindings don't contain null (JS lines 104-113)
    _validateBindings(compiledBindings);

    // Step 3: Apply wrapping (JS lines 88-93)
    if (_wrappedBefore != null && _wrappedBefore!.isNotEmpty) {
      compiledSql = _wrappedBefore! + compiledSql;
    }
    if (_wrappedAfter != null && _wrappedAfter!.isNotEmpty) {
      compiledSql = compiledSql + _wrappedAfter!;
    }

    // Step 4: Generate query UID (JS line 115: __knexQueryUid = nanoid())
    final uid = _generateUid();

    return SqlString(compiledSql, compiledBindings, method: 'raw', uid: uid);
  }

  /// Generate a unique ID for this query
  ///
  /// JS uses nanoid() which generates 21-char alphanumeric IDs
  /// We'll use a simpler approach: timestamp + random
  String _generateUid() {
    final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final random =
        (DateTime.now().microsecond * 1000 + DateTime.now().millisecond)
            .toRadixString(36);
    return '$timestamp$random'.substring(0, 12); // Match nanoid default length
  }

  /// Validate bindings don't contain null values
  ///
  /// JS Reference: lib/util/helpers.js lines 16-42 (containsUndefined)
  /// Throws KnexException if any binding is null (Dart) / undefined (JS)
  void _validateBindings(List<dynamic> bindings) {
    if (_containsNull(bindings)) {
      final indices = _getNullIndices(bindings);
      throw KnexException(
        'Undefined binding(s) detected for keys $indices when compiling RAW query: $_sql',
      );
    }
  }

  /// Recursively check if value contains null
  ///
  /// JS Reference: lib/util/helpers.js lines 16-42
  /// Dart: null ≈ JS undefined
  bool _containsNull(dynamic value) {
    if (value is List) {
      return value.any(_containsNull);
    } else if (value is Map) {
      return value.values.any(_containsNull);
    }
    return value == null;
  }

  /// Get indices/keys of null values
  ///
  /// JS Reference: lib/util/helpers.js lines 44-64
  List<dynamic> _getNullIndices(dynamic bindings) {
    final indices = <dynamic>[];
    if (bindings is List) {
      for (var i = 0; i < bindings.length; i++) {
        if (_containsNull(bindings[i])) {
          indices.add(i);
        }
      }
    } else if (bindings is Map) {
      for (final key in bindings.keys) {
        if (_containsNull(bindings[key])) {
          indices.add(key);
        }
      }
    }
    return indices;
  }

  @override
  String toString() => _sql;

  /// Execute this raw query
  Future<dynamic> execute() {
    return _client.rawQuery(_sql, _bindings);
  }

  /// Alias for execute
  Future<dynamic> then(Function(dynamic value) onValue, {Function? onError}) {
    return execute().then(onValue, onError: onError);
  }
}
