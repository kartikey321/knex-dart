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

// ── Schema-DDL corpus profiles ─────────────────────────────────────────────
//
// Unlike the query-corpus profiles above (applied once, shared across an
// entire run), every one of these is meant to be applied fresh into its own
// case's private, disposable schema — DDL cases routinely need OPPOSITE
// starting states for the identical table/column/constraint name (e.g.
// alter-table-add-unique needs `users.email` NOT yet uniquely constrained,
// while alter-table-drop-unique needs that exact same default-named
// constraint to already exist), which only a per-case schema can satisfy.
// DDL/text content is driver-specific and lives in each driver's own
// `test/live_execution/<driver>_schema_ddl_profiles.dart` (identity only
// here, matching the pattern above). See that file's docstring for the full
// per-profile rationale.
const schemaDdlEmptyV1 = FixtureProfileRef('schema_ddl_empty_v1', 'no prerequisite — self-contained CREATE-type cases');
const schemaDdlUsersBareV1 = FixtureProfileRef('schema_ddl_users_bare_v1', 'bare users table, zero columns — pure ADD-column cases');
const schemaDdlUsersConstraintsV1 = FixtureProfileRef('schema_ddl_users_constraints_v1', 'users(foo, test1, test2, email) — ADD-constraint-over-existing-column cases');
const schemaDdlUserSingularV1 = FixtureProfileRef('schema_ddl_user_singular_v1', "table literally named 'user' (singular)");
const schemaDdlUsersNicknameV1 = FixtureProfileRef('schema_ddl_users_nickname_v1', 'users(nickname) — drop/rename-column cases');
const schemaDdlUsersFooBarV1 = FixtureProfileRef('schema_ddl_users_foo_bar_v1', 'users(foo, bar) — drop-columns-multiple');
const schemaDdlUsersNicknameAvatarV1 = FixtureProfileRef('schema_ddl_users_nickname_avatar_v1', 'users(nickname, avatar) — drop-columns-multi');
const schemaDdlUsersTimestampsV1 = FixtureProfileRef('schema_ddl_users_timestamps_v1', 'users(created_at, updated_at) — drop-timestamps');
const schemaDdlUsersEmailV1 = FixtureProfileRef('schema_ddl_users_email_v1', 'users(email) — set/drop-nullable');
const schemaDdlUsersUniqueDefaultV1 = FixtureProfileRef('schema_ddl_users_unique_default_v1', 'users(email) with default-named unique constraint — drop-unique (unnamed)');
const schemaDdlUsersUniqueNamedV1 = FixtureProfileRef('schema_ddl_users_unique_named_v1', 'users(email) with a named unique constraint — drop-unique-named');
const schemaDdlUsersIndexDefaultV1 = FixtureProfileRef('schema_ddl_users_index_default_v1', 'users(email) with default-named index — drop-index (unnamed)');
const schemaDdlUsersIndexNamedV1 = FixtureProfileRef('schema_ddl_users_index_named_v1', 'users(email) with a named index — drop-index-named');
const schemaDdlUsersUniqueFooV1 = FixtureProfileRef('schema_ddl_users_unique_foo_v1', "users with a unique constraint literally named 'foo' — dropUnique(null, 'foo')");
const schemaDdlUsersIndexFooV1 = FixtureProfileRef('schema_ddl_users_index_foo_v1', "users with an index literally named 'foo' — dropIndex(null, 'foo')");
const schemaDdlUsersForeignFooV1 = FixtureProfileRef('schema_ddl_users_foreign_foo_v1', "users with an FK literally named 'foo' — dropForeign(null, 'foo')");
const schemaDdlUsersPrimaryNamedV1 = FixtureProfileRef('schema_ddl_users_primary_named_v1', "users with a PK named 'testconstraintname' — drop-primary-named");
const schemaDdlMembershipsBareV1 = FixtureProfileRef('schema_ddl_memberships_bare_v1', 'memberships(user_id, org_id), no PK — add-unique/index-composite, primary');
const schemaDdlMembershipsPkV1 = FixtureProfileRef('schema_ddl_memberships_pk_v1', 'memberships(user_id, org_id) with a composite PK — drop-primary');
const schemaDdlOrdersBareV1 = FixtureProfileRef('schema_ddl_orders_bare_v1', 'users + orders, no FK yet — add-column-foreign');
const schemaDdlOrdersFkV1 = FixtureProfileRef('schema_ddl_orders_fk_v1', 'users + orders with a default-named FK — drop-foreign');
const schemaDdlOrdersUserIdV1 = FixtureProfileRef('schema_ddl_orders_user_id_v1', 'users + orders(user_id), no FK yet — foreign, foreign-both-actions');
const schemaDdlTBareV1 = FixtureProfileRef('schema_ddl_t_bare_v1', "table literally named 't' — alter-table-column-unsigned");
const schemaDdlCompositeKeyTestV1 = FixtureProfileRef('schema_ddl_composite_key_test_v1', 'composite_key_test(column_a, column_b) with a matching unique constraint — drop-unique-composite');
const schemaDdlUsersRefV1 = FixtureProfileRef('schema_ddl_users_ref_v1', 'users(id) as an FK/reference target — create-table-foreign-*, drop-table, rename-table');
const schemaDdlUsersAccountsRefV1 = FixtureProfileRef('schema_ddl_users_accounts_ref_v1', 'users(id) + accounts(id) as FK targets — create-table-foreign-mixed-actions');
const schemaDdlUsersNameRefV1 = FixtureProfileRef('schema_ddl_users_name_ref_v1', 'users(id, name) — createTableLike source');
const schemaDdlUsersActiveRefV1 = FixtureProfileRef('schema_ddl_users_active_ref_v1', 'users(id, name, active) — create-view-bare');
const schemaDdlUsersAgeRefV1 = FixtureProfileRef('schema_ddl_users_age_ref_v1', 'users(id, name, age) — view-create-basic/or-replace/materialized');
const schemaDdlBillingSchemaV1 = FixtureProfileRef('schema_ddl_billing_schema_v1', "schema 'billing' pre-existing — drop-schema family");
const schemaDdlActiveUsersMvV1 = FixtureProfileRef('schema_ddl_active_users_mv_v1', "materialized view 'active_users_mv' pre-existing");
const schemaDdlActiveUsersMvConcurrentV1 = FixtureProfileRef('schema_ddl_active_users_mv_concurrent_v1', "materialized view 'active_users_mv' + unique index — refresh ... concurrently");
const schemaDdlViewToRefreshV1 = FixtureProfileRef('schema_ddl_view_to_refresh_v1', "materialized view 'view_to_refresh' pre-existing");
const schemaDdlViewToRefreshConcurrentV1 = FixtureProfileRef('schema_ddl_view_to_refresh_concurrent_v1', "materialized view 'view_to_refresh' + unique index — refresh ... concurrently");
const schemaDdlViewUsersV1 = FixtureProfileRef('schema_ddl_view_users_v1', "a VIEW literally named 'users' — view-drop");
const schemaDdlViewOldV1 = FixtureProfileRef('schema_ddl_view_old_v1', "view 'old_view' pre-existing — view-rename");
const schemaDdlViewActiveUsersV1 = FixtureProfileRef('schema_ddl_view_active_users_v1', "view 'active_users' pre-existing — drop-view-if-exists");
const schemaDdlMyschemaUsersTableV1 = FixtureProfileRef('schema_ddl_myschema_users_table_v1', "schema 'myschema' + table myschema.users — drop-table(-if-exists)-with-schema");
const schemaDdlMyschemaUsersViewV1 = FixtureProfileRef('schema_ddl_myschema_users_view_v1', "schema 'myschema' + view myschema.users — view-drop-with-schema");
const schemaDdlMyschemaCapUsersIndexV1 = FixtureProfileRef('schema_ddl_myschema_cap_users_index_v1', "schema 'mySchema' + table + index — alter-table-drop-index-with-schema");
const schemaDdlCitextUsersV1 = FixtureProfileRef('schema_ddl_citext_users_v1', 'citext extension + bare users table — column-specifictype-unique-notnull');

