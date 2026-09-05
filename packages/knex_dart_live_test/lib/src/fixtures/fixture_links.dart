/// The fixture-link table: which [FixtureProfileRef] id each case id runs
/// under, per dialect. This is the versioned, reviewed artifact the whole
/// framework's "never infer" rule depends on.
///
/// Every entry here must be backed by an empirical dry run that actually
/// built and executed the case's builder under that profile and observed
/// [MechanicalStatus.executedWithoutError] — never hand-guessed from a
/// case's id or category. A case id absent from a dialect's map here is
/// not linked to any profile yet and reports as
/// [MechanicalStatus.deferredFixture], which is the honest default.
library;

/// dialect -> case id -> fixture profile id.
///
/// Populated incrementally, dialect by dialect, from dry-run evidence — see
/// `drivers/knex_dart_<name>/test/live_execution/` for each dialect's dry
/// run and the evidence file it was derived from.
///
/// Deliberately excluded from postgres's `canonical_seed_v1` entries below:
/// `table/dotted-schema` (queries `public.users` via an explicitly-qualified
/// table reference). It "executed clean" in the raw dry run, but only
/// because an explicit schema qualifier bypasses `SET LOCAL search_path` —
/// it was silently reading the real integration suite's `public.users`
/// table, not the run's isolated schema. Linking it here would both violate
/// the isolation guarantee and record a false pass. Left unlinked
/// (reports as `deferredFixture`) until it gets dedicated handling.
const Map<String, Map<String, String>> fixtureLinksByDialect = {
  'postgres': {
    'clear/counters': 'canonical_seed_v1',
    'clear/group-basic': 'canonical_seed_v1',
    'clear/group-then-regroup': 'canonical_seed_v1',
    'clear/order-basic': 'canonical_seed_v1',
    'clear/order-then-reorder': 'canonical_seed_v1',
    'clear/select-basic': 'canonical_seed_v1',
    'clear/select-then-reselect': 'canonical_seed_v1',
    'clear/where-basic': 'canonical_seed_v1',
    'clear/where-then-rewhere': 'canonical_seed_v1',
    'delete/all': 'canonical_seed_v1',
    'delete/where': 'canonical_seed_v1',
    'dml/onconflict-merge-explicit': 'canonical_seed_v1',
    'dml/onconflict-merge-implicit-multi': 'canonical_seed_v1',
    'dml/returning-delete': 'canonical_seed_v1',
    'dml/returning-update': 'canonical_seed_v1',
    'except/wrapped-array': 'canonical_seed_v1',
    'exists/or-where': 'canonical_seed_v1',
    'exists/or-where-not': 'canonical_seed_v1',
    'exists/where': 'canonical_seed_v1',
    'exists/where-not': 'canonical_seed_v1',
    'from/alias': 'canonical_seed_v1',
    'group/raw': 'canonical_seed_v1',
    'insert/empty-array-noop': 'canonical_seed_v1',
    'insert/single': 'canonical_seed_v1',
    'intersect/wrapped-array': 'canonical_seed_v1',
    'lock/for-key-share': 'canonical_seed_v1',
    'lock/for-no-key-update': 'canonical_seed_v1',
    'lock/for-share': 'canonical_seed_v1',
    'lock/for-share-skip-locked': 'canonical_seed_v1',
    'lock/for-update': 'canonical_seed_v1',
    'lock/for-update-no-wait': 'canonical_seed_v1',
    'lock/for-update-skip-locked': 'canonical_seed_v1',
    'lock/for-update-tables': 'canonical_seed_v1',
    'select/alias-map-raw': 'canonical_seed_v1',
    'select/columns': 'canonical_seed_v1',
    'select/desc': 'canonical_seed_v1',
    'select/distinct': 'canonical_seed_v1',
    'select/limit-offset': 'canonical_seed_v1',
    'select/numeric-literal': 'canonical_seed_v1',
    'select/orderby-raw-direction': 'canonical_seed_v1',
    'select/star': 'canonical_seed_v1',
    'subquery/where-in-2level': 'canonical_seed_v1',
    'subquery/where-scalar': 'canonical_seed_v1',
    'subquery/where-scalar-callback': 'canonical_seed_v1',
    'union/array-callbacks': 'canonical_seed_v1',
    'union/wrapped-array': 'canonical_seed_v1',
    'unionAll/wrapped-array': 'canonical_seed_v1',
    'update/from-where-then-update': 'canonical_seed_v1',
    'update/join-mysql': 'canonical_seed_v1',
    'update/limit-mysql': 'canonical_seed_v1',
    'update/orderby-limit': 'canonical_seed_v1',
    'update/set': 'canonical_seed_v1',
    'update/two-cols': 'canonical_seed_v1',
    'upsert/merge': 'canonical_seed_v1',
    'upsert/merge-columns': 'canonical_seed_v1',
    'where/in': 'canonical_seed_v1',
    'where/named-binding-identifier': 'canonical_seed_v1',
    'where/not-between': 'canonical_seed_v1',
    'where/not-between-alt': 'canonical_seed_v1',
    'where/not-in': 'canonical_seed_v1',
    'where/not-null': 'canonical_seed_v1',
  },
};
