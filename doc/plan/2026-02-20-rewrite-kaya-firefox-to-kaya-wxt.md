# Rewrite `kaya-firefox` to `kaya-wxt` for All-Browser Support

## Summary

Port the existing Firefox-only extension and Rust sync daemon from `kaya-firefox` to a WXT-based cross-browser extension in this repository (`kaya-wxt`). The native Rust daemon adopts the [`native_messaging`](https://crates.io/crates/native_messaging) crate (v0.2.0) for both stdin/stdout framing and multi-browser manifest installation, replacing hand-rolled code.

---

## Phase 1: WXT Extension Scaffolding

### 1.1 Initialize WXT project

Create a WXT project under `/extension` using vanilla TypeScript (no framework).

**Files created:**
- `extension/package.json` — name `save-button`, scripts for `dev`, `build`, `zip`, `postinstall`
- `extension/wxt.config.ts` — manifest config, permissions, icons, browser-specific settings
- `extension/tsconfig.json`

**`wxt.config.ts` key decisions:**
- `srcDir: '.'` (entrypoints live directly under `extension/entrypoints/`)
- `manifest.permissions`: `["activeTab", "tabs", "contextMenus", "nativeMessaging", "storage", "notifications"]`
- `manifest.name`: `"Save Button"`
- `manifest.description`: `"Save bookmarks, quotes, and images with Save Button"`
- `manifest.author`: `"lofi.mx"`
- `manifest.homepage_url`: `"https://savebutton.com"`
- `manifest.browser_specific_settings.gecko.id`: `"org.savebutton@savebutton.org"`
- `manifest.browser_specific_settings.gecko.strict_min_version`: `"91.0"`
- Icons auto-discovered from `public/` directory
- For Chrome/Chromium: `manifest.action` (WXT auto-converts `action` to `browser_action` for MV2)

WXT defaults: MV2 for Firefox/Safari, MV3 for Chrome/Edge/others.

### 1.2 Generate icons into `extension/public/`

Generate all icons from the source SVG at `doc/design/yellow-floppy4.svg` (do not copy from `kaya-firefox`).

**Create `bin/generate-icons.sh`** — a script that:
1. Takes an optional SVG path argument (defaults to `doc/design/yellow-floppy4.svg`)
2. Uses `rsvg-convert` (from `librsvg`) or `inkscape` CLI to render PNGs at sizes: 16, 32, 48, 96, 128px
3. Generates both colored and greyscale variants:
   - Colored: render the SVG as-is
   - Grey: render the SVG, then desaturate (e.g. via ImageMagick `convert -colorspace Gray`)
4. Also copies/generates SVG variants at 48 and 96 logical sizes for Firefox (which supports SVG icons)
5. Outputs all icons to `extension/public/icon/`

**Generated files:**
- `extension/public/icon/icon-16.png`, `icon-32.png`, `icon-48.png`, `icon-96.png`, `icon-128.png`
- `extension/public/icon/icon-grey-16.png`, `icon-grey-32.png`, `icon-grey-48.png`, `icon-grey-96.png`, `icon-grey-128.png`
- `extension/public/icon/icon-48.svg`, `icon-96.svg` (colored SVG, for Firefox)
- `extension/public/icon/icon-grey-48.svg`, `icon-grey-96.svg` (greyscale SVG, for Firefox)

All generated icons are checked into source control. The script can be re-run whenever the source SVG changes.

---

## Phase 2: Port Extension Entrypoints

### 2.1 Background script (`extension/entrypoints/background.ts`)

Port `background.js` to TypeScript using `defineBackground()`:
- Native host connection via `browser.runtime.connectNative("org.savebutton.nativehost")`
- Message queue with request/response IDs and promises
- Bookmark URL tracking (`knownBookmarkedUrls` set) and icon updates
- Context menu creation ("Add to Save Button" for text selections and images)
- Image fetching, base64 encoding, and sending as anga messages
- `browser.runtime.onMessage` listener for popup/options communication
- Notification display

**Cross-browser considerations:**
- WXT provides `browser` API polyfill automatically (uses `webextension-polyfill` under the hood for Chrome)
- `browser.browserAction` (MV2) vs `browser.action` (MV3) — WXT handles this when you use `action` in the manifest config; at runtime, use `browser.action` and WXT shims it
- `browser.runtime.connectNative` works the same across Firefox and Chrome
- Chrome MV3 uses service workers (no persistent background); ensure no state leaks across service worker restarts. The `knownBookmarkedUrls` set should be refreshed on service worker activation. Consider `browser.storage.session` for ephemeral state in MV3.

### 2.2 Popup (`extension/entrypoints/popup/`)

Port popup UI:
- `extension/entrypoints/popup.html` — HTML with `<meta>` tags for WXT popup config
- `extension/entrypoints/popup/main.ts` — TypeScript port of popup.js
- `extension/entrypoints/popup/style.css` — popup.css (unchanged)

The HTML file will use WXT meta tags:
```html
<meta name="manifest.default_icon" content="{ \"48\": \"/icon/icon-grey-48.svg\", \"96\": \"/icon/icon-grey-96.svg\" }" />
<meta name="manifest.default_title" content="Add to Save Button" />
```

Logic is identical: setup view for first-time config, bookmark view for saving.

### 2.3 Options page (`extension/entrypoints/options/`)

Port options UI:
- `extension/entrypoints/options.html` — with WXT meta tag `open_in_tab: false`
- `extension/entrypoints/options/main.ts` — TypeScript port of options.js
- `extension/entrypoints/options/style.css` — options.css (unchanged)

---

## Phase 3: Multi-Browser Native Messaging (via `native_messaging` crate)

The [`native_messaging`](https://crates.io/crates/native_messaging) crate (v0.2.0) handles both the stdin/stdout wire protocol and the multi-browser manifest install/verify/remove lifecycle. We use it with **sync-only framing** (no Tokio).

### 3.1 What the crate provides

**Manifest installation** (`native_messaging::install()`):
- Writes correctly-formatted JSON manifests for each browser
- Chromium-family (`allowed_origins`) vs Firefox-family (`allowed_extensions`) handled automatically
- Creates target directories as needed
- On Windows, writes registry keys for browsers that require them
- Companion functions: `verify_installed()`, `remove()`

**Supported browsers** (embedded `browsers.toml`, overridable via env var):
- Chromium-family: `chrome`, `edge`, `chromium`, `brave`, `vivaldi`
- Firefox-family: `firefox`, `librewolf`

**Per-OS manifest paths** are built into the crate's config for all 3 platforms (Linux, macOS, Windows) with both user and system scopes.

**Stdin/stdout framing** (sync API, no Tokio needed):
- `encode_message()` / `decode_message()` — 4-byte native-endian length prefix + JSON
- `send_json()` / `recv_json()` — typed serde helpers
- Correct size limits: 1 MiB outgoing, 64 MiB incoming
- Proper EOF/disconnect handling

### 3.2 What we still handle ourselves

- **`--install` CLI flag**: thin wrapper that calls `native_messaging::install()` with our host name, description, exe path, allowed origins/extensions, and browser list. Add `clap` for CLI argument parsing.
- **`--uninstall` CLI flag**: calls `native_messaging::remove()`.
- **Browser detection**: before calling `install()`, check which browsers are actually present on the system so we don't write manifests to nonexistent directories. The crate creates directories but doesn't detect browser presence.
- **`~/.kaya/` directory creation**: not the crate's concern.

### 3.3 Manifest format differences (for reference)

**Firefox-family** uses `allowed_extensions`:
```json
{
  "name": "org.savebutton.nativehost",
  "description": "...",
  "path": "/usr/local/bin/savebutton-sync-daemon",
  "type": "stdio",
  "allowed_extensions": ["org.savebutton@savebutton.org"]
}
```

**Chromium-family** uses `allowed_origins`:
```json
{
  "name": "org.savebutton.nativehost",
  "description": "...",
  "path": "/usr/local/bin/savebutton-sync-daemon",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://EXTENSION_ID_HERE/"]
}
```

Chrome/Edge extension IDs are assigned after first store publish. Use a placeholder `allowed_origins` for now (see README.md TODO).

---

## Phase 4: Port & Update the Rust Sync Daemon

### 4.1 Copy the Rust crate

Copy `sync-daemon/` from `kaya-firefox` to `sync-daemon/` in this repo.

### 4.2 Update `Cargo.toml` dependencies

Replace hand-rolled messaging code with the `native_messaging` crate:

```toml
native_messaging = { version = "0.2", default-features = false, features = ["install"] }
clap = { version = "4", features = ["derive"] }
```

Key points:
- `default-features = false` disables the `tokio` feature — we use sync-only framing
- `install` feature enables manifest install/verify/remove + embedded `browsers.toml`
- On Windows builds, also enable `windows-registry` feature

**Dependencies to remove/simplify:**
- Remove hand-rolled `read_native_message()` / `write_native_message()` from `main.rs` — use `native_messaging::host::{decode_message, encode_message, send_json, recv_json}` instead

### 4.3 Refactor `main.rs`

- Replace the manual 4-byte length prefix stdin/stdout code with `native_messaging::host::decode_message()` and `native_messaging::host::encode_message()` (or the typed `recv_json()` / `send_json()` helpers)
- Keep the background sync thread (`reqwest::blocking`, every 60s) — no Tokio needed
- **Immediate sync**: after handling an `anga` or `meta` message (file written to disk), trigger `sync_with_server()` immediately in addition to the periodic 60-second poll. This ensures data reaches the server before MV3 browsers (Chrome, Edge) can suspend the process (~30s inactivity timeout).
- Add `clap` CLI argument parsing with `--install` and `--uninstall` flags
- The `--install` flag calls `native_messaging::install()` with:
  - `host_name`: `"org.savebutton.nativehost"`
  - `exe_path`: absolute path to the installed binary
  - `allowed_origins`: `["chrome-extension://PLACEHOLDER/"]` (updated after CWS/Edge publish)
  - `allowed_extensions`: `["org.savebutton@savebutton.org"]`
  - `browsers`: `["chrome", "edge", "chromium", "brave", "vivaldi", "firefox", "librewolf"]`
  - `scope`: `Scope::User`
- The `--uninstall` flag calls `native_messaging::remove()` with the same browser list

### 4.4 Drop `src/install.rs`

No custom install module needed — the `native_messaging` crate handles all manifest generation, path resolution, and Windows registry operations.

### 4.5 Keep `src/lib.rs`

The `parse_server_file_listing()` helper remains unchanged.

---

## Phase 5: Install Scripts (Multi-Browser)

### 5.1 `install.sh` (Linux/macOS, from source)

Update the existing `install.sh` to:
1. Build the Rust binary
2. Install to `/usr/local/bin/`
3. Run `savebutton-sync-daemon --install` to place manifests for all detected browsers
4. Create `~/.kaya/` directories

### 5.2 `install.ps1` (Windows, from source)

Update to:
1. Build the Rust binary
2. Install to `C:\Program Files\Save Button\`
3. Run `savebutton-sync-daemon.exe --install` to set up registry entries for all detected browsers
4. Create `%USERPROFILE%\.kaya\` directories

### 5.3 Packaging scripts (DEB, RPM, PKG)

Update `build-deb.sh`, `build-rpm.sh`, `build-pkg.sh` to:
- Drop the `.xpi` bundling (extensions are now distributed per-browser through their respective stores)
- Install native messaging manifests for *all* supported browsers on the platform
- The postinstall scripts should run `savebutton-sync-daemon --install`

---

## Phase 6: CI/CD (GitHub Actions)

### 6.1 Extension building workflow

Create `.github/workflows/build-extension.yml`:
- Build the WXT extension for each target browser: `wxt build -b firefox`, `wxt build -b chrome`, `wxt build -b edge`, `wxt build -b safari`
- Zip each with `wxt zip -b <browser>`
- For Firefox: sign with `web-ext sign` (AMO listed + unlisted)
- For Chrome: upload to Chrome Web Store via API (or manual for now)
- For Edge: upload to Edge Add-ons (or manual for now)
- Upload all zipped extensions as release artifacts

### 6.2 Native daemon packaging workflow

Update the existing `sign-extension.yml` to become `release.yml`:
- Trigger on `v*.*.*` tags
- Build DEB, RPM, MSI, PKG installers (same matrix as before)
- Each installer now includes multi-browser manifest support via `--install`
- Attach all artifacts to the GitHub Release

### 6.3 AUR packaging

Add an AUR PKGBUILD that:
- Downloads the release binary or builds from source
- Runs `savebutton-sync-daemon --install` in postinstall

---

## Phase 7: Testing

### 7.1 Extension unit tests

Use WXT's testing support (Vitest) for:
- Timestamp generation
- URL-to-domain-slug conversion
- Message formatting

### 7.2 Rust daemon tests

Existing `sync_test.rs` carries over. Add tests for:
- `--install` flag manifest generation
- Multi-browser manifest detection

### 7.3 E2E smoke test (Playwright + real Rust daemon)

Attempt a Playwright E2E smoke test under `test/` that:
1. Builds the Rust daemon and the WXT extension (Firefox target)
2. Launches Firefox with the extension loaded and the real native messaging host connected
3. Navigates to a URL (e.g. `https://example.com`)
4. Clicks the toolbar button to save a bookmark
5. Asserts that a `.url` file was written to `~/.kaya/anga/` with the correct URL content

This tests the full end-to-end path: extension popup -> native messaging -> Rust daemon -> file on disk. No mocks. Stop if you have too much trouble. Don't thrash.

---

## Phase 8: Safari, Orion, Epiphany (Separate Plans)

These are explicitly deferred to separate plan documents:
- **Safari**: Requires wrapping the extension as a macOS app via Xcode with `safari-web-extension-converter`
- **Orion**: Supports both Chrome and Firefox extension formats natively; test with existing builds
- **Epiphany**: Supports WebExtensions to a limited degree; test with existing Firefox build

---

## File Structure (Target)

```
kaya-wxt/
├── extension/
│   ├── package.json
│   ├── wxt.config.ts
│   ├── tsconfig.json
│   ├── entrypoints/
│   │   ├── background.ts
│   │   ├── popup.html
│   │   ├── popup/
│   │   │   ├── main.ts
│   │   │   └── style.css
│   │   ├── options.html
│   │   └── options/
│   │       ├── main.ts
│   │       └── style.css
│   ├── public/
│   │   └── icon/
│   │       ├── icon-48.svg
│   │       ├── icon-96.svg
│   │       ├── icon-grey-48.svg
│   │       ├── icon-grey-96.svg
│   │       ├── icon-16.png
│   │       ├── icon-32.png
│   │       ├── icon-48.png
│   │       ├── icon-128.png
│   │       └── ... (grey PNGs)
│   └── utils/
│       ├── native-messaging.ts
│       └── timestamp.ts
├── sync-daemon/
│   ├── Cargo.toml
│   ├── src/
│   │   ├── main.rs
│   │   └── lib.rs
│   ├── tests/
│   │   └── sync_test.rs
│   ├── packaging/
│   │   ├── build-deb.sh
│   │   ├── build-rpm.sh
│   │   └── build-pkg.sh
│   ├── install.sh
│   ├── install.ps1
│   ├── uninstall.sh
│   └── uninstall.ps1
├── bin/
│   ├── generate-icons.sh
│   ├── sync.rb
│   └── release.rb
├── .github/
│   └── workflows/
│       └── release.yml
├── test/
├── doc/
└── ...
```

---

## Resolved Questions

1. **Chrome Extension ID**: Handle after first Chrome Web Store publish. Use a placeholder `allowed_origins` in the Chrome native messaging manifest for now. Manual step required post-publish: update the Chrome extension ID in the manifest template and in `--install` logic. Tracked in README.md TODO.

2. **Edge Extension ID**: Same as Chrome — handle after first Edge Add-ons publish. Tracked in README.md TODO.

3. **Default server URL**: `https://savebutton.com` is the canonical default everywhere.

4. **`native_messaging` crate**: Use the [`native_messaging`](https://crates.io/crates/native_messaging) crate (v0.2.0) for both manifest installation and stdin/stdout framing. The crate supports 7 browsers (chrome, edge, chromium, brave, vivaldi, firefox, librewolf) across all 3 OSes with correct paths and Windows registry handling. We use it with `default-features = false` (no Tokio) + the `install` feature. This replaces both our hand-rolled `read_native_message()`/`write_native_message()` and eliminates the need for a custom `src/install.rs`.

5. **PNG icon generation**: Generate PNGs once from `doc/design/yellow-floppy4.svg` and check them into source control. Include a `bin/generate-icons.sh` script to regenerate them in the future if the SVG changes.

6. **WXT framework version**: Use the latest stable WXT version.

7. **Package manager**: PNPM (WXT's recommended default). Add `pnpm` to `mise.toml` alongside Node 24.

8. **`release.rb`**: Update to bump `extension/package.json` instead of `extension/manifest.json`, since WXT generates the manifest from `package.json`.

---

## Execution Order

1. Phase 1 (scaffolding) and Phase 4.1 (copy Rust crate) — can be done in parallel
2. Phase 2 (port entrypoints) — depends on Phase 1
3. Phase 3 (multi-browser manifests) and Phase 4.2 (`--install` flag) — can be done together
4. Phase 5 (install scripts) — depends on Phase 4
5. Phase 6 (CI/CD) — depends on Phases 2 + 5
6. Phase 7 (testing) — can begin after Phase 2
7. Phase 8 (Safari/Orion/Epiphany) — separate future plans
