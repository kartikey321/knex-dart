// JS Baseline Tests for Window Functions (analytic)
// Run: node knex-dart/test/js/analytic_baseline.js  (from /Users/kartik/StudioProjects/knex/knex-js)
// These define the expected SQL output that the Dart port must match exactly.

const KnexInitializer = require('/Users/kartik/StudioProjects/knex/knex-js/knex.js');
const knex = KnexInitializer({ client: 'pg' });

console.log('=== Window Function (Analytic) Baseline Tests ===\n');

// ─── rank() ──────────────────────────────────────────────────────────────────

console.log('Test 1: rank() - string orderBy, string partitionBy');
let r = knex('users').select('*').rank('alias_name', 'email', 'firstName').toSQL();
console.log('SQL:', r.sql);
console.log('Bindings:', JSON.stringify(r.bindings));
console.log();

console.log('Test 2: rank() - array orderBy, array partitionBy');
r = knex('users').select('*').rank('alias_name', ['email', 'address'], ['firstName', 'lastName']).toSQL();
console.log('SQL:', r.sql);
console.log('Bindings:', JSON.stringify(r.bindings));
console.log();

console.log('Test 3: rank() - string orderBy only (no partitionBy)');
r = knex('users').select('*').rank('alias_name', 'email').toSQL();
console.log('SQL:', r.sql);
console.log('Bindings:', JSON.stringify(r.bindings));
console.log();

// ─── denseRank() ─────────────────────────────────────────────────────────────

console.log('Test 4: denseRank() - string orderBy, string partitionBy');
r = knex('users').select('*').denseRank('alias_name', 'email', 'firstName').toSQL();
console.log('SQL:', r.sql);
console.log('Bindings:', JSON.stringify(r.bindings));
console.log();

console.log('Test 5: denseRank() - array orderBy, array partitionBy');
r = knex('users').select('*').denseRank('alias_name', ['email', 'address'], ['firstName', 'lastName']).toSQL();
console.log('SQL:', r.sql);
console.log('Bindings:', JSON.stringify(r.bindings));
console.log();

// ─── rowNumber() ──────────────────────────────────────────────────────────────

console.log('Test 6: rowNumber() - string orderBy, string partitionBy');
r = knex('users').select('*').rowNumber('alias_name', 'email', 'firstName').toSQL();
console.log('SQL:', r.sql);
console.log('Bindings:', JSON.stringify(r.bindings));
console.log();

console.log('Test 7: rowNumber() - array orderBy, array partitionBy');
r = knex('users').select('*').rowNumber('alias_name', ['email', 'address'], ['firstName', 'lastName']).toSQL();
console.log('SQL:', r.sql);
console.log('Bindings:', JSON.stringify(r.bindings));
console.log();

console.log('Test 8: rowNumber() - raw OVER clause');
r = knex('users').select('*').rowNumber('alias_name', knex.raw('order by ?? desc', ['salary'])).toSQL();
console.log('SQL:', r.sql);
console.log('Bindings:', JSON.stringify(r.bindings));
console.log();

// ─── callback (function) syntax ──────────────────────────────────────────────

console.log('Test 9: rowNumber() - callback with orderBy + partitionBy');
r = knex('users').select('*').rowNumber('alias_name', function () {
    this.orderBy('email').partitionBy('firstName');
}).toSQL();
console.log('SQL:', r.sql);
console.log('Bindings:', JSON.stringify(r.bindings));
console.log();

console.log('Test 10: rowNumber() - callback partitionBy with direction');
r = knex('users').select('*').rowNumber('alias_name', function () {
    this.partitionBy('firstName', 'desc');
}).toSQL();
console.log('SQL:', r.sql);
console.log('Bindings:', JSON.stringify(r.bindings));
console.log();

console.log('Test 11: rowNumber() - callback partitionBy with multi-object');
r = knex('users').select('*').rowNumber('alias_name', function () {
    this.partitionBy([
        { column: 'firstName', order: 'asc' },
        { column: 'lastName', order: 'desc' },
    ]);
}).toSQL();
console.log('SQL:', r.sql);
console.log('Bindings:', JSON.stringify(r.bindings));
console.log();

// ─── null alias ──────────────────────────────────────────────────────────────

console.log('Test 12: rowNumber() - null alias');
r = knex('users').select('*').rowNumber(null, 'email', 'firstName').toSQL();
console.log('SQL:', r.sql);
console.log('Bindings:', JSON.stringify(r.bindings));
console.log();

// ─── with other SELECT columns ────────────────────────────────────────────────

console.log('Test 13: rowNumber() alongside regular columns');
r = knex('users').select(['name', 'email']).rowNumber('rn', 'salary', 'dept').toSQL();
console.log('SQL:', r.sql);
console.log('Bindings:', JSON.stringify(r.bindings));
console.log();

console.log('Test 14: rank() with WHERE clause');
r = knex('users').select('*').rank('r', 'salary', 'dept').where('active', true).toSQL();
console.log('SQL:', r.sql);
console.log('Bindings:', JSON.stringify(r.bindings));
console.log();

console.log('=== All analytic baseline tests done ===');
