# Step 2: Implementing Raw.toSQL() Method

## JS Implementation Deep Dive

### Overview (lines 74-128)
The `toSQL()` method is the **core** of Raw class. It:
1. Processes bindings (positional `?` or named `:key`)
2. Applies wrapping
3. Validates no undefined bindings
4. Adds metadata (UID, timeout, toNative)

---

## Part 1: Binding Replacement Logic

### Case 1: Array Bindings (Positional) - lines 76-77

**JS Code**:
```javascript
if (Array.isArray(this.bindings)) {
  obj = replaceRawArrBindings(this, this.client);
}
```

**Calls**: `rawFormatter.js replaceRawArrBindings` (lines 3-35)

#### replaceRawArrBindings Logic:

**Handles two types of placeholders**:
1. `?` - Regular binding → `client.parameter(value)`
2. `??` - Identifier binding → `columnize(value)` (wraps in quotes)
3. `\?` - Escaped question mark → literal `?`

**Code** (lines 13-28):
```javascript
const sql = raw.sql.replace(/\\?\??/g, function (match) {
  if (match === '\?') {
    return match;  // Literal ?
  }
  
  const value = values[index++];
  
  if (match === '??') {
    return columnize(value, builder, client, bindingsHolder);
  }
  return client.parameter(value, builder, bindingsHolder);
});

// Validate: must use all bindings
if (expectedBindings !== index) {
  throw new Error(`Expected ${expectedBindings} bindings, saw ${index}`);
}
```

**Examples**:
- `SELECT ? FROM ??` + `[123, 'users']` → `SELECT $1 FROM "users"` (bindings: [123])
- `SELECT \? FROM users` → `SELECT ? FROM users` (escaped)

---

### Case 2: Object Bindings (Named) - lines 78-79

**JS Code**:
```javascript
else if (this.bindings && isPlainObject(this.bindings)) {
  obj = replaceKeyBindings(this, this.client);
}
```

**Calls**: `rawFormatter.js replaceKeyBindings` (lines 37-79)

#### replaceKeyBindings Logic:

**Handles named placeholders**:
1. `:key` - Value binding → `client.parameter(value)`
2. `:key:` - Identifier binding → `columnize(value)` (wraps in quotes)
3. `\:key` - Escaped → literal `:key`

**Regex** (line 44):
```javascript
const regex = /\\?(:(\\w+):(?=::)|:(\\w+):(?!:)|:(\\w+))/g;
```

**Code** (lines 46-72):
```javascript
const sql = raw.sql.replace(regex, function(match, p1, p2, p3, p4) {
  if (match !== p1) {
    return p1;  // Escaped
  }
  
  const part = p2 || p3 || p4;  // Extract key name
  const key = match.trim();
  const isIdentifier = key[key.length - 1] === ':';  // Ends with :
  const value = values[part];  // Look up in bindings object
  
  if (value === undefined) {
    if (Object.prototype.hasOwnProperty.call(values, part)) {
      bindingsHolder.bindings.push(value);
    }
    return match;  // Keep placeholder if undefined
  }
  
  if (isIdentifier) {
    return match.replace(p1, columnize(value, builder, client, bindingsHolder));
  }
  
  return match.replace(p1, client.parameter(value, builder, bindingsHolder));
});
```

**Examples**:
- `SELECT * FROM :table: WHERE id = :id` + `{table: 'users', id: 1}` 
  → `SELECT * FROM "users" WHERE id = $1` (bindings: [1])

---

### Case 3: Other (single value) - lines 81-86

**JS Code**:
```javascript
else {
  obj = {
    method: 'raw',
    sql: this.sql,
    bindings: this.bindings === undefined ? [] : [this.bindings],
  };
}
```

**Handles**: Single value not in array → wraps in array

---

## Part 2: Apply Wrapping (lines 88-93)

```javascript
if (this._wrappedBefore) {
  obj.sql = this._wrappedBefore + obj.sql;
}
if (this._wrappedAfter) {
  obj.sql = obj.sql + this._wrappedAfter;
}
```

**Our Dart**: Already implemented in Step 1! ✅

---

## Part 3: Options Handling (line 95)

```javascript
obj.options = reduce(this._options, assign, {});
```

**TODO**: Add `_options` field and merge logic

---

## Part 4: Timeout Metadata (lines 97-102)

```javascript
if (this._timeout) {
  obj.timeout = this._timeout;
  if (this._cancelOnTimeout) {
    obj.cancelOnTimeout = this._cancelOnTimeout;
  }
}
```

**TODO**: Add timeout fields

---

## Part 5: Undefined Binding Validation (lines 104-113)

```javascript
obj.bindings = obj.bindings || [];
if (helpers.containsUndefined(obj.bindings)) {
  const undefinedBindingIndices = helpers.getUndefinedIndices(this.bindings);
  debugBindings(obj.bindings);
  throw new Error(
    `Undefined binding(s) detected for keys [${undefinedBindingIndices}] when compiling RAW query: ${obj.sql}`
  );
}
```

### containsUndefined Logic (helpers.js lines 16-42):
```javascript
function containsUndefined(mixed) {
  if (Array.isArray(mixed)) {
    for (let i = 0; i < mixed.length; i++) {
      if (containsUndefined(mixed[i])) return true;
    }
  } else if (isPlainObject(mixed)) {
    for (const key in mixed) {
      if (containsUndefined(mixed[key])) return true;
    }
  } else {
    return mixed === undefined;  // Base case
  }
  return false;
}
```

