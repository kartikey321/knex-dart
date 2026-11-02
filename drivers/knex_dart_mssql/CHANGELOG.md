## 0.2.1

Constraint-only release. No source changes; identical behaviour to 0.2.0.

- Caps `knex_dart` at `<1.4.0` (was `^1.2.1`, which admitted every 1.x).

  This release line expects core to compile `?` placeholders and rewrites them
  for FreeTDS itself. `knex_dart` 1.4.0 changes MSSQL compilation to emit
  `@p0`/`@p1`/… instead, so pairing it with this driver breaks the bindings of
  every query built through the QueryBuilder — silently as far as resolution is
  concerned, since `^1.2.1` accepts it. (Raw `rawSql()` / `executeRaw()` are
  unaffected; they do their own rewriting.)

  0.2.0 cannot be amended after publication, so the bound ships here instead.
  Anyone on `knex_dart_mssql: ^0.2.0` picks this up automatically on their next
  `pub upgrade` and stays on a compatible core rather than being upgraded into
  a broken pair.

  To move to `knex_dart` 1.4.0 or later, upgrade to `knex_dart_mssql` 0.3.2+,
  which is the pure-Dart driver (`package:mssql`, no FreeTDS) and requires
  `^1.4.0`.

## 0.2.0

- Added `QueryInterceptor` pipeline support: attach OTel, logging, or custom
  interceptors via the `interceptors` parameter on `KnexMSSQL.connect()`.
- Fixed schema compiler `renameColumn` to emit the correct `exec sp_rename`
  syntax with full `[schema].[table].[column]` qualified name.
- Fixed savepoint lifecycle events routed through child transaction ID.
- Fixed exception propagation in transaction rollback using
  `Error.throwWithStackTrace`.
- Fixed savepoint ID generation to use a per-instance counter.

## 0.1.0

- Initial release.
- Microsoft SQL Server driver for `knex_dart`.
