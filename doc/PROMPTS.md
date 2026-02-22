# Historical Prompts

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