**Dart Translation**:
```dart
bool _containsUndefined(dynamic value) {
  if (value is List) {
    return value.any(_containsUndefined);
  } else if (value is Map) {
    return value.values.any(_containsUndefined);
  }
  return value == null;  // Dart: null ≈ JS undefined
}
```

---

## Part 6: Query UID (line 115)

```javascript
obj.__knexQueryUid = nanoid();
```

**TODO**: Add nanoid-like UID generator

---

## Part 7: toNative() Method (lines 117-125)

```javascript
Object.defineProperties(obj, {
  toNative: {
    value: () => ({
      sql: this.client.positionBindings(obj.sql),
      bindings: this.client.prepBindings(obj.bindings),
    }),
    enumerable: false,
  },
});
```

**Dart**: Add as method to SqlString class

---

## Dart Implementation Plan

### Step 2A: Simple toSQL() (No binding replacement yet)

```dart
SqlString toSQL() {
  // Start simple: assume bindings are already positioned
  String compiledSql = _sql;
  List<dynamic> compiledBindings = _bindings;
  
  // Apply wrapping (Step 1 fix)
  if (_wrappedBefore != null && _wrappedBefore!.isNotEmpty) {
    compiledSql = _wrappedBefore! + compiledSql;
  }
  if (_wrappedAfter != null && _wrappedAfter!.isNotEmpty) {
    compiledSql = compiledSql + _wrappedAfter!;
  }
  
  return SqlString(compiledSql, compiledBindings, method: 'raw');
}
```

### Step 2B: Add Binding Validation

```dart
void _validateBindings(List<dynamic> bindings) {
  if (_containsUndefined(bindings)) {
    final indices = _getUndefinedIndices(bindings);
    throw KnexException(
      'Undefined binding(s) detected for keys [$indices] when compiling RAW query: $_sql'
    );
  }
}

bool _containsUndefined(dynamic value) {
  if (value is List) {
    return value.any(_containsUndefined);
  } else if (value is Map) {
    return value.values.any(_containsUndefined);
  }
  return value == null;
}

List<dynamic> _getUndefinedIndices(dynamic bindings) {
  final indices = [];
  if (bindings is List) {
    for (var i = 0; i < bindings.length; i++) {
      if (_containsUndefined(bindings[i])) {
        indices.add(i);
      }
    }
  } else if (bindings is Map) {
    for (final key in bindings.keys) {
      if (_containsUndefined(bindings[key])) {
        indices.add(key);
      }
    }
  }
  return indices;
}
```

### Step 2C: Implement Binding Replacement (Complex - Next Step)

This requires:
1. Regex replacement for `?` and `??`
2. Regex replacement for `:key` and `:key:`
3. Client methods: `parameter()` and identifier wrapping
4. Proper binding collection

**Too complex for one step - will split into Step 3**

---

## Implementation Strategy

### This Step (Step 2):
1. ✅ Implement simple toSQL() that applies wrapping
2. ✅ Add binding validation
3. ✅ Add tests comparing with JS output

### Next Step (Step 3):
1. Implement positional binding replacement (`?`)
2. Test against JS

### Step 4:
1. Implement named binding replacement (`:key`)
2. Test against JS

### Step 5:
1. Add identifier bindings (`??` and `:key:`)
2. Full feature parity

---

## Test Cases for Step 2

```dart
test('toSQL returns SqlString', () {
  final raw = Raw(client).set('SELECT 1');
  final sql = raw.toSQL();
  
  expect(sql, isA<SqlString>());
  expect(sql.sql, 'SELECT 1');
  expect(sql.bindings, []);
  expect(sql.method, 'raw');
});

test('toSQL applies wrapping', () {
  final raw = Raw(client).set('SELECT 1').wrap('(', ')');
  final sql = raw.toSQL();
  
  expect(sql.sql, '(SELECT 1)');
});

test('toSQL can be called multiple times (idempotent)', () {
  final raw = Raw(client).set('SELECT 1').wrap('(', ')');
  final sql1 = raw.toSQL();
  final sql2 = raw.toSQL();
  
  expect(sql1.sql, sql2.sql);
  expect(sql1.bindings, sql2.bindings);
});

test('toSQL throws on null bindings', () {
  final raw = Raw(client).set('SELECT ?', [null]);
  
  expect(() => raw.toSQL(), throwsA(isA<KnexException>()));
});

test('toSQL preserves bindings array', () {
  final raw = Raw(client).set('SELECT ?', [123]);
  final sql = raw.toSQL();
  
  expect(sql.bindings, [123]);
});
```

---

## Expected JS Output (for comparison)

```javascript
// Test 1
knex.raw('SELECT 1').toSQL()
// Output: { method: 'raw', sql: 'SELECT 1', bindings: [], __knexQueryUid: '...' }

// Test 2
knex.raw('SELECT 1').wrap('(', ')').toSQL()
// Output: { method: 'raw', sql: '(SELECT 1)', bindings: [], __knexQueryUid: '...' }

// Test 3
knex.raw('SELECT ?', [123]).toSQL()
// Output: { method: 'raw', sql: 'SELECT $1', bindings: [123], __knexQueryUid: '...' }
```

---

## Summary

**Step 2 Scope**: Basic toSQL() with:
- ✅ Wrap application
- ✅ Binding validation  
- ✅ SqlString return type
- ✅ Idempotency

**Deferred to Step 3-5**:
- Positional binding replacement (`?`)
- Named binding replacement (`:key`)
- Identifier bindings (`??`, `:key:`)
- Timeout metadata
- Query UID

This keeps Step 2 focused and testable!
