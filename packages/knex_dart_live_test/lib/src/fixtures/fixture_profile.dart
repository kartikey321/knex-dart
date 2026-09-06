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

/// The baseline profile: users(5) / products(5) / orders(7). Originally
/// `canonical_seed_v1` (retired — its narrower users/orders shape couldn't
/// cover a large cluster of where/having/select/json/onconflict cases found
/// in the next dry-run pass). v2 is a strict additive superset of v1's
/// shape and data — nothing behind an already-verified v1 link changed
/// meaning, it only gained more columns/indexes nothing referenced before.
const canonicalSeedV2 = FixtureProfileRef(
  'canonical_seed_v2',
  'users(5) / products(5) / orders(7) baseline seed, widened for '
  'where/having/select/json/onconflict cases',
);

/// A minimal empty-schema profile: tables exist (so column/type references
/// resolve) but hold zero rows — for cases that only need to prove a
/// statement compiles and runs, not that it returns particular data.
const ddlEmptyV1 = FixtureProfileRef(
  'ddl_empty_v1',
  'users/products/orders tables created, zero rows',
);

/// Generic join/set-op tables (`a`/`b`/`c`) for corpus cases that reference
/// bare, dialect-test-only table names rather than the canonical shape.
const syntheticJoinV1 = FixtureProfileRef(
  'synthetic_join_v1',
  'a/b/c tables for union/intersect/except/join-predicate cases',
);

/// Generic aggregate/where/having/window kitchen-sink table (`t`, plus the
/// single-purpose `src` and `inner_t`) for corpus cases that reference bare,
/// dialect-test-only table names rather than the canonical shape.
const syntheticAggregateV1 = FixtureProfileRef(
  'synthetic_aggregate_v1',
  't/src/inner_t tables for agg/having/where/on/window/jsonb cases',
);

/// Window-function batch's `accounts` table for corpus cases exercising
/// rank/denseRank/rowNumber partition/order-by columns.
const accountsWindowV1 = FixtureProfileRef(
  'accounts_window_v1',
  'accounts table for window function (rank/denseRank/rowNumber) cases',
);

/// Join-target and one-off tables (`contacts`, `phones`, `photos`, `docs`,
/// `contracts`, `admins`, reserved-word tables like `"group"`/`"user"`/
/// `"table"`, `employee`, etc.) for the `on/*` JoinClause family and a
/// grab-bag of cases each needing exactly one or two small tables.
const joinTargetsV1 = FixtureProfileRef(
  'join_targets_v1',
  'contacts/phones/photos/docs/contracts/admins/employee and other '
  'one-off join-target tables for the on/* family and similar cases',
);

/// All known profile ids, for validation (e.g. a fixture link referencing
/// an id not in this list is itself a bug in the link table).
const knownFixtureProfiles = <FixtureProfileRef>[
  canonicalSeedV2,
  ddlEmptyV1,
  syntheticJoinV1,
  syntheticAggregateV1,
  accountsWindowV1,
  joinTargetsV1,
];
