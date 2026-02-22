# ADR 0004: OPFS Storage and Direct HTTP Sync

## Context

The original architecture used the browser's native messaging API to communicate between the extension and a Rust native host. The native host handled file storage (writing to `~/.kaya/`) and server sync.

Native messaging proved fundamentally fragile across browsers:

- Chrome's `--user-data-dir` flag (used by WXT dev mode and some user configurations) redirects the NativeMessagingHosts manifest lookup to a temp directory, breaking host discovery
- Even with system-wide manifest installation, Chrome closes the native messaging pipe within milliseconds
- MV3 service worker suspension (Chrome suspends after ~30s of inactivity) compounds the problem, as the background script may be terminated before the native host can respond
- Each browser has different manifest formats, file locations, and registration mechanisms, creating a large surface area for failures

These issues would directly impact end users, not just developers.

## Decision

The browser extension is now self-sufficient:

1. **OPFS** (Origin Private File System) stores anga and meta files locally within the browser's sandboxed storage. OPFS provides a real directory/file hierarchy with the same filenames used on disk and on the server.

2. **Direct HTTP sync** from the extension to the Save Button Server using `fetch()` with HTTP Basic Auth. The sync logic (diff server listing against local, download missing, upload local-only) runs entirely in the extension's background script.

3. **Optional daemon** on `localhost:21420` receives copies of files from the extension for users who want disk-level access to `~/.kaya/`. The daemon is a standalone HTTP server, not a native messaging host. If it's not running, the extension works identically -- it just doesn't mirror files to disk.

OPFS is available in Chrome 86+, Firefox 111+, and Safari 15.2+. The async `createWritable()` API works in MV3 service workers.

## Status

Accepted.

## Consequences

- The extension no longer requires any native binary to function. Users install only the browser extension.
- OPFS data is deleted when the extension is uninstalled. The server is the durable store.
- The daemon becomes optional, simplifying the user experience for most people.
- The `nativeMessaging` permission is no longer needed, which simplifies store review.
- Sync scheduling uses `chrome.alarms` (1-minute minimum interval), which survives MV3 service worker suspension.
