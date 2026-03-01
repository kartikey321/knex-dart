import 'raw.dart';
import 'query/sql_string.dart';

/// Column reference that should behave like a Raw fragment
///
/// Mirrors Knex.js where Ref extends Raw, so it can be used anywhere a Raw is
/// accepted and benefits from wrapping/UID handling in Raw.toSQL().
class Ref extends Raw {
  final String ref;
  String? _alias;
  String? _schema;

  Ref(super.client, this.ref);

  /// Set an alias for this reference
  Ref as(String alias) {
    _alias = alias;
    return this;
  }

  /// Set schema for this reference
  Ref withSchema(String schema) {
    _schema = schema;
    return this;
  }

  /// Format this reference using the client's identifier wrapper
  @override
  SqlString toSQL() {
    // Build base ref with optional schema prefix
    final base = _schema != null ? '${_schema!}.$ref' : ref;

    // Wrap each part of the reference
    final parts = base.split('.');
    final wrapped = parts.map(client.wrapIdentifier).join('.');

    // Apply alias if present
    final sql =
        _alias != null ? '$wrapped AS ${client.wrapIdentifier(_alias!)}' : wrapped;

    // Store on Raw and delegate to Raw.toSQL for wrapping/UID/binding handling
    set(sql, []);
    return super.toSQL();
  }

  @override
  String toString() => toSQL().toString();
}
