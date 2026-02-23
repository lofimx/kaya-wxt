# Fix Release Workflow

## Context

After pushing tag `v0.2.1`, the GitHub Actions release workflow failed
([run #22288150666](https://github.com/loficc/kaya-wxt/actions/runs/22288150666)).
The initial fixes (`include-hidden-files` and `@v5.0.0`) were applied for `v0.2.2`,
which fixed the build/artifact issues but revealed three publish-job failures
([run #22289032391](https://github.com/loficc/kaya-wxt/actions/runs/22289032391)).

## Diagnosis

### Round 1 (v0.2.1 failures — fixed)

1. **`.output` hidden directory excluded by `upload-artifact@v4`** — `upload-artifact`
   v4.4+ excludes hidden files by default. Fixed with `include-hidden-files: true`.

2. **`mnao305/chrome-extension-upload@v5` doesn't resolve** — only `v5.0.0` tag exists.
   Fixed by using `@v5.0.0`.

3. **Redundant `wxt build` step** — removed since `wxt zip` builds internally.

### Round 2 (v0.2.2 failures)

1. **Chrome: "Input required and not supplied: extension-id"** — `CHROME_EXTENSION_ID`
   secret is not configured in the GitHub repo.

2. **Edge: "Input required and not supplied: api-key"** — `EDGE_API_KEY` secret is not
   configured in the GitHub repo.

3. **Firefox: `CACError: Unknown option --browser`** — `pnpm wxt submit --browser firefox`
   is invalid syntax. `wxt submit` is an alias for `publish-browser-extension`, which
   uses `--firefox-zip`, `--firefox-jwt-issuer`, `--firefox-jwt-secret`, and
   `--firefox-extension-id` flags. Also, `AMO_JWT_ISSUER` and `AMO_JWT_SECRET` secrets
   are not configured.

## Changes

**File:** `.github/workflows/release.yml`

### Already applied (v0.2.2)
- Added `include-hidden-files: true` to upload-artifact
- Changed `@v5` to `@v5.0.0`
- Removed redundant `wxt build` step

### New fix (Firefox submit syntax)
- Replaced `pnpm wxt submit --browser firefox` with proper `publish-browser-extension`
  flags: `--firefox-zip`, `--firefox-extension-id`, `--firefox-jwt-issuer`,
  `--firefox-jwt-secret`

### Manual action required (secrets)
The following GitHub repository secrets must be configured before publish jobs will work:
- `CHROME_EXTENSION_ID`, `CHROME_CLIENT_ID`, `CHROME_CLIENT_SECRET`, `CHROME_REFRESH_TOKEN`
- `EDGE_PRODUCT_ID`, `EDGE_CLIENT_ID`, `EDGE_API_KEY`
- `AMO_JWT_ISSUER`, `AMO_JWT_SECRET`

## Verification

Push a new tag after configuring secrets and confirm all jobs pass.
