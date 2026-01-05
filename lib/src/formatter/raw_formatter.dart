import '../client/client.dart';

/// Result of formatting SQL with bindings
class FormattedSql {
  final String sql;
  final List<dynamic> bindings;

  FormattedSql(this.sql, this.bindings);
}

/// Raw SQL formatter - handles binding replacement
///
/// JS Reference: lib/formatter/rawFormatter.js
class RawFormatter {
  /// Replace positional bindings (? and ??)
  ///
  /// JS Reference: lib/formatter/rawFormatter.js lines 3-35
  ///
  /// Handles:
  /// - `?` → parameter placeholder ($1, $2, etc.)
  /// - `??` → identifier (wrapped with quotes)
  /// - `\?` → escaped (literal ?)
  ///
  /// Example:
  /// ```dart
  /// replacePositionalBindings(
  ///   'SELECT ?? FROM ?? WHERE id = ?',
  ///   ['name', 'users', 123],
  ///   client
  /// )
  /// // Returns: FormattedSql(
  /// //   sql: 'SELECT "name" FROM "users" WHERE id = $1',
  /// //   bindings: [123]
  /// // )
  /// ```
  static FormattedSql replacePositionalBindings(
    String sql,
    List<dynamic> bindings,
    Client client,
  ) {
    final result = <dynamic>[];
    var index = 0;

    // Regex from JS: /\\\?|\?\??/g
    // Matches: \? (escaped) or ? or ??
    final replaced = sql.replaceAllMapped(RegExp(r'\\\?|\?\??'), (match) {
      final matchStr = match[0]!;

      // Escaped question mark - return literal '?'
      if (matchStr == r'\?') {
        return '?';
      }

      final value = bindings[index++];

      // Double question mark - identifier binding
      if (matchStr == '??') {
        return client.wrapIdentifier(value.toString());
      }

      // Single question mark - regular binding
      result.add(value);
      return client.parameterPlaceholder(result.length);
    });

    // Validate all bindings were used (JS line 26-28)
    if (index != bindings.length) {
      throw Exception('Expected ${bindings.length} bindings, saw $index');
    }

    return FormattedSql(replaced, result);
  }

  /// Replace named bindings (:key and :key:)
  ///
  /// JS Reference: lib/formatter/rawFormatter.js lines 37-79
  ///
  /// Handles:
  /// - `:key` → parameter placeholder ($1, $2, etc.)
  /// - `:key:` → identifier (wrapped with quotes)
  /// - `\:key` → escaped (literal :key)
  /// - `:key:` before `::cast` → value binding (not identifier)
  ///
  /// Example:
  /// ```dart
  /// replaceNamedBindings(
  ///   'SELECT :column: FROM :table: WHERE id = :id',
  ///   {'column': 'name', 'table': 'users', 'id': 123},
  ///   client
  /// )
  /// // Returns: FormattedSql(
  /// //   sql: 'SELECT "name" FROM "users" WHERE id = $1',
  /// //   bindings: [123]
  /// // )
  /// ```
  static FormattedSql replaceNamedBindings(
    String sql,
    Map<String, dynamic> bindings,
    Client client,
  ) {
    final result = <dynamic>[];

    // Regex from JS with correct escaping: /\\?(:(\w+):(?=::)|:(\w+):(?!:)|:(\w+))/g
    // Matches:
    // - \:... (escaped)
    // - :word: followed by :: (p2 - identifier before ::cast)
    // - :word: NOT followed by : (p3 - identifier)
    // - :word (p4 - regular binding)
    final replaced = sql.replaceAllMapped(
      RegExp(r'\\?(:(\w+):(?=::)|:(\w+):(?!:)|:(\w+))'),
      (match) {
        final matchStr = match[0]!;
        final p1 = match[1];
        final p2 = match[2];
        final p3 = match[3];
        final p4 = match[4];

        // If match !== p1, backslash was consumed (escaped)
        if (matchStr != p1) {
          return p1!; // Return without backslash
        }

        // Extract the key name from whichever group matched
        final part = p2 ?? p3 ?? p4;
        final key = matchStr.trim();
        final isIdentifier = key[key.length - 1] == ':'; // Ends with :
        final value = bindings[part];

        // Handle undefined/missing value
        if (value == null) {
          if (bindings.containsKey(part)) {
            result.add(value);
          }
          return matchStr; // Keep original placeholder
        }

        if (isIdentifier) {
          // :key: - identifier binding (wrapped, no parameter)
          return matchStr.replaceFirst(
            p1!,
            client.wrapIdentifier(value.toString()),
          );
        }

        // :key - regular value binding
        result.add(value);
        return matchStr.replaceFirst(
          p1!,
          client.parameterPlaceholder(result.length),
        );
      },
    );

    return FormattedSql(replaced, result);
  }
}
