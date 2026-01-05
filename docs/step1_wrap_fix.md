# Step 1: Fixing Raw.wrap() Method

## JavaScript Implementation Analysis

### Constructor (lines 33-34)
```javascript
// Todo: Deprecate
this._wrappedBefore = undefined;
this._wrappedAfter = undefined;
```
**Behavior**: Initializes two instance variables to store wrapping strings

---

### wrap() Method (lines 62-66)
```javascript
// Wraps the current sql with `before` and `after`.
wrap(before, after) {
  this._wrappedBefore = before;  // ← STORES the value
  this._wrappedAfter = after;    // ← STORES the value
  return this;                   // ← Returns this for chaining
}
```

**Key Points**:
- ✅ **Stores** values, doesn't modify `this.sql`
- ✅ Returns `this` for method chaining
- ✅ Values can be `undefined` or strings

---

### Usage in toSQL() (lines 88-93)
```javascript
// After creating obj with sql and bindings...
if (this._wrappedBefore) {
  obj.sql = this._wrappedBefore + obj.sql;  // ← Applied HERE, during compilation
}
if (this._wrappedAfter) {
  obj.sql = obj.sql + this._wrappedAfter;
}
```

**Key Points**:
- ✅ Applied **during SQL compilation**, not during `wrap()` call
- ✅ Allows re-compiling with same Raw object
- ✅ Only applies if values are truthy (not `undefined` or empty)

---

## Current Dart Implementation (INCORRECT)

### Constructor
```dart
Raw(this._client);  // ← No _wrappedBefore or _wrappedAfter fields
```

### wrap() Method (lines 60-62)
```dart
Raw wrap(String before, String after) {
  _sql = '$before$_sql$after';  // ❌ WRONG: Modifies SQL immediately
  return this;
}
```

**Problems**:
1. ❌ Modifies `_sql` **immediately** instead of storing values
2. ❌ Cannot re-compile with different wrapping
3. ❌ No instance variables to store `_wrappedBefore`/`_wrappedAfter`
4. ❌ If `toSQL()` is called multiple times, wrapping is applied multiple times
   - First call: `(SELECT 1)`
   - Second call: `((SELECT 1))` ← WRONG!

---

## Correct Dart Implementation

### Step 1: Add Instance Variables

```dart
class Raw {
  final Client _client;
  String _sql = '';
  List<dynamic> _bindings = [];
  
  // ✅ ADD THESE:
  String? _wrappedBefore;
  String? _wrappedAfter;
  
  Raw(this._client);
```

### Step 2: Fix wrap() Method

```dart
/// Wraps the SQL with `before` and `after` strings
///
/// Applied during toSQL() compilation, not immediately.
/// Allows re-compiling with same Raw object.
///
/// Example:
/// ```dart
/// raw('SELECT 1').wrap('(', ')')  // Stored, not applied yet
///   .toSQL()  // Returns: { sql: '(SELECT 1)', bindings: [] }
/// ```
Raw wrap(String before, String after) {
  _wrappedBefore = before;  // ✅ Store for later
  _wrappedAfter = after;    // ✅ Store for later
  return this;              // ✅ Return this for chaining
}
```

### Step 3: Apply in toSQL() Method

```dart
SqlString toSQL() {
  // ... create sql and bindings ...
  
  // ✅ Apply wrapping during compilation:
  if (_wrappedBefore != null && _wrappedBefore!.isNotEmpty) {
    sql = _wrappedBefore! + sql;
  }
  if (_wrappedAfter != null && _wrappedAfter!.isNotEmpty) {
    sql = sql + _wrappedAfter!;
  }
  
  return SqlString(sql, bindings, method: 'raw');
}
```

---

## Behavior Comparison

### Scenario: Multiple toSQL() Calls

**JavaScript**:
```javascript
const raw = client.raw('SELECT 1').wrap('(', ')');
const sql1 = raw.toSQL();  // { sql: '(SELECT 1)' }
const sql2 = raw.toSQL();  // { sql: '(SELECT 1)' } ← Same! ✅
```

**Current Dart (WRONG)**:
```dart
final raw = client.raw('SELECT 1').wrap('(', ')');
final sql1 = raw.toSQL();  // { sql: '(SELECT 1)' }
final sql2 = raw.toSQL();  // { sql: '((SELECT 1))' } ← WRONG! ❌
```

**Fixed Dart**:
```dart
final raw = client.raw('SELECT 1').wrap('(', ')');
final sql1 = raw.toSQL();  // { sql: '(SELECT 1)' }
final sql2 = raw.toSQL();  // { sql: '(SELECT 1)' } ← Correct! ✅
```

---

## Edge Cases to Handle

### 1. Empty Strings
```javascript
raw.wrap('', '')  // Should work, but not modify SQL
```

**Solution**: Check for `isNotEmpty` before applying

### 2. Null Values (Dart-specific)
```dart
raw.wrap(null, null)  // Should work in Dart
```

**Solution**: Check for `!= null` before applying

### 3. Chaining
```javascript
raw.wrap('(', ')').wrap('[', ']')  // Last call wins
```

**JS Behavior**: Overwrites previous values  
**Dart Behavior**: Should match

---

## Test Cases

```dart
test('wrap stores values without modifying SQL', () {
  final raw = client.raw('SELECT 1');
  expect(raw.sql, 'SELECT 1');
  
  raw.wrap('(', ')');
  expect(raw.sql, 'SELECT 1');  // ✅ Unchanged
});

test('wrap is applied during toSQL', () {
  final raw = client.raw('SELECT 1').wrap('(', ')');
  final sql = raw.toSQL();
  expect(sql.sql, '(SELECT 1)');
});

test('multiple toSQL calls produce same result', () {
  final raw = client.raw('SELECT 1').wrap('(', ')');
  final sql1 = raw.toSQL();
  final sql2 = raw.toSQL();
  expect(sql1.sql, sql2.sql);  // ✅ Same
});

test('empty wrap does not modify SQL', () {
  final raw = client.raw('SELECT 1').wrap('', '');
  final sql = raw.toSQL();
  expect(sql.sql, 'SELECT 1');
});

test('wrap can be overridden', () {
  final raw = client.raw('SELECT 1')
    .wrap('(', ')')
    .wrap('[', ']');  // ← Overwrites
  final sql = raw.toSQL();
  expect(sql.sql, '[SELECT 1]');
});
```

---

## Implementation Checklist

- [ ] Add `_wrappedBefore` field to Raw class
- [ ] Add `_wrappedAfter` field to Raw class
- [ ] Fix `wrap()` method to store instead of modify
- [ ] Implement toSQL() method (separate step)
- [ ] Apply wrapping in toSQL()
- [ ] Add tests for wrap behavior
- [ ] Verify all tests pass

---

**Next Step**: After fixing wrap(), we'll implement the full toSQL() method.
