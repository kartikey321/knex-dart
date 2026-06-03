#!/usr/bin/env node

// Rewrites package_config roots through a stable symlink tree. The Dart kernel
// compiler records source URIs in its output, so using machine-specific repo and
// pub-cache paths would make playground kernel artifacts differ on every host.

import { mkdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const [inputPathArg, packageLinksDirArg, outputPathArg] = process.argv.slice(2);
if (!inputPathArg || !packageLinksDirArg || !outputPathArg) {
  console.error('usage: node tool/write_playground_package_config.mjs <input-package-config> <package-links-dir> <output-package-config>');
  process.exit(2);
}

const inputPath = resolve(inputPathArg);
const packageLinksDir = resolve(packageLinksDirArg);
const outputPath = resolve(outputPathArg);
const inputUrl = pathToFileURL(inputPath);
const config = JSON.parse(readFileSync(inputPath, 'utf8'));

rmSync(packageLinksDir, { recursive: true, force: true });
mkdirSync(packageLinksDir, { recursive: true });
mkdirSync(dirname(outputPath), { recursive: true });

const rewrittenPackages = config.packages.map((pkg) => {
  const rootUrl = new URL(pkg.rootUri, inputUrl);
  if (rootUrl.protocol !== 'file:') {
    throw new Error(`Unsupported package root URI for ${pkg.name}: ${pkg.rootUri}`);
  }

  const target = fileURLToPath(rootUrl);
  symlinkSync(target, `${packageLinksDir}/${pkg.name}`, 'dir');

  return {
    ...pkg,
    rootUri: `packages/${pkg.name}`,
  };
});

writeFileSync(outputPath, `${JSON.stringify({
  ...config,
  packages: rewrittenPackages,
}, null, 2)}\n`);
