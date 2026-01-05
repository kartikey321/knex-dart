// Formatter Step 1: Core Wrapping Methods Test
// Tests wrapString, wrap, columnize
// Captures all edge cases for Dart implementation

// Mock Client (PostgreSQL-style)
class MockClient {
  wrapIdentifier(id) {
    // Skip wrapping for *, or if already quoted
    if (id === '*') return id;
    if (id.startsWith('"') && id.endsWith('"')) return id;
    return `"${id}"`;
  }
  
  alias(value, alias) {
    return `${value} AS ${alias}`;
  }
}

// Mock Raw
class Raw {
  constructor(sql, bindings = []) {
    this.sql = sql;
    this.bindings = bindings;
    this.isRawInstance = true;
  }
  
  toSQL() {
    return { sql: this.sql, bindings: this.bindings };
  }
}

// Simplified wrapAsIdentifier from formatterUtils
function wrapAsIdentifier(value, builder, client) {
  if (value === '*') return value;
  return client.wrapIdentifier(value);
}

// Core wrapping functions from wrappingFormatter.js

// wrapString - lines 139-161
function wrapString(value, builder, client) {
  // Check for "AS" alias
  const asIndex = value.toLowerCase().indexOf(' as ');
  if (asIndex !== -1) {
    const first = value.slice(0, asIndex);
    const second = value.slice(asIndex + 4);
    return client.alias(
      wrapString(first, builder, client),
      wrapAsIdentifier(second, builder, client)
    );
  }
  
  // Split by dots
  const wrapped = [];
  const segments = value.split('.');
  for (let i = 0; i < segments.length; i++) {
    const segment = segments[i];
    if (i === 0 && segments.length > 1) {
      wrapped.push(wrapString((segment || '').trim(), builder, client));
    } else {
      wrapped.push(wrapAsIdentifier(segment, builder, client));
    }
  }
  return wrapped.join('.');
}

// wrap - lines 80-98 (simplified - no functions/objects for Step 1)
function wrap(value, isParameter, builder, client, bindingHolder) {
  // Check if Raw
  if (value && value.isRawInstance) {
    const sql = value.toSQL();
    if (sql.bindings) {
      bindingHolder.bindings.push(...sql.bindings);
    }
    return sql.sql;
  }
  
  // Handle by type
  switch (typeof value) {
    case 'number':
      return value;
    default:
      return wrapString(value + '', builder, client);
  }
}

// columnize - lines 67-76
function columnize(target, builder, client, bindingHolder) {
  const columns = Array.isArray(target) ? target : [target];
  let str = '';
  for (let i = 0; i < columns.length; i++) {
    if (i > 0) str += ', ';
    str += wrap(columns[i], undefined, builder, client, bindingHolder);
  }
  return str;
}

// Test suite
const client = new MockClient();
const builder = {};  // Minimal builder
const bindingHolder = { bindings: [] };

console.log('=== Test 1: wrapString - Simple identifier ===');
console.log(wrapString('users', builder, client));

console.log('\n=== Test 2: wrapString - Dotted (schema.table) ===');
console.log(wrapString('public.users', builder, client));

console.log('\n=== Test 3: wrapString - Three parts (schema.table.column) ===');
console.log(wrapString('public.users.id', builder, client));

console.log('\n=== Test 4: wrapString - With AS alias ===');
console.log(wrapString('name AS user_name', builder, client));

console.log('\n=== Test 5: wrapString - Dotted with AS ===');
console.log(wrapString('users.email AS contact', builder, client));

console.log('\n=== Test 6: wrapString - Wildcard ===');
console.log(wrapString('*', builder, client));

console.log('\n=== Test 7: wrap - String ===');
bindingHolder.bindings = [];
console.log(wrap('users', false, builder, client, bindingHolder));
console.log('Bindings:', bindingHolder.bindings);

console.log('\n=== Test 8: wrap - Number ===');
bindingHolder.bindings = [];
console.log(wrap(123, false, builder, client, bindingHolder));
console.log('Bindings:', bindingHolder.bindings);

console.log('\n=== Test 9: wrap - Raw ===');
bindingHolder.bindings = [];
const raw = new Raw('NOW()', []);
console.log(wrap(raw, false, builder, client, bindingHolder));
console.log('Bindings:', bindingHolder.bindings);

console.log('\n=== Test 10: wrap - Raw with bindings ===');
bindingHolder.bindings = [];
const rawWithBindings = new Raw('SELECT ?', [123]);
console.log(wrap(rawWithBindings, false, builder, client, bindingHolder));
console.log('Bindings:', bindingHolder.bindings);

console.log('\n=== Test 11: columnize - Single column ===');
bindingHolder.bindings = [];
console.log(columnize('id', builder, client, bindingHolder));

console.log('\n=== Test 12: columnize - Multiple columns ===');
bindingHolder.bindings = [];
console.log(columnize(['id', 'name', 'email'], builder, client, bindingHolder));

console.log('\n=== Test 13: columnize - Dotted columns ===');
bindingHolder.bindings = [];
console.log(columnize(['users.id', 'users.name'], builder, client, bindingHolder));

console.log('\n=== Test 14: columnize - With wildcard ===');
bindingHolder.bindings = [];
console.log(columnize('*', builder, client, bindingHolder));

console.log('\n=== Test 15: columnize - Mixed: strings and Raw ===');
bindingHolder.bindings = [];
console.log(columnize(['id', new Raw('COUNT(*)')], builder, client, bindingHolder));

console.log('\n=== Test 16: columnize - With AS aliases ===');
bindingHolder.bindings = [];
console.log(columnize(['id', 'name AS user_name'], builder, client, bindingHolder));
