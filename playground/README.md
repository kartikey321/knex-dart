# knex_dart Playground (Browser-only MVP)

This folder contains a standalone browser-only playground scaffold with:

- Monaco editor
- Dart language registration
- Custom browser lint worker (mirrors key `knex_dart_lint` rules)
- Monaco marker mapping
- Runtime selector (`wasm` or `dart_eval`)
- Dart Wasm bridge package at `dart_wasm_bridge/` exporting JS-callable query builders

## Run

```bash
cd /Users/kartik/StudioProjects/knex/knex-dart-playground-web
npm install
./scripts/build_wasm.sh
npm run dev
```

Default URL: `http://localhost:5176`

## Current lint coverage

Implemented in-browser equivalents:

- `invalid_where_operator`
- `where_null_value`
- `invalid_order_direction`
- Dialect method guards:
  - `returning`, `fullOuterJoin`, lateral join variants
  - `with`, `withRecursive`
  - `rowNumber`, `denseRank`, `rank`
  - `jsonExtract`, `jsonSet`, `jsonInsert`
  - `intersect`, `except`

These are syntax-based checks, not full analyzer/type-inference checks.

## Wasm wiring steps

1. Edit `dart_wasm_bridge/web/main.dart` to adjust supported DSL/API.
2. Run `./scripts/build_wasm.sh`.
3. Confirm generated files exist:
   - `public/wasm/main.wasm`
   - `public/wasm/main.mjs`
4. Use the `Execution Input (JSON)` panel and click `Run`.

## Notes

- This browser-only MVP does not run official `dart analyze` or `custom_lint` plugin runtime.
- The worker lints are heuristic and aligned to your rule IDs/messages where practical.
- Monaco currently has Dart language registration + config; full semantic Dart tokenization can be added later.
