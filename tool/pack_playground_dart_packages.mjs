#!/usr/bin/env node

// Packs the Dart package sources needed by the browser playground analyzer into
// dart-live's small DPKG format. This intentionally reads the local workspace
// package_config so PRs validate against the branch's current source.

import { existsSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const requiredPackages = [
  'knex_dart',
  'knex_dart_capabilities',
  'logging',
  'meta',
  'collection',
  'universal_io',
  'typed_data',
];

const [packageConfigPathArg, outPathArg] = process.argv.slice(2);
if (!packageConfigPathArg || !outPathArg) {
  console.error('usage: node tool/pack_playground_dart_packages.mjs <package_config.json> <out.bin>');
  process.exit(2);
}

const packageConfigPath = resolve(packageConfigPathArg);
const packageConfigUrl = pathToFileURL(packageConfigPath);
const outPath = resolve(outPathArg);
const config = JSON.parse(readFileSync(packageConfigPath, 'utf8'));
const packagesByName = new Map(config.packages.map((pkg) => [pkg.name, pkg]));

function packageRoot(pkg) {
  const rootUrl = new URL(pkg.rootUri, packageConfigUrl);
  if (rootUrl.protocol !== 'file:') {
    throw new Error(`Unsupported package root URI for ${pkg.name}: ${pkg.rootUri}`);
  }
  return fileURLToPath(rootUrl);
}

function includePath(relativePath) {
  return relativePath === 'pubspec.yaml' ||
    relativePath === 'analysis_options.yaml' ||
    relativePath === 'README.md' ||
    relativePath === 'LICENSE' ||
    relativePath.startsWith(`lib${sep}`);
}

function collectPackageFiles(root) {
  const files = [];
  const walk = (dir) => {
    for (const entry of readdirSync(dir).sort()) {
      const absolute = join(dir, entry);
      const st = statSync(absolute);
      if (st.isDirectory()) {
        walk(absolute);
      } else if (st.isFile()) {
        const rel = relative(root, absolute);
        if (includePath(rel)) {
          files.push({
            path: rel.split(sep).join('/'),
            content: readFileSync(absolute),
          });
        }
      }
    }
  };

  for (const entry of ['pubspec.yaml', 'analysis_options.yaml', 'README.md', 'LICENSE', 'lib']) {
    const absolute = join(root, entry);
    if (!existsSync(absolute)) continue;
    const st = statSync(absolute);
    if (st.isDirectory()) {
      walk(absolute);
    } else if (st.isFile()) {
      files.push({ path: entry, content: readFileSync(absolute) });
    }
  }

  files.sort((a, b) => a.path.localeCompare(b.path));
  return files;
}

const encoder = new TextEncoder();
const chunks = [];

function appendU32LE(n) {
  chunks.push(Buffer.from([
    n & 0xff,
    (n >>> 8) & 0xff,
    (n >>> 16) & 0xff,
    (n >>> 24) & 0xff,
  ]));
}

function appendString(value) {
  const bytes = encoder.encode(value);
  appendU32LE(bytes.length);
  chunks.push(Buffer.from(bytes));
}

chunks.push(Buffer.from('DPKG', 'ascii'));
appendU32LE(requiredPackages.length);

for (const name of requiredPackages) {
  const pkg = packagesByName.get(name);
  if (!pkg) {
    throw new Error(`Package ${name} not found in ${packageConfigPath}`);
  }

  const root = packageRoot(pkg);
  const files = collectPackageFiles(root);
  if (files.length === 0) {
    throw new Error(`Package ${name} at ${root} did not contribute any files`);
  }

  appendString(name);
  appendU32LE(files.length);
  for (const file of files) {
    appendString(file.path);
    appendU32LE(file.content.length);
    chunks.push(file.content);
  }

  console.error(`packed ${name}: ${files.length} files`);
}

writeFileSync(outPath, Buffer.concat(chunks));
console.error(`wrote ${outPath}`);
