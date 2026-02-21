# Guide for LLMs

This repository contains two tightly related projects:

* `/extension` contains a cross-browser extension built with [WXT](https://wxt.dev/)
* `/nativehost` contains a small, native messaging host written in Rust

Both are named "Save Button" to the user.

### Identifiers

* **Native messaging host name**: `org.savebutton.nativehost`
* **Firefox extension ID (gecko)**: `org.savebutton@savebutton.org`
* **Chrome/Edge extension IDs**: Assigned after first store publish (see README.md TODO)

These identifiers appear in native messaging manifests (`org.savebutton.nativehost.json`) and the WXT config (`wxt.config.ts`). As long as they are correct and symmetrical across the extension and the native host, the exact values don't matter.

## Planning

Read [@PLAN.md](./doc/plan/PLAN.md) and follow those instructions for creating a plan before any work is performed.

---

## Prompt History

You can find a chronological list of significant past prompts in [@PROMPTS.md](./doc/PROMPTS.md). Major prompts are titled with Subheading Level Two (\#\#), sub-prompts are titled with Subheading Level Three (\#\#\#).

The current major prompt or bugfix will probably also be in this file, uncommitted.

This file will get large, over time, so only prioritize reading through it if you require additional context.

---

## Architecture

The browser extension and the native host work together as though they were a single program. Together, they follow the Architectural Decision Records listed in [@arch](./doc/arch): the native host saves files to, and reads files from, the directories in `~/.kaya/`. It also performs a periodic sync with the HTTP service listed in [@adr-0002-service-sync.md](./doc/arch/adr-0002-service-sync.md). The browser extension primarily exists to provide the user a minimal user interface.

### Supported Browsers

The extension is built with WXT to support multiple browsers from a single codebase:

* **Primary targets**: Firefox, Chrome, Edge
* **Also supported**: Chromium-based browsers (Brave, Opera, Vivaldi, Arc, etc.)
* **Deferred**: Safari (requires separate Xcode packaging), Orion, Epiphany

WXT defaults to MV2 for Firefox/Safari and MV3 for Chrome/Edge/others. Browser-specific code should use `import.meta.env.BROWSER` or `import.meta.env.MANIFEST_VERSION` for conditional logic.

### Logging

Logs go in `~/.kaya/log`.

Log when any significant event occurs. This includes human-triggered messages from the frontend, errors, non-empty file sync events, and so on.

### Errors

Errors must be signaled back to the browser extension from the native host / sync engine. They should also be logged to `~/.kaya/log` for easy inspection.

### Messaging

The native host communicates with the browser extension via JSON messages. The extension uses the browser's native messaging API (`browser.runtime.connectNative`) to communicate with the native host over STDIN/STDOUT.

The format of the JSON messages is symmetrical to the Anga and Meta files and APIs mentioned under [@adr-0002-service-sync.md](./doc/arch/adr-0002-service-sync.md):

* Anga represent a single file: a `.url` bookmark, a `.md` note, or any other arbitrary file
  * all anga live under `~/.kaya/anga/`
* Meta represent only `.toml` files, following the format from [@adr-0003-metadata.md](./doc/arch/adr-0003-metadata.md)
  * all metadata lives under `~/.kaya/meta/`

All messaging between the browser extension and the native host should be as simple, flat, and symmetrical as possible. However, the JSON message can and should set a "type" key, declaring either "text" or "base64", which determines which key to read from. `.url` and `.md` files will be passed as text. Images will be passed as base64. For example:

```json
{
  "message": "anga",
  "filename": "2026-01-27T171207-wakarimasen.png",
  "type": "base64",
  "base64": "iVBORw0KGgoAAAANSUhEUgAA...",
  ...
}

{
  "message": "anga",
  "filename": "2025-01-27T171207-quote.md",
  "type": "text",
  "text": "Four score and seven years ago, the prime minister of Canada declared the Rules Based Order to be a sham.",
  ...
}

{
  "message": "anga",
  "filename": "2026-01-20T000000_123000000-microsoft-com.url",
  "type": "text",
  "text": "[InternetShortcut]\nURL=https://www.microsoft.com/en-ca/surface\n",
  ...
}

{
  "message": "meta",
  "filename": "2026-01-27T171207-note.toml",
  "type": "text",
  "text": "[anga]\nfilename = \"2026-01-28T205208-bookmark.url\"\n[meta]\nnote = '''This is a longer note, containing a reminder to myself that I was a guest on this podcast. It cannot be multi-line because it is TOML embedded in JSON.'''",
  ...
}
```

### Messaging: Config

The browser extension can configure the native host so it knows where the Save Button Server is. It sends a message formatted like so:

```json
{
  "message": "config",
  "server": "http://localhost:3000",
  "email": "steven@deobald.ca",
  "password": "some-secret-password!",
  ...
}
```

### Bookmarks

Bookmarks will follow the file format `~/.kaya/anga/2026-01-27T171207-www-deobald-ca.url`, where the `www-deobald-ca` portion is the domain and subdomains in the URL, with special characters and periods (`.`) turned into hyphens (`-`). Bookmarks are created by clicking the extension's Toolbar Button.

Bookmarks are saved as `.url` files which have the format:

```
[InternetShortcut]
URL=https://perkeep.org/
```


## Browser Extension

The browser extension is built with [WXT](https://wxt.dev/) using vanilla TypeScript. WXT generates browser-specific builds (Firefox MV2, Chrome MV3, Edge MV3, etc.) from a single codebase.

The extension lives under `/extension` and uses WXT conventions:
* `entrypoints/` — background scripts, popup, options page, etc.
* `public/` — static assets (icons)
* `utils/` — shared TypeScript utilities
* `wxt.config.ts` — WXT configuration and manifest settings

### Config

The user can right-click the Toolbar Button (see "Toolbar Button") to get a context menu from which they can choose "Preferences" and configure the Save Button Server location (defaults to https://savebutton.com), email, and password. These should be sent to the native host using a Config Message (see "Messaging: Config").

The first time the user clicks the Toolbar Button to save a bookmark, the extension should prompt them with a popup to enter their Save Button Server, email, and password.

### Toolbar Button

The extension must provide a toolbar button, similar to other bookmark managers like Pocket. If a website is currently being visited which hasn't been bookmarked (ie. saved into a file with the format `~/.kaya/anga/2026-01-27T171207-some-bookmark-com.url`), the button should appear like [@icon.svg](./doc/design/icon.svg), but grey. If the site has been bookmarked (ie. one of the files in `~/.kaya/anga/*` contains the URL already), the button should appear in full color.

If the user clicks the toolbar button, it should record a new bookmark, even if the user has bookmarked this site before. When the user clicks the button, a small popup with a textbox labelled "Add a Note" should show up, providing the user with the option to create note metadata. If the user clicks into the Note textbox, it remains visible until they hit <enter>. If they don't, it remains visible for 4 seconds and then disappears. If they choose to add a note, the note will be recorded under the `[meta]` header with the key `note = '''their note'''`, as described in [@adr-0003-metadata.md](./doc/arch/adr-0003-metadata.md), with one exception: the user cannot enter a newline or carriage return character and so multiline notes are not possible. This keeps things simple and prevents JSON formatting errors. The `filename =` key under the `[anga]` header should list the name of the anga (bookmark) file they just created by clicking the button.

To synchronize the datetime-stamp, as described in [@adr-0001-core-concept.md](./doc/arch/adr-0001-core-concept.md), the extension will choose "now" as of the time the button is pushed and send this to the native host so it can prefix both the Anga and Meta files with it.

### Text and Images

The user may also select text on a webpage or right-click an image and choose "Save To Kaya" from an option in the context menu. Text will be saved as a `.md` note, prefixed with the usual datetime-stamp and suffixed with `-quote.md`. Images will be saved as their existing file format, prefixed with the usual datetime-stamp but suffixed with their actual filename and file extension.

Both text and images are sent with a regular Anga message to the native host, just as bookmarks are.

### Errors

If the browser extension experiences an error or receives an error back from the native host, it should display it to the user.

### Publishing

The extension should be published to each browser's extension store:

* **Firefox**: [addons.mozilla.org](https://addons.mozilla.org) via `web-ext sign`
* **Chrome**: [Chrome Web Store](https://chromewebstore.google.com/) via the Chrome Web Store API
* **Edge**: [Edge Add-ons](https://microsoftedge.microsoft.com/addons/) via the Edge Add-ons API

Do this last.


## Native Host

### Messaging

The browser extension communicates with the native host via the browser's native messaging API. On the Rust side, all that should be required is the use of `serde_json` over STDIN and STDOUT. The native messaging protocol is identical across all browsers.

When a messaging error is encountered, the native host should notify the browser extension of the error with an error description from Rust sent back as a string.

### Config

When the native host receives a config message (see "Messaging: Config"), it should store the config in a simple key/value store on disk, in a way that will work well on Windows, MacOS, and Linux. The password should be encrypted at rest. The config can be stored in `~/.kaya/.config` if there is no better or more standard cross-platform location.

### Saving Messages

All file ("anga") messages, including bookmarks, text, and images, should be saved to `~/.kaya/anga/`, in the format described in [@adr-0001-core-concept.md](./doc/arch/adr-0001-core-concept.md).

All metadata ("meta") messages should be saved to `~/.kaya/meta/`, in the format described in [@adr-0003-metadata.md](./doc/arch/adr-0003-metadata.md).

### Saving Bookmarks

When the browser extension sends a message to save a bookmark, it will arrive as a multi-line string representing a Microsoft Windows-style `.url` file. See "Bookmarks" in this document.

### Saving Text

When the browser extension sends a message to save a quote, it will arrive as a string representing a Markdown file.

### Saving Images

When the browser extension sends a message to save an image, it will arrive as a Base64-encoded string, which the Rust code will need to decode. Chunking should not be necessary.

### Sync

Once per minute, the native host should sync the local files (anga and meta) with the Save Button Server over HTTP as per [@adr-0002-service-sync.md](./doc/arch/adr-0002-service-sync.md). You can follow the example found in [@sync.rb](./bin/sync.rb).

### Installer

The native host provides a `--install` flag that detects installed browsers and places the correct native messaging manifest for each one. Manifest format and location differ by browser and OS:

* **Firefox** uses `allowed_extensions` in the manifest JSON
* **Chrome/Chromium/Edge/Brave** use `allowed_origins` in the manifest JSON
* **Linux/macOS**: manifest JSON files placed in browser-specific directories
* **Windows**: manifest JSON files registered via the Windows Registry

The native host should have packaged installers for Windows (MSI), MacOS (PKG), and Linux (DEB, RPM). Do this last.


## Testing

In [@test](./test), write Playwright, Capybara, or Selenium (or any other end-to-end framework) tests to try to test the above scenarios, if possible. Sync against http://localhost:3000 when testing, using `~/work/deobald/kaya-server/` if a Rails service is not running at http://localhost:3000. Stop if you have too much trouble. Don't thrash.
