# knex_dart_capabilities

Shared dialect capability metadata for the Knex Dart ecosystem.

This package is intentionally tiny and dependency-free. It exists so runtime
(`knex_dart`) and tooling (`knex_dart_lint`) can consume one canonical
capability matrix without drift.

## Exports

- `KnexDialect`
- `SqlCapability`
- `dialectCapabilities`
- `supportsCapability(...)`
- `dialectFromDriverName(...)`