/// All known profile ids, for validation (e.g. a fixture link referencing
/// an id not in this list is itself a bug in the link table).
const knownFixtureProfiles = <FixtureProfileRef>[
  canonicalSeedV2,
  ddlEmptyV1,
  syntheticJoinV1,
  syntheticAggregateV1,
  accountsWindowV1,
  joinTargetsV1,
  schemaDdlEmptyV1,
  schemaDdlUsersBareV1,
  schemaDdlUsersConstraintsV1,
  schemaDdlUserSingularV1,
  schemaDdlUsersNicknameV1,
  schemaDdlUsersFooBarV1,
  schemaDdlUsersNicknameAvatarV1,
  schemaDdlUsersTimestampsV1,
  schemaDdlUsersEmailV1,
  schemaDdlUsersUniqueDefaultV1,
  schemaDdlUsersUniqueNamedV1,
  schemaDdlUsersIndexDefaultV1,
  schemaDdlUsersIndexNamedV1,
  schemaDdlUsersUniqueFooV1,
  schemaDdlUsersIndexFooV1,
  schemaDdlUsersForeignFooV1,
  schemaDdlUsersPrimaryNamedV1,
  schemaDdlMembershipsBareV1,
  schemaDdlMembershipsPkV1,
  schemaDdlOrdersBareV1,
  schemaDdlOrdersFkV1,
  schemaDdlOrdersUserIdV1,
  schemaDdlTBareV1,
  schemaDdlCompositeKeyTestV1,
  schemaDdlUsersRefV1,
  schemaDdlUsersAccountsRefV1,
  schemaDdlUsersNameRefV1,
  schemaDdlUsersActiveRefV1,
  schemaDdlUsersAgeRefV1,
  schemaDdlBillingSchemaV1,
  schemaDdlActiveUsersMvV1,
  schemaDdlActiveUsersMvConcurrentV1,
  schemaDdlViewToRefreshV1,
  schemaDdlViewToRefreshConcurrentV1,
  schemaDdlViewUsersV1,
  schemaDdlViewOldV1,
  schemaDdlViewActiveUsersV1,
  schemaDdlMyschemaUsersTableV1,
  schemaDdlMyschemaUsersViewV1,
  schemaDdlMyschemaCapUsersIndexV1,
  schemaDdlCitextUsersV1,
];
