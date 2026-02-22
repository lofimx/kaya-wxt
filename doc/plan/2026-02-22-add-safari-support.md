# Add Safari Support

**Date**: 2026-02-22

## Context

Save Button is already published on the Chrome Web Store, Edge Add-ons, and Firefox AMO. Safari is the remaining major browser. Safari Web Extensions use the same WebExtension APIs but must be packaged as a macOS/iOS app containing the extension. This requires Xcode and Apple's `safari-web-extension-converter` tool.

The extension already uses OPFS (supported in Safari 15.2+), `browser.alarms`, and `fetch()` -- all available in Safari.

## Prerequisites

- macOS with Xcode 14+ installed
- Apple Developer Program membership (already have this)
- The `safari-web-extension-converter` CLI (ships with Xcode, located at `/usr/bin/xcrun safari-web-extension-converter`)
- Node.js 24+ and pnpm 10+ (install via `mise` or directly)
- Clone and set up the repo:
  ```bash
  git clone <repo-url> kaya-wxt
  cd kaya-wxt/extension
  pnpm install
  ```

## Phase 1: Build the Safari Extension

WXT supports Safari as a build target. It produces an MV2 build (same as Firefox):

```bash
cd extension
pnpm wxt build -b safari
```

Output: `.output/safari-mv2/`

Verify the generated `manifest.json` looks correct (MV2, `browser_specific_settings` stripped, permissions intact).

## Phase 2: Convert to Xcode Project

Run Apple's converter on the WXT build output:

```bash
xcrun safari-web-extension-converter extension/.output/safari-mv2/ \
  --project-location safari/ \
  --app-name "Save Button" \
  --bundle-identifier org.savebutton.extension \
  --no-open
```

This generates a `safari/` directory containing:
- An Xcode project (`.xcodeproj`)
- A macOS app target (the container app)
- An iOS app target (the container app for iPhone/iPad)
- A Safari Web Extension target (contains the actual extension, shared across platforms)
- The extension files copied into the Xcode project

Flags:
- `--no-open`: Don't auto-open Xcode
- `--bundle-identifier`: `org.savebutton.extension` (matching other extension identifiers)

No `--macos-only` flag -- we target macOS, iOS, and iPadOS.

## Phase 3: Configure the Xcode Project

On the Mac, open the Xcode project and configure:

1. **Signing**: Select the Apple Developer team, enable automatic signing for all targets
2. **App IDs**: Register in App Store Connect:
   - `org.savebutton.extension` for the container app
   - `org.savebutton.extension.extension` for the web extension target
3. **App Groups**: Add an App Group capability (e.g. `group.org.savebutton`) to both the container app and extension targets, so they can share data on iOS
4. **Version**: Set to 0.2.0 to match other stores
5. **App Icon**: Add the Save Button icon to the asset catalog (use `doc/design/yellow-floppy4.svg` as source, generate the required sizes for both macOS and iOS)
6. **Minimum deployment targets**:
   - macOS 12.0 (Safari 15.2+ for OPFS support)
   - iOS 16.0 (Safari 16+ for OPFS support)
7. **Category**: Productivity

## Phase 4: Test Locally

### macOS
1. Build and run the macOS container app from Xcode (Cmd+R)
2. Open Safari > Settings > Extensions, enable "Save Button"
3. Test: bookmark a page, save text via context menu, save an image, verify sync works
4. Check Safari's Web Inspector for any console errors in the extension background page

### iOS (Simulator or device)
1. Select an iOS simulator or connected device in Xcode
2. Build and run
3. Open Settings > Safari > Extensions, enable "Save Button"
4. Open Safari, test bookmarking and context menu actions
5. Verify OPFS and sync work on iOS Safari

## Phase 5: Archive and Submit to App Store

1. In Xcode: Product > Archive (for each platform, or use "Any Device" destination)
2. In the Organizer window: Distribute App > App Store Connect
3. In App Store Connect:
   - Create a new app listing for "Save Button" under the Productivity category
   - Set platform to macOS + iOS
   - Fill in description from `doc/stores/listing.md`
   - Upload screenshots taken from Safari (macOS) and iOS Safari
   - Set pricing to Free
   - Submit for review

## Phase 6: Automate in CI (Optional, Later)

Add a `build-safari` job to `.github/workflows/release.yml`:

```yaml
build-safari:
  runs-on: macos-latest
  steps:
    - uses: actions/checkout@v4
    - uses: pnpm/action-setup@v4
    - uses: actions/setup-node@v4
      with:
        node-version: 24
    - run: cd extension && pnpm install && pnpm wxt build -b safari
    - run: |
        xcrun safari-web-extension-converter extension/.output/safari-mv2/ \
          --project-location safari/ \
          --app-name "Save Button" \
          --bundle-identifier org.savebutton.extension \
          --no-open
    - run: |
        cd safari
        xcodebuild archive \
          -scheme "Save Button" \
          -archivePath build/SaveButton.xcarchive \
          CODE_SIGN_IDENTITY="${{ secrets.APPLE_CODE_SIGN_IDENTITY }}" \
          DEVELOPMENT_TEAM="${{ secrets.APPLE_TEAM_ID }}"
```

Full App Store upload automation requires `xcrun altool` or the Transporter app, plus additional secrets (App Store Connect API key). This can be deferred -- manual archive + upload from Xcode is fine for now.

## Phase 7: Update Documentation

1. **AGENTS.md**: Move Safari from "Deferred" to "Primary targets"
2. **README.md**: Add Safari to the browser list, mention the Mac App Store
3. **STORES.md**: Add Safari/App Store section with submission details and secrets
4. **listing.md**: Add any Safari-specific notes if needed

## Directory Structure

```
kaya-wxt/
├── safari/                          # Generated by safari-web-extension-converter
│   ├── Save Button.xcodeproj/
│   ├── Save Button/                 # macOS container app
│   │   ├── AppDelegate.swift
│   │   ├── Assets.xcassets/
│   │   └── ...
│   ├── Save Button iOS/             # iOS container app
│   │   ├── AppDelegate.swift
│   │   ├── Assets.xcassets/
│   │   └── ...
│   └── Save Button Extension/      # The web extension (shared)
│       ├── Resources/               # Extension files copied from .output/safari-mv2/
│       └── ...
└── ...
```

The `safari/` directory should be committed to the repo so the Xcode project is reproducible. When the extension code changes, re-run the converter or manually update the Resources directory.

## Implementation Order

All phases run on the Mac: 1 -> 2 -> 3 -> 4 -> 5 -> 7. Phase 6 (CI automation) is optional and can be deferred.
