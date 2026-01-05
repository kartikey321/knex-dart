// Simple test without Knex dependencies
// Just raw JavaScript to understand the expected behavior

class MockRaw {
  constructor() {
    this.sql = '';
    this.bindings = [];
    this._wrappedBefore = undefined;
    this._wrappedAfter = undefined;
  }

  set(sql, bindings) {
    this.sql = sql;
    this.bindings = bindings === undefined ? [] :
                    Array.isArray(bindings) ? bindings :
                    [bindings];
    return this;
  }

  wrap(before, after) {
    this._wrappedBefore = before;
    this._wrappedAfter = after;
    return this;
  }

  toSQL() {
    // Simple version without binding replacement
    let obj = {
      method: 'raw',
      sql: this.sql,
      bindings: this.bindings
    };

    // Apply wrapping
    if (this._wrappedBefore) {
      obj.sql = this._wrappedBefore + obj.sql;
    }
    if (this._wrappedAfter) {
      obj.sql = obj.sql + this._wrappedAfter;
    }

    return obj;
  }
}

// Tests
console.log('=== Test 1: Simple SQL ===');
const r1 = new MockRaw().set('SELECT 1');
console.log(JSON.stringify(r1.toSQL(), null, 2));

console.log('\n=== Test 2: With bindings ===');
const r2 = new MockRaw().set('SELECT * FROM users WHERE id = ?', [123]);
console.log(JSON.stringify(r2.toSQL(), null, 2));

console.log('\n=== Test 3: With wrap ===');
const r3 = new MockRaw().set('SELECT 1').wrap('(', ')');
console.log(JSON.stringify(r3.toSQL(), null, 2));

console.log('\n=== Test 4: Multiple calls (idempotent) ===');
const r4 = new MockRaw().set('SELECT 1').wrap('(', ')');
const sql1 = r4.toSQL();
const sql2 = r4.toSQL();
console.log('First call:', JSON.stringify(sql1, null, 2));
console.log('Second call:', JSON.stringify(sql2, null, 2));
console.log('Are equal?', JSON.stringify(sql1) === JSON.stringify(sql2));

console.log('\n=== Test 5: Empty wrap ===');
const r5 = new MockRaw().set('SELECT 1').wrap('', '');
console.log(JSON.stringify(r5.toSQL(), null, 2));

console.log('\n=== Test 6: Null in bindings ===');
const r6 = new MockRaw().set('SELECT ?', [null]);
console.log(JSON.stringify(r6.toSQL(), null, 2));
console.log('Contains null:', r6.toSQL().bindings.includes(null));
