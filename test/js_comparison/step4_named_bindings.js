// Step 4: Named Binding Replacement Test
// Tests :key and :key: placeholder replacement
// Based on knex.js lib/formatter/rawFormatter.js lines 37-79
// FIXED: Correct regex escaping per user's debugging

class MockClient {
  parameterPlaceholder(index) {
    return `$${index}`;  // PostgreSQL style
  }
  
  wrapIdentifier(value) {
    return `"${value}"`;  // PostgreSQL style
  }
}

class RawFormatter {
  static replaceNamedBindings(sql, bindings, client) {
    const result = [];
    
    // Regex from knex.js with CORRECT escaping
    // In regex literal: /\\?(:(\w+):(?=::)|:(\w+):(?!:)|:(\w+))/g
    // Matches:
    // - \:... (escaped - match !== p1)
    // - :word: followed by :: (p2 group - identifier before cast)
    // - :word: NOT followed by : (p3 group - identifier)
    // - :word (p4 group - regular binding)
    const regex = /\\?(:(\w+):(?=::)|:(\w+):(?!:)|:(\w+))/g;
    
    const replaced = sql.replace(regex, (match, p1, p2, p3, p4) => {
      // If match !== p1, backslash was consumed (escaped)
      if (match !== p1) {
        return p1;  // Return without backslash (e.g., \:key → :key)
      }
      
      // Extract the key name from whichever group matched
      const part = p2 || p3 || p4;
      const key = match.trim();
      const isIdentifier = key[key.length - 1] === ':';  // Ends with :
      const value = bindings[part];
      
      // Handle undefined value
      if (value === undefined) {
        if (Object.prototype.hasOwnProperty.call(bindings, part)) {
          result.push(value);
        }
        return match;  // Keep original placeholder
      }
      
      if (isIdentifier) {
        // :key: - identifier binding (no parameter, just wrap)
        return match.replace(p1, client.wrapIdentifier(value.toString()));
      }
      
      // :key - regular value binding
      result.push(value);
      return match.replace(p1, client.parameterPlaceholder(result.length));
    });
    
    return {
      sql: replaced,
      bindings: result
    };
  }
}

const client = new MockClient();

console.log('=== Test 1: Single :key binding ===');
const r1 = RawFormatter.replaceNamedBindings(
  'SELECT * FROM users WHERE id = :id',
  {id: 123},
  client
);
console.log(JSON.stringify(r1, null, 2));

console.log('\n=== Test 2: Multiple :key bindings ===');
const r2 = RawFormatter.replaceNamedBindings(
  'SELECT * FROM users WHERE id = :id AND status = :status',
  {id: 123, status: 'active'},
  client
);
console.log(JSON.stringify(r2, null, 2));

console.log('\n=== Test 3: :key: identifier binding ===');
const r3 = RawFormatter.replaceNamedBindings(
  'SELECT * FROM :table:',
  {table: 'users'},
  client
);
console.log(JSON.stringify(r3, null, 2));

console.log('\n=== Test 4: Mixed :key and :key: ===');
const r4 = RawFormatter.replaceNamedBindings(
  'SELECT :column: FROM :table: WHERE id = :id',
  {column: 'name', table: 'users', id: 123},
  client
);
console.log(JSON.stringify(r4, null, 2));

console.log('\n=== Test 5: Escaped \\:key (becomes literal :key) ===');
const r5 = RawFormatter.replaceNamedBindings(
  'SELECT * FROM users WHERE email = \\:email',
  {},
  client
);
console.log(JSON.stringify(r5, null, 2));

console.log('\n=== Test 6: :key: before ::cast (user example) ===');
const r6 = RawFormatter.replaceNamedBindings(
  'SELECT :ns::jsonb FROM users',
  {ns: 'data'},
  client
);
console.log(JSON.stringify(r6, null, 2));

console.log('\n=== Test 7: Complex mixed ===');
const r7 = RawFormatter.replaceNamedBindings(
  'INSERT INTO :table: (:col1:, :col2:) VALUES (:val1, :val2)',
  {
    table: 'users',
    col1: 'name',
    col2: 'email',
    val1: 'John',
    val2: 'john@example.com'
  },
  client
);
console.log(JSON.stringify(r7, null, 2));

console.log('\n=== Test 8: Undefined value (should keep placeholder) ===');
const r8 = RawFormatter.replaceNamedBindings(
  'SELECT * FROM users WHERE id = :id',
  {name: 'test'},  // id is missing
  client
);
console.log(JSON.stringify(r8, null, 2));
