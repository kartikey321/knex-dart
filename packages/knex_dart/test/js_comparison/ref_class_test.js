// Ref Class Comparison Test
// Tests that Ref extends Raw and behaves identically to JS

const path = require('path');

// Mock Client with formatter
class MockFormatter {
  columnize(value) {
    // Split by dots and wrap each part
    return value.split('.').map(part => `"${part}"`).join('.');
  }
  
  wrap(value) {
    return `"${value}"`;
  }
}

class MockClient {
  formatter(builder) {
    return new MockFormatter();
  }
  
  wrapIdentifier(id) {
    return `"${id}"`;
  }
  
  parameterPlaceholder(index) {
    return `$${index}`;
  }
}

// Simulate Raw class (simplified)
class Raw {
  constructor(client) {
    this.client = client;
    this.sql = '';
    this.bindings = [];
    this._wrappedBefore = null;
    this._wrappedAfter = null;
  }
  
  set(sql, bindings) {
    this.sql = sql;
    this.bindings = bindings || [];
    return this;
  }
  
  wrap(before, after) {
    this._wrappedBefore = before;
    this._wrappedAfter = after;
    return this;
  }
  
  toSQL() {
    let result = this.sql;
    
    if (this._wrappedBefore) {
      result = this._wrappedBefore + result;
    }
    if (this._wrappedAfter) {
      result = result + this._wrappedAfter;
    }
    
    return {
      sql: result,
      bindings: this.bindings,
      method: 'raw',
      __knexQueryUid: 'test-uid-123'
    };
  }
}

// Actual Ref class from Knex (simplified to match our implementation)
class Ref extends Raw {
  constructor(client, ref) {
    super(client);
    this.ref = ref;
    this._schema = null;
    this._alias = null;
  }
  
  withSchema(schema) {
    this._schema = schema;
    return this;
  }
  
  as(alias) {
    this._alias = alias;
    return this;
  }
  
  toSQL() {
    // Build base ref with optional schema prefix
    const base = this._schema ? `${this._schema}.${this.ref}` : this.ref;
    
    // Wrap each part of the reference
    const parts = base.split('.');
    const wrapped = parts.map(p => this.client.wrapIdentifier(p)).join('.');
    
    // Apply alias if present
    const sql = this._alias 
      ? `${wrapped} AS ${this.client.wrapIdentifier(this._alias)}`
      : wrapped;
    
    // Store on Raw and delegate to Raw.toSQL
    this.set(sql, []);
    return super.toSQL();
  }
}

const client = new MockClient();

console.log('=== Test 1: Simple ref ===');
const r1 = new Ref(client, 'user_id');
console.log(JSON.stringify(r1.toSQL(), null, 2));

console.log('\n=== Test 2: Ref with alias ===');
const r2 = new Ref(client, 'user_id').as('uid');
console.log(JSON.stringify(r2.toSQL(), null, 2));

console.log('\n=== Test 3: Ref with schema ===');
const r3 = new Ref(client, 'balance').withSchema('accounts');
console.log(JSON.stringify(r3.toSQL(), null, 2));

console.log('\n=== Test 4: Ref with schema and alias ===');
const r4 = new Ref(client, 'balance')
  .withSchema('accounts')
  .as('account_balance');
console.log(JSON.stringify(r4.toSQL(), null, 2));

console.log('\n=== Test 5: Dotted ref (table.column) ===');
const r5 = new Ref(client, 'users.email');
console.log(JSON.stringify(r5.toSQL(), null, 2));

console.log('\n=== Test 6: Dotted ref with alias ===');
const r6 = new Ref(client, 'users.email').as('user_email');
console.log(JSON.stringify(r6.toSQL(), null, 2));

console.log('\n=== Test 7: Chaining returns this ===');
const r7 = new Ref(client, 'id');
const chained = r7.withSchema('public').as('user_id');
console.log('Same instance:', r7 === chained);
console.log(JSON.stringify(r7.toSQL(), null, 2));

console.log('\n=== Test 8: Ref can use .wrap() (inherited from Raw) ===');
const r8 = new Ref(client, 'count').wrap('(', ')');
console.log(JSON.stringify(r8.toSQL(), null, 2));

console.log('\n=== Test 9: Multiple schema parts ===');
const r9 = new Ref(client, 'column').withSchema('schema.table');
console.log(JSON.stringify(r9.toSQL(), null, 2));
