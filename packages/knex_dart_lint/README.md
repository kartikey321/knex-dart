# knex_dart_lint

Optional analyzer plugin for `knex_dart`, built on `analysis_server_plugin`.

This package provides dialect-aware warnings for query APIs that are unsupported
for the inferred driver.

## Rule Catalog

### Dialect capability rules

- `dialect_unsupported_returning`
- `dialect_unsupported_full_outer_join`
- `dialect_unsupported_lateral_join`
- `dialect_unsupported_on_conflict_merge`
- `dialect_unsupported_cte`
- `dialect_unsupported_window_functions`
- `dialect_unsupported_json`
- `dialect_unsupported_intersect_except`

### Query argument correctness rules

- `invalid_where_operator`
- `where_null_value`
- `invalid_order_direction`
- `limit_non_int_argument`
- `insert_wrong_value_type`
- `where_null_typed_value`

## Enable

Add a top-level `plugins` section to the `analysis_options.yaml` at the root
of your package or [workspace](https://dart.dev/tools/pub/workspaces) (plugins
cannot be enabled from a nested analysis options file):

```yaml
plugins:
  knex_dart_lint: ^0.3.0
```

While developing against a local checkout, use a path instead:

```yaml
plugins:
  knex_dart_lint:
    path: ../packages/knex_dart_lint
```

No separate dev dependency or CLI runner is needed — `knex_dart_lint` is a
native analyzer plugin, so its diagnostics show up directly from `dart
analyze` / `flutter analyze` and in the IDE, the same as built-in lints.

Restart the Dart Analysis Server (or your IDE) after changing the `plugins`
section for the change to take effect.

## Enabling an opt-in rule

Warning-severity rules are on by default. Opt-in lint rules — currently just
`where_null_value` — are disabled by default and must be enabled under
`diagnostics`:

```yaml
plugins:
  knex_dart_lint:
    version: ^0.3.0
    diagnostics:
      where_null_value: true
```

## Confidence behavior

Dialect capability rules emit diagnostics only when dialect inference is high-confidence.
If inference is unknown, those rules intentionally stay silent.

## Suppressing a diagnostic

```dart
// ignore: knex_dart_lint/dialect_unsupported_returning

// ignore_for_file: knex_dart_lint/dialect_unsupported_returning
```

## Troubleshooting

If diagnostics don't show up:

1. Confirm `analysis_options.yaml` has a top-level `plugins:` section (not
   nested under `analyzer:` — that was the old `custom_lint` layout).
2. Run `dart pub get` in the workspace and the consuming app.
3. Restart the Dart Analysis Server / restart the IDE.
4. Ensure the IDE can resolve `dart` from its environment `PATH`.

See `docs/mvp_rules.md` for the locked rule contract.
