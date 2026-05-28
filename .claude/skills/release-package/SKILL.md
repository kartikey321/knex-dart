# Skill: release-package

Release a knex_dart package, the docs site, or the playground.

## Release a Dart package (core or driver)

1. **Bump the version** in the package's `pubspec.yaml`:
   ```yaml
   version: 1.3.0
   ```

2. **Update `CHANGELOG.md`** in the same package directory.

3. **Run checks**:
   ```bash
   melos run analyze
   make test-unit          # for core
   # or make test-<driver> for a driver package
   ```

4. **Dry-run publish from the package directory**:
   ```bash
   cd packages/knex_dart
   dart pub publish --dry-run
   ```

5. **Commit**:
   ```bash
   git add packages/knex_dart/pubspec.yaml packages/knex_dart/CHANGELOG.md
   git commit -m "chore(knex_dart): release v1.3.0"
   ```

6. **Tag and push**:
   ```bash
   git tag knex_dart-v1.3.0
   git push && git push --tags
   ```

   Tag patterns for other packages:
   - `knex_dart_postgres-v0.3.0`
   - `knex_dart_mysql-v0.2.0`
   - etc.

7. **Publish to pub.dev** (manual step — do from the package directory):
   ```bash
   cd packages/knex_dart
   dart pub publish
   ```

## Release the playground

The playground deploys via GitHub Actions on a `playground-v*.*.*` tag.

1. Verify the build locally:
   ```bash
   cd playground && npm ci && npm run check && npm run build
   ```

2. Tag and push:
   ```bash
   git tag playground-v1.2.0
   git push --tags
   ```

   GitHub Actions (`.github/workflows/deploy_playground.yml`) will build and deploy to Cloudflare Pages automatically.

3. To deploy manually without a tag (e.g. hotfix):
   ```bash
   cd playground && npm run build
   npx wrangler pages deploy dist --project-name=knex-dart-playground --branch main
   ```
   Requires `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` in environment.

## Release the docs site

The docs deploy via GitHub Actions on a `docs-v*.*.*` tag.

1. Verify the build locally:
   ```bash
   cd docs/site && dart run jaspr build
   ```

2. Tag and push:
   ```bash
   git tag docs-v1.1.0
   git push --tags
   ```

   GitHub Actions (`.github/workflows/deploy_docs.yml`) will build and deploy to Cloudflare Pages automatically.

## Notes

- Cloudflare Pages has a **25 MiB per-file limit**. The playground's `dart-live/` WASM assets need to stay below that per-file cap.
- Playground deploys are tag-triggered from [deploy_playground.yml](/Users/kartik/StudioProjects/knex/knex-dart/.github/workflows/deploy_playground.yml).
- Docs deploys are CI-gated through [deploy_docs.yml](/Users/kartik/StudioProjects/knex/knex-dart/.github/workflows/deploy_docs.yml).
