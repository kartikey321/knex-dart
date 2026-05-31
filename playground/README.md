# knex_dart Playground

Browser playground for `knex_dart`, deployed at:

https://playground.knex.mahawarkartikey.in/

## What It Does

- Monaco editor with Dart language registration
- Dart LSP diagnostics, hover, completions, and auto-imports via `dart_lsp.wasm`
- Browser lint worker for lightweight dialect checks
- In-browser Dart compile/run via dart-live CFE + VM WASM
- Embedded execution against:
  - PostgreSQL-compatible PGlite for the `postgres` dialect
  - sql.js SQLite for `sqlite` and non-Postgres fallback
- Query result table and embedded DB visualizer

The playground executes SQL printed by helper functions in the snippet. For example:

```dart
void sql(SqlString s) =>
    print(jsonEncode({'sql': s.sql, 'bindings': s.bindings}));

void schema(List<Map<String, dynamic>> statements) {
  for (final s in statements) {
    print(jsonEncode({
      'sql': s['sql'] as String,
      'bindings': (s['bindings'] as List?)?.cast<dynamic>() ?? [],
    }));
  }
}
```

Schema builders must be emitted explicitly:

```dart
schema(db.schemaBuilder().createTable('products', (t) {
  t.increments('id');
  t.string('name').notNullable();
}).toSQL());
```

## Run Locally

```bash
cd playground
npm ci
npm run dev
```

Default URL: `http://localhost:5177`

## Build

```bash
cd playground
npm run check
npm run build
```

Static output goes to `playground/dist`.

## Deploy Manually

```bash
cd playground
npx wrangler pages deploy dist --project-name=knex-dart-playground --branch main
```

The CI workflow deploys on `playground-v*.*.*` tags.

## Dart Assets

The `public/dart-live/` directory contains the browser Dart runtime/analyzer assets:

- `dart_cfe.mjs` / `dart_cfe.wasm` — compiles Dart source to kernel bytes
- `dart_il.mjs` / `dart_il.wasm` — runs compiled kernel bytes
- `dart_lsp.mjs` / `dart_lsp.wasm` — Dart LSP server for Monaco diagnostics/completions
- `dart_sdk.sum` — SDK summary used by the LSP server
- `knex_dart.dill` — compiled package dill used by the runtime
- `knex_dart_packages.bin` — DPKG source bundle used by the LSP server for package analysis
- `vm_platform.dill` — VM platform dill used by the runtime

If `knex_dart` public APIs change, rebuild both `knex_dart.dill` and `knex_dart_packages.bin` before deploying.

