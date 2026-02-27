# kaya-wxt

Kaya browser extensions

## Browser Support

* Firefox
* Chrome
* Edge
* Safari (macOS, iOS, iPadOS)
* Orion (via Firefox or Chrome)
* Chromium:
  * Vivaldi
  * Brave
  * Arc

## Architecture

The browser extension is self-sufficient: it stores files locally using OPFS (Origin Private File System) and syncs them directly with the Save Button Server over HTTP. An optional local daemon can mirror files to `~/.kaya/` on disk.

Read the [Architecture Decision Records](doc/arch/) for full details.

## Prerequisites

* Node.js 24 (managed via [mise](https://mise.jdx.dev/))
* PNPM

## Development

```bash
cd extension
pnpm install
pnpm dev:chrome    # Chrome with hot reload
pnpm dev:firefox   # Firefox with hot reload
```

### Safari

Safari requires an Xcode project wrapping the web extension. The Xcode project lives in `safari/` and references the WXT build output at `extension/.output/safari-mv2/`.

```bash
bin/build-safari.sh                  # build WXT output (required before Xcode build)
open "safari/Save Button/Save Button.xcodeproj"  # open in Xcode, then build & run
```

To regenerate the Xcode project from scratch (e.g. after changing entrypoints):

```bash
bin/build-safari.sh --regen
```

### Optional Daemon

The daemon is not required for development or normal use. To run it:

```bash
cd daemon
cargo build --release
./target/release/savebutton-daemon
# Listens on localhost:21420
```

## Release

To release a new version:

```bash
ruby bin/release.rb
```

This bumps the patch version in `extension/package.json`, commits, tags (e.g. `v0.1.1`), and pushes. The tag triggers the GitHub Actions workflow which builds the extension for Firefox, Chrome, Edge, and Safari, runs tests, publishes to all four browser stores, and creates a GitHub Release with all artifacts.

For detailed store setup, secrets configuration, and first-time submission instructions, see [doc/stores/STORES.md](doc/stores/STORES.md).

## Safari: Manual Tasks

These steps must be completed in Xcode and App Store Connect before the Safari extension can be distributed.

### One-time Xcode setup

1. Open the project: `open "safari/Save Button/Save Button.xcodeproj"`
2. Select your Apple Developer team for all 4 targets (iOS app, macOS app, iOS extension, macOS extension) and enable automatic signing
3. Register App IDs in the Apple Developer portal:
   - `org.savebutton.safari` (container app)
   - `org.savebutton.safari.Extension` (web extension)
4. Add the **App Groups** capability (`group.org.savebutton`) to both the container app and extension targets on both platforms so they can share data with the full iOS app

### Local testing

**macOS:**
1. Select the "Save Button (macOS)" scheme, press Cmd+R
2. Safari > Settings > Extensions > enable "Save Button"
3. Test: bookmark a page, save text via context menu, save an image, verify sync
4. Check Safari Web Inspector for console errors in the extension background page

**iOS (Simulator or device):**
1. Select the "Save Button (iOS)" scheme, choose a simulator or connected device
2. Build and run
3. Settings > Safari > Extensions > enable "Save Button"
4. Open Safari, test bookmarking and context menu actions

### App Store submission

App Store submissions are automated via CI. See [doc/stores/STORES.md](doc/stores/STORES.md) for details.

## Open Questions

* Ladybird and Servo Browser support in the future?
* "Unsaved" icon: should it just be an outline, instead of grayscale?

## TODO

* [x] First submission to Chrome Web Store (update Chrome Extension ID after publish)
* [x] First submission to Edge Add-ons (update Edge Extension ID after publish)
* [x] Configure GitHub repository secrets for automated store publishing
* [x] Automate Safari CI: secrets configured, see [doc/stores/STORES.md](doc/stores/STORES.md) for details
