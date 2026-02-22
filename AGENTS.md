# Guide for LLMs

This repository contains two projects:

* `/extension` contains a cross-browser extension built with [WXT](https://wxt.dev/)
* `/daemon` contains an optional local daemon written in Rust

Both are named "Save Button" to the user.

### Identifiers

* **Firefox extension ID (gecko)**: `org.savebutton@savebutton.org`
* **Chrome/Edge extension IDs**: Assigned after first store publish (see README.md TODO)

## Planning

Read [@PLAN.md](./doc/plan/PLAN.md) and follow those instructions for creating a plan before any work is performed.

---

## Prompt History

You can find a chronological list of significant past prompts in [@PROMPTS.md](./doc/PROMPTS.md). Major prompts are titled with Subheading Level Two (\#\#), sub-prompts are titled with Subheading Level Three (\#\#\#).

The current major prompt or bugfix will probably also be in this file, uncommitted.

This file will get large, over time, so only prioritize reading through it if you require additional context.

---

## Architecture

The browser extension is self-sufficient. It stores files locally using **OPFS** (Origin Private File System) and syncs them directly with the Save Button Server over HTTP. An optional local daemon can mirror files to `~/.kaya/` on disk for users who want filesystem access to their saved data.

The extension follows the Architectural Decision Records listed in [@arch](./doc/arch):
* Files ("anga") and metadata ("meta") are stored as real files in OPFS directories
* The extension syncs OPFS contents with the server per [@adr-0002-service-sync.md](./doc/arch/adr-0002-service-sync.md)
* The optional daemon also syncs with the server independently and writes files to `~/.kaya/`

### Supported Browsers

The extension is built with WXT to support multiple browsers from a single codebase:

* **Primary targets**: Firefox, Chrome, Edge
* **Also supported**: Chromium-based browsers (Brave, Opera, Vivaldi, Arc, etc.)
* **Deferred**: Safari (requires separate Xcode packaging), Orion, Epiphany

WXT defaults to MV2 for Firefox/Safari and MV3 for Chrome/Edge/others. Browser-specific code should use `import.meta.env.BROWSER` or `import.meta.env.MANIFEST_VERSION` for conditional logic.

### Storage: OPFS

The extension uses the Origin Private File System (OPFS) for local storage. OPFS provides a real directory/file hierarchy accessible via `navigator.storage.getDirectory()`. All extension data lives under a `/kaya` root directory, symmetrical with the daemon's `~/.kaya/` layout:

* `/kaya/anga/` -- bookmarks (`.url`), text quotes (`.md`), images, and other files
* `/kaya/meta/` -- TOML metadata files linking anga to tags/notes
* `/kaya/words/` -- plaintext copies of anga for full-text search, per [@adr-0005-full-text-search.md](./doc/arch/adr-0005-full-text-search.md)

The `words/` directory has a nested structure: `/kaya/words/{anga}/{filename}`. Words are download-only from the server (the server generates plaintext copies via background jobs).

OPFS is available in Chrome 86+, Firefox 111+, and Safari 15.2+. The async `createWritable()` API works in MV3 service workers.

**Important**: OPFS data is deleted when the extension is uninstalled. The server is the durable store; periodic sync ensures data is backed up.

### Sync

The extension syncs directly with the Save Button Server using `fetch()` and HTTP Basic Auth:

1. `GET /api/v1/{email}/anga` -- server returns newline-separated filenames
2. Diff against local OPFS file listing
3. Download files missing locally, upload files missing on server
4. Same for `meta/`
5. Sync `words/` (download-only): `GET /api/v1/{email}/words` lists anga dirs, then `GET /api/v1/{email}/words/{anga}` lists files within each, then download missing files

Sync runs on two triggers:
* **Periodic**: `chrome.alarms` fires every 1 minute (MV3-safe)
* **Immediate**: After each anga/meta save operation

### Errors

If the browser extension experiences an error during save or sync, it should display it to the user.

### Data Format

Anga and Meta files follow the formats from the ADRs:

* Anga represent a single file: a `.url` bookmark, a `.md` note, or any other arbitrary file
* Meta represent `.toml` files, following the format from [@adr-0003-metadata.md](./doc/arch/adr-0003-metadata.md)

### Bookmarks

Bookmarks will follow the file format `anga/2026-01-27T171207-www-deobald-ca.url`, where the `www-deobald-ca` portion is the domain and subdomains in the URL, with special characters and periods (`.`) turned into hyphens (`-`). Bookmarks are created by clicking the extension's Toolbar Button.

Bookmarks are saved as `.url` files which have the format:

```
[InternetShortcut]
URL=https://perkeep.org/
```


## Browser Extension

The browser extension is built with [WXT](https://wxt.dev/) using vanilla TypeScript. WXT generates browser-specific builds (Firefox MV2, Chrome MV3, Edge MV3, etc.) from a single codebase.

The extension lives under `/extension` and uses WXT conventions:
* `entrypoints/` -- background scripts, popup, options page, etc.
* `public/` -- static assets (icons)
* `utils/` -- shared TypeScript utilities (`opfs.ts`, `sync.ts`, `config.ts`, `daemon.ts`, `timestamp.ts`)
* `wxt.config.ts` -- WXT configuration and manifest settings

### Config

The user can right-click the Toolbar Button (see "Toolbar Button") to get a context menu from which they can choose "Preferences" and configure the Save Button Server location (defaults to https://savebutton.com), email, and password. Config is stored in `browser.storage.local`.

The first time the user clicks the Toolbar Button to save a bookmark, the extension should prompt them with a popup to enter their Save Button Server, email, and password.

### Toolbar Button

The extension must provide a toolbar button, similar to other bookmark managers like Pocket. If a website is currently being visited which hasn't been bookmarked (ie. saved into OPFS as an `anga/*.url` file containing that URL), the button should appear like [@icon.svg](./doc/design/icon.svg), but grey. If the site has been bookmarked, the button should appear in full color.

If the user clicks the toolbar button, it should record a new bookmark, even if the user has bookmarked this site before. When the user clicks the button, a small popup with a textbox labelled "Add a Note" should show up, providing the user with the option to create note metadata. If the user clicks into the Note textbox, it remains visible until they hit <enter>. If they don't, it remains visible for 4 seconds and then disappears. If they choose to add a note, the note will be recorded under the `[meta]` header with the key `note = '''their note'''`, as described in [@adr-0003-metadata.md](./doc/arch/adr-0003-metadata.md), with one exception: the user cannot enter a newline or carriage return character and so multiline notes are not possible. This keeps things simple. The `filename =` key under the `[anga]` header should list the name of the anga (bookmark) file they just created by clicking the button.

To synchronize the datetime-stamp, as described in [@adr-0001-core-concept.md](./doc/arch/adr-0001-core-concept.md), the extension will choose "now" as of the time the button is pushed and use this timestamp to prefix both the Anga and Meta files.

### Text and Images

The user may also select text on a webpage or right-click an image and choose "Save To Kaya" from an option in the context menu. Text will be saved as a `.md` note, prefixed with the usual datetime-stamp and suffixed with `-quote.md`. Images will be saved as their existing file format, prefixed with the usual datetime-stamp but suffixed with their actual filename and file extension.

Both text and images are written to OPFS and then synced, just as bookmarks are.

### Publishing

The extension should be published to each browser's extension store:

* **Firefox**: [addons.mozilla.org](https://addons.mozilla.org) via `web-ext sign`
* **Chrome**: [Chrome Web Store](https://chromewebstore.google.com/) via the Chrome Web Store API
* **Edge**: [Edge Add-ons](https://microsoftedge.microsoft.com/addons/) via the Edge Add-ons API


## Optional Daemon

The daemon (`/daemon`) is a standalone Rust binary that listens on `localhost:21420`. It is entirely optional -- the extension works fully without it.

### Purpose

The daemon provides two services:
1. **Disk mirroring**: Receives files from the extension and writes them to `~/.kaya/anga/`, `~/.kaya/meta/`, and `~/.kaya/words/`
2. **Server sync**: Independently syncs `~/.kaya/` with the Save Button Server every 60 seconds (including `words/`, which is download-only from the server)

### HTTP API

* `GET /health` -- returns 200 OK
* `GET /anga` -- lists files in `~/.kaya/anga/`
* `GET /meta` -- lists files in `~/.kaya/meta/`
* `GET /words` -- lists anga subdirectories in `~/.kaya/words/`
* `GET /words/{anga}` -- lists files in `~/.kaya/words/{anga}/`
* `POST /anga/{filename}` -- writes request body to `~/.kaya/anga/{filename}`
* `POST /meta/{filename}` -- writes request body to `~/.kaya/meta/{filename}`
* `POST /words/{anga}/{filename}` -- writes request body to `~/.kaya/words/{anga}/{filename}`
* `POST /config` -- accepts JSON `{"server", "email", "password"}`, encrypts password, saves to `~/.kaya/.config`

### Communication with Extension

The extension's `daemon.ts` module pushes copies of saved files to the daemon over localhost HTTP. Failures are silently ignored (the daemon is optional).

### Config

The daemon reads its server sync config from `~/.kaya/.config` (TOML format with encrypted password). The extension can push config to the daemon via `POST /config`, which accepts a plaintext password, encrypts it, and saves to `~/.kaya/.config`. The extension also pushes config on each periodic sync cycle, so the daemon picks up credentials even if it starts after the user has configured the extension.

### Logging

Daemon logs go to `~/.kaya/daemon-log`.

### Packaging

The daemon has packaged installers for Windows (MSI), macOS (PKG), and Linux (DEB, RPM, AUR).


## Testing

In [@test](./test), write Playwright, Capybara, or Selenium (or any other end-to-end framework) tests to try to test the above scenarios, if possible. Sync against http://localhost:3000 when testing, using `~/work/deobald/kaya-server/` if a Rails service is not running at http://localhost:3000. Stop if you have too much trouble. Don't thrash.
