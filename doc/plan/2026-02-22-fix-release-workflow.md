# Fix Release Workflow

## Context

After pushing tag `v0.2.1`, the GitHub Actions release workflow failed
([run #22288150666](https://github.com/loficc/kaya-wxt/actions/runs/22288150666)).
Two root-cause issues need to be fixed in `.github/workflows/release.yml`.

## Diagnosis

### Issue 1: Hidden directory `.output` excluded by `upload-artifact@v4`

The CI logs confirm `pnpm wxt zip` **succeeded** and produced
`.output/save-button-0.2.1-chrome.zip`. But `actions/upload-artifact@v4`
(v4.4+) excludes hidden files and directories by default. Since `.output`
starts with a dot, the glob `extension/.output/*.zip` matches nothing.

This cascades into all three publish jobs (Chrome, Edge, Firefox) failing
with "Artifact not found".

**Fix:** Add `include-hidden-files: true` to the `upload-artifact` step.

### Issue 2: `mnao305/chrome-extension-upload@v5` does not resolve

The action's repository only has the tag `v5.0.0` — there is no floating
`v5` tag. GitHub Actions cannot resolve it.

**Fix:** Change `@v5` to `@v5.0.0`.

## Changes

**File:** `.github/workflows/release.yml`

1. **Line 44 (upload-artifact in `build-extension`):** Add `include-hidden-files: true`.

2. **Line 130 (publish-chrome):** Change `mnao305/chrome-extension-upload@v5`
   to `mnao305/chrome-extension-upload@v5.0.0`.

3. **Line 36-37 (optional cleanup):** Remove the redundant `pnpm wxt build` step
   from `build-extension` since `pnpm wxt zip` already builds internally. This
   simplifies the job and avoids building twice.

## Verification

Review the diff, then push a new tag (e.g. `v0.2.2` via `ruby bin/release.rb`)
and confirm all jobs pass.
