# kaya-wxt

Kaya browser extensions

## Browser Support

* Firefox
* Chrome
* Edge
* Safari (soon)
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

* [x] First submission to Chrome Web Store (update Chrome Extension ID after publish)
* [x] First submission to Edge Add-ons (update Edge Extension ID after publish)
* [ ] Configure GitHub repository secrets for automated store publishing
