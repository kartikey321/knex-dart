/// Fixture profiles are versioned, hand-authored schema+data definitions
/// that a case id is explicitly linked to per dialect — never inferred
/// from scanning a case's `.table()`/column calls. Inference risks two
/// silent failure modes: a broken case can "execute" successfully against
/// an overly-permissive guessed schema (a false pass), or a fine case can
/// fail against a schema nobody actually reviewed for it (a false alarm).
///
/// This file holds only profile *identity* (id + description) — it is
/// dialect-agnostic on purpose, since [FixtureProfileRef] is what the
/// report and the fixture-link table reference. The actual DDL/seed SQL
/// text for a profile is inherently dialect-specific (column types, DDL
/// syntax) and lives in each driver's own test tree, keyed by the same id.
library;

class FixtureProfileRef {
  final String id;
  final String description;

  const FixtureProfileRef(this.id, this.description);

  @override
  String toString() => id;
}

/// The baseline profile: users(5) / products(5) / orders(7), the same
/// shape the hand-written postgres integration suite already seeds — reused
/// here as the first, most broadly-linkable profile rather than inventing a
/// new baseline shape.
const canonicalSeedV1 = FixtureProfileRef(
  'canonical_seed_v1',
  'users(5) / products(5) / orders(7) baseline seed',
);

/// A minimal empty-schema profile: tables exist (so column/type references
/// resolve) but hold zero rows — for cases that only need to prove a
/// statement compiles and runs, not that it returns particular data.
const ddlEmptyV1 = FixtureProfileRef(
  'ddl_empty_v1',
  'users/products/orders tables created, zero rows',
);

/// All known profile ids, for validation (e.g. a fixture link referencing
/// an id not in this list is itself a bug in the link table).
const knownFixtureProfiles = <FixtureProfileRef>[canonicalSeedV1, ddlEmptyV1];
