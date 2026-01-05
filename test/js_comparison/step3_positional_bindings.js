// Step 3: Positional Binding Replacement Test
// Tests ? and ?? placeholder replacement

class MockClient {
  parameterPlaceholder(index) {
    return `$${index}`;  // PostgreSQL style
  }
  
  wrapIdentifier(value) {
    return `"${value}"`;  // PostgreSQL style
  }
}

class RawFormatter {
  static replacePositionalBindings(sql, bindings, client) {
    const result = [];
    let index = 0;
    
    // Regex from knex.js: /\\?\??/g (escaped ?, or one-or-two ?)
    // This means: either \? (escaped) or ? or ??
    const replaced = sql.replace(/\\\?|\?\??/g, (match) => {
      if (match === '\\?') {
        return '?';  // Escaped - literal ?
      }
      
      const value = bindings[index++];
      
      if (match === '??') {
        // Identifier - wrap with quotes, don't add to bindings
        return client.wrapIdentifier(value.toString());
      }
      
      // Regular binding - add to result bindings
      result.push(value);
      return client.parameterPlaceholder(result.length);
    });
    
    if (index !== bindings.length) {
      throw new Error(`Expected ${bindings.length} bindings, saw ${index}`);
    }
    
    return {
      sql: replaced,
      bindings: result
    };
  }
}

const client = new MockClient();

console.log('=== Test 1: Single ? binding ===');
const r1 = RawFormatter.replacePositionalBindings(
  'SELECT * FROM users WHERE id = ?',
  [123],
  client
);
console.log(JSON.stringify(r1, null, 2));

console.log('\n=== Test 2: Multiple ? bindings ===');
const r2 = RawFormatter.replacePositionalBindings(
  'SELECT * FROM users WHERE id = ? AND status = ?',
  [123, 'active'],
  client
);
console.log(JSON.stringify(r2, null, 2));

console.log('\n=== Test 3: ?? identifier binding ===');
const r3 = RawFormatter.replacePositionalBindings(
  'SELECT * FROM ??',
  ['users'],
  client
);
console.log(JSON.stringify(r3, null, 2));

console.log('\n=== Test 4: Mixed ? and ?? ===');
const r4 = RawFormatter.replacePositionalBindings(
  'SELECT ?? FROM ?? WHERE id = ?',
  ['name', 'users', 123],
  client
);
console.log(JSON.stringify(r4, null, 2));

console.log('\n=== Test 5: Escaped \\? ===');
const r5 = RawFormatter.replacePositionalBindings(
  'SELECT * FROM users WHERE email LIKE \\?',
  [],
  client
);
console.log(JSON.stringify(r5, null, 2));

console.log('\n=== Test 6: Multiple types ===');
const r6 = RawFormatter.replacePositionalBindings(
  'INSERT INTO ?? (??, ??) VALUES (?, ?)',
  ['users', 'name', 'email', 'John', 'john@example.com'],
  client
);
console.log(JSON.stringify(r6, null, 2));

console.log('\n=== Test 7: Wrong binding count (should error) ===');
try {
  RawFormatter.replacePositionalBindings(
    'SELECT ? FROM users',
    [1, 2],  // Too many
    client
  );
  console.log('ERROR: Should have thrown!');
} catch (e) {
  console.log('✓ Caught error:', e.message);
}
