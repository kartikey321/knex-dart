# knex_dart_lint

Optional `custom_lint` plugin for `knex_dart`.

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

Add to your app/package `pubspec.yaml`:

```yaml
dev_dependencies:
  custom_lint: ^0.7.0
  knex_dart_lint:
    path: ../packages/knex_dart_lint
```

Then update `analysis_options.yaml`:

```yaml
analyzer:
  plugins:
    - custom_lint
```

## Run

```bash
dart run custom_lint
```

## Confidence behavior

Dialect capability rules emit diagnostics only when dialect inference is high-confidence.
If inference is unknown, those rules intentionally stay silent.

## Troubleshooting

If CLI works but IDE does not show diagnostics:

1. Confirm `analysis_options.yaml` includes `analyzer.plugins: [custom_lint]`.
2. Run `dart pub get` in the workspace and the consuming app.
3. Ensure the IDE can resolve `dart` from its environment `PATH`.
4. Open the `custom_lint.log` from the IDE and check for process spawn errors.

See `docs/mvp_rules.md` for the locked rule contract.
