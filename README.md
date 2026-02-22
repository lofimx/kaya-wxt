# kaya-wxt

Kaya browser extensions

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

This bumps the patch version in `extension/package.json`, commits, tags (e.g. `v0.1.1`), and pushes. The tag triggers the GitHub Actions workflow which builds the extension for Firefox, Chrome, and Edge, runs tests, publishes to all three browser stores, and creates a GitHub Release with all artifacts.

For detailed store setup, secrets configuration, and first-time submission instructions, see [doc/stores/STORES.md](doc/stores/STORES.md).

## Open Questions

* Ladybird and Servo Browser support in the future?

## TODO

* [ ] First submission to Chrome Web Store (update Chrome Extension ID after publish)
* [ ] First submission to Edge Add-ons (update Edge Extension ID after publish)
* [ ] Configure GitHub repository secrets for automated store publishing

## Temp: Saving Screenshots and First Store Submissions

**Screenshots first.** Before submitting to either store, you'll need at least one 1280x800 screenshot. To capture one:

1. Load the extension in Chrome: `cd extension && pnpm dev:chrome`, then go to `chrome://extensions`, enable Developer mode, load unpacked from `extension/.output/chrome-mv3/`
2. Navigate to any website, click the toolbar button
3. Capture a 1280x800 screenshot of the browser window
4. Save it as `doc/stores/screenshot-1-popup.png`

---

**Then, Chrome Web Store submission**:

1. Build the zip: `cd extension && pnpm zip:chrome`
2. Go to [Chrome Web Store Developer Dashboard](https://chrome.google.com/webstore/devconsole)
3. Click "New item", upload the zip from `extension/.output/`
4. Fill in the listing using the text from `doc/stores/listing.md`, the screenshot(s), and `doc/stores/store-icon-128.png`
5. Fill in Privacy tab with the privacy policy URL and permissions justifications from `listing.md`
6. Submit for review
7. Note the **Chrome Extension ID** (32-char string from the dashboard URL)
