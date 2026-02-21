# Guide for LLMs

This repository will contain two tightly related projects:

* `/extension` contains a Firefox browser extension
* `/sync-daemon` contains a small, native sync engine written in Rust

Both will be named "Save Button", to the user. The application name can be `org.savebutton.nativehost` in the native messaging manifest. The application (gecko) ID can be `org.savebutton@savebutton.org` in both the native messaging manifest (`org.savebutton.nativehost.json`) and the extension's `manifest.json`. Though as long as it's correct and symmetrical, the name/id doesn't matter.

## Planning

Read [@PLAN.md](./doc/plan/PLAN.md) and follow those instructions for creating a plan before any work is performed.

---

## Prompt History

You can find a chronological list of significant past prompts in [@PROMPTS.md](./doc/PROMPTS.md). Major prompts are titled with Subheading Level Two (\#\#), sub-prompts are titled with Subheading Level Three (\#\#\#).

The current major prompt or bugfix will probably also be in this file, uncommitted.

This file will get large, over time, so only prioritize reading through it if you require additional context.

---

## Architecture

The Firefox extension and the native sync daemon work together, as though they were a single program. Together, they follow the Architectural Decision Records, listed in [@arch](./doc/arch): the native sync daemon saves files to, and reads files from, the directories in `~/.kaya/`. It also performs a periodic sync with the HTTP service listed in [@adr-0002-service-sync.md](./doc/arch/adr-0002-service-sync.md). The Firefox extension primarily exists to provide the user a minimal user interface.

### Logging

Logs go in `~/.kaya/log`.

Log when any significant event occurs. This includes human-triggered messages from the frontend, errors, non-empty file sync events, and so on.

### Errors

Errors must be signaled back to the Firefox plugin from the native host / sync engine. They should also be logged to `~/.kaya/log` for easy inspection.

### Messaging

The Rust daemon communicates with the Firefox plugin via JSON messges. The plugin uses the browser's native messages to communicate with the Rust daemon over STDIN/STDOUT.

The format of the JSON messages is symmetrical to the Anga and Meta files and APIs mentioned under [@adr-0002-service-sync.md](./doc/arch/adr-0002-service-sync.md):

* Anga represent a single file: a `.url` bookmark, a `.md` note, or any other arbitrary file
  * all anga live under `~/.kaya/anga/`
* Meta represent only `.toml` files, following the format from [@adr-0003-metadata.md](./doc/arch/adr-0003-metadata.md) 
  * all metadata lives under `~/.kaya/meta/`

All messaging between the Firefox extension and the Rust daemon should be as simple, flat, and symmetrical as possible. However, the JSON message can and should set a "type" key, declaring either "text" or "base64", which determines which key to read from. `.url` and `.md` files will be passed as text. Images will be passed as base64. For example:

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

The Firefox extension can configure the Rust daemon so it knows where the Kaya Server is. It sends a message formatted like so:

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

Bookmarks will follow the file format `~/.kaya/anga/2026-01-27T171207-www-deobald-ca.url`, where the `www-deobald-ca` portion is the domain and subdomains in the URL, with special characters and periods (`.`) turned into hyphens (`-`). Bookmarks are created by clicking the plugin's Toolbar Button.

Bookmarks are saved as `.url` files which have the format:

```
[InternetShortcut]
URL=https://perkeep.org/
```


## Firefox Extension

The Firefox extension should be built following the guidelines in the [Firefox Browser Extensions documentation](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions).

### Config

The user can right-click the Toolbar Button (see "Toolbar Button") to get a context menu from which they can choose "Preferences" and configure the Kaya Server location (defaults to https://kaya.town), email, and password. These should be sent to the Rust daemon using a Config Message (see "Messaging: Config").

The first time the user clicks the Toolbar Button to save a bookmark, the extension should prompt them with a popup to enter their Kaya Server, email, and password.

### Toolbar Button

The extension must provide a [toolbar button](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/user_interface/Toolbar_button), similar to other bookmark managers, like Pocket. If a website is currently being visited which hasn't been bookmarked (ie. saved into a file with the format `~/.kaya/anga/2026-01-27T171207-some-bookmark-com.url`), the button should appear like [@icon.svg](./doc/design/icon.svg), but grey. If the site has been bookmarked (ie. one of the files in `~/.kaya/anga/*` contains the URL already), the button should appear in full color.

If the user clicks the toolbar button, it should record a new bookmark, even if the user has bookmarked this site before. When the user clicks the button, a small popup with a textbox labelled "Add a Note" should show up, providing the user with the option to create note metadata. If the user clicks into the Note textbox, it remains visible until they hit <enter>. If they don't, it remains visible for 4 seconds and then disappears. If they choose to add a note, the note will be recorded under the `[meta]` header with the key `note = '''their note'''`, as described in [@adr-0003-metadata.md](./doc/arch/adr-0003-metadata.md), with one exception: the user cannot enter a newline or carriage return character and so multiline notes are not possible. This keeps things simple and prevents JSON formatting errors. The `filename =` key under the `[anga]` header should list the name of the anga (bookmark) file they just created by clicking the button.

To synchronize the datetime-stamp, as described in [@adr-0001-core-concept.md](./doc/arch/adr-0001-core-concept.md), the Firefox Extension will choose "now" as of the time the button is pushed and send this to the Rust daemon so it can prefix both the Anga and Meta files with it.

### Text and Images:

The user may also select text on a webpage or right-click an image and choose "Save To Kaya" from an option in the context menu. Text will be saved as a `.md` note, prefixed with the usual datetime-stamp and suffixed with `-quote.md`. Images will be saved as their existing file format, prefixed with the usual datetime-stamp but suffixed with their actual filename and file extension.

Both text and images are sent with a regular Anga message to the Rust daemon, just as bookmarks are.

### Errors

If the Firefox extension experiences an error or receives an error back from the Rust daemon, it should display it to the user.

### Publishing

The Firefox extension should be prepared for publishing on https://addons.mozilla.org as per [The Firefox Extension Workshop docs](https://extensionworkshop.com/documentation/publish/). Do this last.


## Native Rust Daemon

### Messaging

The Firefox extension can communicate with the Rust daemon via the browser's native messaging. On the Rust side, all that should be required is the use of `serde_json` over STDIN and STDOUT.

When a messaging error is encountered, the daemon should notify the Firefox extension of the error with an error description from Rust sent back as a string.

### Config

When the Rust daemon receives a config message (see "Messaging: Config"), it should store the config in a simple key/value store on disk, in a way that will work well on Windows, MacOS, and Linux. The password should be encrypted at rest. The config can be stored in `~/.kaya/.config` if there is no better or more standard cross-platform location.

### Saving Messages

All file ("anga") messages, including bookmarks, text, and images, should be saved to `~/.kaya/anga/`, in the format described in [@adr-0001-core-concept.md](./doc/arch/adr-0001-core-concept.md).

All metadata ("meta") messages should be saved to `~/.kaya/meta/`, in the format described in [@adr-0003-metadata.md](./doc/arch/adr-0003-metadata.md).

### Saving Bookmarks

When the Firefox extension sends a message to save a bookmark, it will arrive as a multi-line string representing a Microsoft Windows-style `.url` file. See "Bookmarks" in this document.

### Saving Text

When the Firefox extension sends a message to save a quote, it will arrive as a string representing a Markdown file.

### Saving Images

When the Firefox extension sends a message to save an image, it will arrive as a Base64-encoded string, which the Rust code will need to decode. Chunking should not be necessary.

### Sync

Once per minute, the Rust daemon should sync the local files (anga and meta) with the Kaya Server over HTTP as per [@adr-0002-service-sync.md](./doc/arch/adr-0002-service-sync.md). You can follow the example found in [@sync.rb](./bin/sync.rb).

### Installer

The Sync Daemon should have a simple installer available for Windows, MacOS, and Linux. On Linux, it's easiest to just publish both a DEB and an RPM. Do this last.


## Testing

In [@test](./test), write Playwrite, Capybara, or Selenium (or any other end-to-end framework) tests to try to test the above scenarios, if possible. Sync against https://localhost:3000 when testing. Stop if you have too much trouble. Don't thrash.
