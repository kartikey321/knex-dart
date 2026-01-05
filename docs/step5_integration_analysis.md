# Step 5: Raw.toSQL() Integration Analysis

## JS Implementation (lib/raw.js lines 74-128)

### Flow:

```javascript
toSQL(method, tz) {
  let obj;
  
  // Step 1: Handle bindings based on type (lines 76-86)
  if (Array.isArray(this.bindings)) {
    obj = replaceRawArrBindings(this, this.client);  // Positional
  } else if (this.bindings && isPlainObject(this.bindings)) {
    obj = replaceKeyBindings(this, this.client);      // Named
  } else {
    obj = {
      method: 'raw',
      sql: this.sql,
      bindings: this.bindings === undefined ? [] : [this.bindings],
    };
  }

  // Step 2: Apply wrapping (lines 88-93)
  if (this._wrappedBefore) {
    obj.sql = this._wrappedBefore + obj.sql;
  }
  if (this._wrappedAfter) {
    obj.sql = obj.sql + this._wrappedAfter;
  }

  // Step 3: Merge options (line 95)
  obj.options = reduce(this._options, assign, {});

  // Step 4: Add timeout metadata (lines 97-102)
  if (this._timeout) {
    obj.timeout = this._timeout;
    if (this._cancelOnTimeout) {
      obj.cancelOnTimeout = this._cancelOnTimeout;
    }
  }

  // Step 5: Validate no undefined bindings (lines 104-113)
  obj.bindings = obj.bindings || [];
  if (helpers.containsUndefined(obj.bindings)) {
    const undefinedBindingIndices = helpers.getUndefinedIndices(this.bindings);
    debugBindings(obj.bindings);
    throw new Error(
      `Undefined binding(s) detected for keys [${undefinedBindingIndices}] when compiling RAW query: ${obj.sql}`
    );
  }

  // Step 6: Add query UID (line 115)
  obj.__knexQueryUid = nanoid();

  // Step 7: Add toNative() helper (lines 117-125)
  Object.defineProperties(obj, {
    toNative: {
      value: () => ({
        sql: this.client.positionBindings(obj.sql),
        bindings: this.client.prepBindings(obj.bindings),
      }),
      enumerable: false,
    },
  });

  return obj;
}
```

## Current Dart Implementation

Missing:
1. ❌ Formatter integration (steps 1-2)
2. ❌ Query UID
3. ✅ Wrapping (already done)
4. ✅ Binding validation (already done)

## Implementation Plan

### Update Raw.toSQL():

```dart
SqlString toSQL() {
  String compiledSql = _sql;
  List<dynamic> compiledBindings;
  
  // Step 1: Format bindings based on type (JS lines 76-86)
  if (_bindings is List && _bindings.isNotEmpty) {
    final formatted = RawFormatter.replacePositionalBindings(
      _sql,
      _bindings as List<dynamic>,
      _client,
    );
    compiledSql = formatted.sql;
    compiledBindings = formatted.bindings;
  } else if (_bindings is Map && _bindings.isNotEmpty) {
    final formatted = RawFormatter.replaceNamedBindings(
      _sql,
      _bindings as Map<String, dynamic>,
      _client,
    );
    compiledSql = formatted.sql;
    compiledBindings = formatted.bindings;
  } else {
    // Single value or empty
    compiledBindings = _bindings is List ? _bindings : [];
  }
  
  // Step 2: Validate bindings (already implemented)
  _validateBindings(compiledBindings);
  
  // Step 3: Apply wrapping (already implemented - JS lines 88-93)
  if (_wrappedBefore != null && _wrappedBefore!.isNotEmpty) {
    compiledSql = _wrappedBefore! + compiledSql;
  }
  if (_wrappedAfter != null && _wrappedAfter!.isNotEmpty) {
    compiledSql = compiledSql + _wrappedAfter!;
  }
  
  // Step 4: Create SqlString with UID (JS line 115)
  return SqlString(
    compiledSql,
    compiledBindings,
    method: 'raw',
    uid: _generateUid(),  // TODO: Add UID generation
  );
}
```

### Add UID generation:

```dart
String _generateUid() {
  // Simple UID generation (can use uuid package later)
  return DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
         Random().nextInt(1000000).toRadixString(36);
}
```

### Update SqlString to include UID:

```dart
class SqlString {
  final String sql;
  final List<dynamic> bindings;
  final String? method;
  final String? uid;  // ADD THIS
  
  SqlString(this.sql, this.bindings, {this.method, this.uid});
}
```

## Test Cases

Need to test full integration:
1. Positional bindings with wrapping
2. Named bindings with wrapping
3. UID generation
4. JS output comparison
