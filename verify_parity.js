const fs = require('fs');

// Read JS methods from querybuilder.js prototype and related files
const jsCode = fs.readFileSync('/Users/kartik/StudioProjects/knex/knex-js/lib/query/querybuilder.js', 'utf8');
const jsMethods = new Set();
// Look for methods defined on the class or prototype
const jsMethodRegex = /^\s+([a-zA-Z0-9_]+)\s*\(/gm;
let match;
while ((match = jsMethodRegex.exec(jsCode)) !== null) {
  if (!match[1].startsWith('_') && !['constructor', 'client', 'and'].includes(match[1])) {
    jsMethods.add(match[1]);
  }
}

// Read Dart methods
const dartCode = fs.readFileSync('/Users/kartik/StudioProjects/knex/knex-dart/lib/src/query/query_builder.dart', 'utf8');
const dartMethods = new Set();
// Match Dart method signatures
const dartMethodRegex = /^\s+(?:QueryBuilder|String|void|dynamic|Client|int|bool)\s+([a-zA-Z0-9_]+)\s*\(/gm;
while ((match = dartMethodRegex.exec(dartCode)) !== null) {
  if (!match[1].startsWith('_')) {
    dartMethods.add(match[1]);
  }
}

// Ignore list (JS specific promise handling, stream handling, transaction handling which is at client level in dart)
const ignore = new Set([
  'client', 'and', 'clone', 'toString', 'toQuery', 'then', 'catch', 'finally',
  'stream', 'pipe', 'asCallback', 'connection', 'debug', 'transacting',
  'forUpdate', 'forShare', 'forNoKeyUpdate', 'forKeyShare', 'skipLocked',
  'noWait', 'modify', 'off', 'on', 'once', 'emit', 'listeners', 'removeAllListeners', 'timeout', 'clear', 'clearSelect', 'clearWhere', 'clearGroup', 'clearOrder', 'clearHaving', 'clearCounters', 'pluck', 'first', 'options'
]);

const missing = [];
const implemented = [];

for (const method of jsMethods) {
  if (!ignore.has(method)) {
    if (dartMethods.has(method)) {
      implemented.push(method);
    } else {
      missing.push(method);
    }
  }
}

missing.sort();
implemented.sort();

console.log('=== API Parity Audit ===\n');
console.log(`Total JS Methods Analyzed: ${missing.length + implemented.length}`);
console.log(`Implemented in Dart: ${implemented.length} (${Math.round(implemented.length / (missing.length + implemented.length) * 100)}%)`);
console.log(`Missing in Dart: ${missing.length}\n`);

console.log('--- Missing Methods ---');
for (const m of missing) {
  console.log(`- ${m}()`);
}
