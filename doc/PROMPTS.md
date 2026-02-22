# Historical Prompts

This file should **not be modified by agents.**

## Rewrite `kaya-firefox` to `kaya-wxt` to support all browsers

Read and follow the instructions in [@PLAN.md](file:///home/steven/work/deobald/kaya-firefox/doc/plan/PLAN.md).

Port the entire project found at [@kaya-firefox](file:///home/steven/work/deobald/kaya-firefox/) to [WXT](https://wxt.dev/) in **this repository** with the intention of supporting all major browsers.

### Browser Support

* Firefox
* Chrome
* Edge
* Chromium-based browsers (Opera, Brave, Ungoogled Chromium, SRWare Iron, Iridium, Vivaldi, Arc, Sidekick, DuckDuckGo Browser, etc.)
* Safari
* Orion
* Epiphany

Because Safari, Orion, and Epiphany are "outliers" in terms of extension support, they can be handled with separate plans. Safari, in particular, will require an entirely separate packaging strategy as a MacOS app.

### Operating System Support & Packaging

Because `kaya-firefox` uses a native host to provide direct access to disk, and all browsers will require this same support, it is important that each browser extension has proper packaging for all 3 major operating systems:

* Windows (`.msi` via `cargo-wix` via `cargo-dist`)
* MacOS (`.pkg` via `cargo-packager` via `cargo-dist`)
* Linux, which has 3 major native packaging formats, and from-source:
  * RPM (`.rpm` via `cargo-generate-rpm` via `cargo-dist`)
  * DEB (`.deb` via `cargo-deb` via `cargo-dist`)
  * AUR (`PKGBUILD` via `cargo-aur` directly, consuming `cargo-dist` output)
  * `install.sh` for users who want to install from source

The native host Rust crate can receive a `--install` flag and then use the `install()` function from the `native_messaging` crate to assist with placing JSON files in specific browser folders.

### Immediate Sync

When a bookmark is saved, a server sync should occur immediately after the bookmark is saved to disk, to ensure the synchronization happens before MV3 (Chrome, Edge) potentially suspends the Rust process due to inactivity (~30 seconds).

### Automation: CI/CD

The `kaya-firefox` repo currently has a `.github/workflows/sign-extension.yml` GitHub Actions workflow that does some of the above work. All packages for all 6 distribution targets (Windows, MacOS, RPM, DEB, AUR, `./install.sh`) should be built automatically by GitHub Actions. Any signing, notarizing, etc. should also happen in the GitHub Actions workflow(s).

## Refactor: OPFS storage and optional daemon

Native messaging between the browser extension and the Rust native host proved fundamentally fragile (Chrome's `--user-data-dir` breaks manifest lookup, MV3 service worker suspension closes the pipe within milliseconds).

Refactored the architecture so the extension is self-sufficient:
- **OPFS** stores anga/meta files locally in the browser's sandboxed filesystem
- **Direct HTTP sync** from extension to Save Button Server via `fetch()`
- **Optional daemon** on `localhost:21420` mirrors files to `~/.kaya/` for users who want disk access
- Rename `nativehost/` to `daemon/`, remove native messaging dependencies
- See `doc/plan/2026-02-22-r-opfs-storage-and-optional-daemon.md` and `doc/arch/adr-0004-opfs-storage.md`

### Adjustments

Adjust `doc/plan/2026-02-22-r-opfs-storage-and-optional-daemon.md` based on [@PLAN.md](file:///home/steven/work/lofi/kaya-wxt/doc/plan/PLAN.md) with the following changes:

* Ensure files stored in OPFS follow a convention symmetrical to the daemon's home directory layout, as per [@adr-0001-core-concept.md](file:///home/steven/work/lofi/kaya-wxt/doc/arch/adr-0001-core-concept.md), [@adr-0003-metadata.md](file:///home/steven/work/lofi/kaya-wxt/doc/arch/adr-0003-metadata.md), and so on. The root directory in OPFS for the browser extension should be `/kaya`: `/kaya/anga`, `/kaya/meta`, etc.
* Add a config endpoint to the daemon's HTTP API (e.g. `POST /config`) so the extension can push a server URL and credentials to it
* The daemon should log to `~/.kaya/daemon-log` instead of `~/.kaya/log`.
* Mention the AUR in addition to RPM/DEB in `AGENTS.md`
* Sync the Full-Text Search "words" API in both the browser extension (OPFS) and daemon (`~/.kaya/words`), according to [@adr-0005-full-text-search.md](file:///home/steven/work/lofi/kaya-wxt/doc/arch/adr-0005-full-text-search.md).

## BUG: Failed to Fetch

When I enter my credentials or use "Test Connection", I get a "Connection Failed: Failed to fetch" error.

## BUG: Saving images without extensions fails

I also noticed that an image (the gravatar image on deobald.ca) stores the image incorrectly when it's sync'd to savebutton.com, storing it without an extension or correct mimetype (it seems). The image mimetype doesn't seem to get picked up correctly. The actual image URL is this: https://www.gravatar.com/avatar/03e8994ec9679667eb7eabe1138e168e

## Safari Support

I think all the store submissions are completed except for Safari. Since you said the process for Safari was special, please plan out the implementation based on [@PLAN.md](file:///home/steven/work/lofi/kaya-wxt/doc/plan/PLAN.md) for building Safari support and releasing it. I have an Apple Developer Account for Kaya / Save Button.

### Implement Safari Support

Reviewed plan at `doc/plan/2026-02-22-03-add-safari-support.md` and implemented:
- Built WXT for Safari (`pnpm wxt build -b safari`) producing MV2 output
- Generated Xcode project via `safari-web-extension-converter` with bundle ID `org.savebutton.app`
- Set deployment targets: macOS 12.0, iOS 16.0 (for OPFS support)
- Set marketing version to 0.2.0
- Verified macOS build succeeds via `xcodebuild`
- Created `bin/build-safari.sh` automation script
- Added `build:safari` and `zip:safari` scripts to package.json
- Stubbed `build-safari` CI job in release.yml with TODO for Apple signing secrets
- Updated AGENTS.md, README.md, listing.md, STORES.md

### Replace notifications with green icon flash

Safari doesn't support `browser.notifications.create()`. Replaced `showNotification()` with
`flashGreenIcon()` which temporarily swaps the toolbar icon to a green variant for 2 seconds.
- Generated green icon PNGs (`icon-green-{16,32,48,96}.png`) via ImageMagick color replacement
- Updated `bin/generate-icons.sh` to produce green variants
- Removed `notifications` permission from `wxt.config.ts`
- Added "Safari: Manual Tasks" section to README.md

### Bundle ID / App ID - Need to Switch

Because we already have an App ID `org.savebutton.app` for the main iOS app (https://github.com/deobald/kaya-flutter), which does not share code with the Safari Extension, we need to change the Safari container app and Safari extension target Bundle IDs to use `org.savebutton.safari` as their root, like so:

|        Target           |             Bundle ID            |        App Store Name        |
|-------------------------|----------------------------------|------------------------------|
| Full app                | `org.savebutton.app` (unchanged) | Save Button                  |
| Safari container app    | `org.savebutton.safari`          | Save Button for Safari       |
| Safari extension target | `org.savebutton.safari.Extension | (internal, not user-visible) |
