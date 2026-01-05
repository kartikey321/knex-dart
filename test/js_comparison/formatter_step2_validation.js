// Formatter Step 2: Validation Methods Test
// Tests operator() and direction()
// Based on wrappingFormatter.js lines 128-136 and 236-240

// Mock Client
class MockClient {
  wrapIdentifier(id) {
    if (id === '*') return id;
    return `"${id}"`;
  }
}

// Mock Raw
class Raw {
  constructor(sql) {
    this.sql = sql;
    this.isRawInstance = true;
  }
}

// Operators map from wrappingFormatter.js lines 9-64
const operators = {
  '=': '=',
  '<': '<',
  '>': '>',
  '<=': '<=',
  '<=>': '<=>',
  '>=': '>=',
  '<>': '<>',
  '!=': '!=',
  'like': 'like',
  'not like': 'not like',
  'between': 'between',
  'not between': 'not between',
  'ilike': 'ilike',
  'not ilike': 'not ilike',
  '&': '&',
  '|': '|',
  '^': '^',
  '<<': '<<',
  '>>': '>>',
  '~': '~',
  '~*': '~*',
  '!~': '!~',
  '!~*': '!~*',
  '@@': '@@',
  '@>': '@>',
  '<@': '<@',
  '||': '||',
  '&&': '&&',
  '?': '\\?',      // Escaped
  '?|': '\\?|',    // Escaped
  '?&': '\\?&',    // Escaped
};

// Valid order by directions
const orderBys = ['asc', 'desc'];

// operator() - lines 128-136
function operator(value, builder, client, bindingsHolder) {
  // Check if Raw first
  if (value && value.isRawInstance) {
    return value.sql;
  }
  
  const op = operators[(value || '').toLowerCase()];
  if (!op) {
    throw new TypeError(`The operator "${value}" is not permitted`);
  }
  return op;
}

// direction() - lines 236-240
function direction(value, builder, client, bindingsHolder) {
  // Check if Raw first
  if (value && value.isRawInstance) {
    return value.sql;
  }
  
  return orderBys.indexOf((value || '').toLowerCase()) !== -1 ? value : 'asc';
}

const client = new MockClient();
const builder = {};
const bindingsHolder = { bindings: [] };

console.log('=== Test 1: operator - Equals ===');
console.log(operator('=', builder, client, bindingsHolder));

console.log('\n=== Test 2: operator - Not equals ===');
console.log(operator('!=', builder, client, bindingsHolder));

console.log('\n=== Test 3: operator - LIKE (case insensitive) ===');
console.log(operator('LIKE', builder, client, bindingsHolder));

console.log('\n=== Test 4: operator - Between ===');
console.log(operator('between', builder, client, bindingsHolder));

console.log('\n=== Test 5: operator - Greater than ===');
console.log(operator('>', builder, client, bindingsHolder));

console.log('\n=== Test 6: operator - PostgreSQL ? (escaped) ===');
console.log(operator('?', builder, client, bindingsHolder));

console.log('\n=== Test 7: operator - PostgreSQL @> (contains) ===');
console.log(operator('@>', builder, client, bindingsHolder));

console.log('\n=== Test 8: operator - Raw value ===');
const rawOp = new Raw('CUSTOM_OP');
console.log(operator(rawOp, builder, client, bindingsHolder));

console.log('\n=== Test 9: operator - Invalid (should throw) ===');
try {
  operator('INVALID_OP', builder, client, bindingsHolder);
  console.log('ERROR: Should have thrown!');
} catch (e) {
  console.log(`Threw: ${e.message}`);
}

console.log('\n=== Test 10: direction - ASC ===');
console.log(direction('ASC', builder, client, bindingsHolder));

console.log('\n=== Test 11: direction - DESC ===');
console.log(direction('DESC', builder, client, bindingsHolder));

console.log('\n=== Test 12: direction - asc (lowercase) ===');
console.log(direction('asc', builder, client, bindingsHolder));

console.log('\n=== Test 13: direction - Invalid (defaults to asc) ===');
console.log(direction('INVALID', builder, client, bindingsHolder));

console.log('\n=== Test 14: direction - Empty (defaults to asc) ===');
console.log(direction('', builder, client, bindingsHolder));

console.log('\n=== Test 15: direction - Raw value ===');
const rawDir = new Raw('CUSTOM_DIR');
console.log(direction(rawDir, builder, client, bindingsHolder));
