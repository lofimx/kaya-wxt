# Refactor: OPFS Storage and Direct HTTP Sync, Optional Native Daemon

**Date**: 2026-02-22

## Context

Native messaging between the browser extension and the Rust host has proven fundamentally fragile:

- Chrome's `--user-data-dir` (used by WXT dev mode) redirects NativeMessagingHosts lookup to a temp directory, breaking manifest discovery
- Even after installing system-wide manifests, Chrome closes the native messaging pipe within ~17ms
- MV3 service workers compound the problem: Chrome suspends the background script before the native host can respond
- This unreliability would directly impact end users across all Chromium browsers

The solution is to move the extension to a self-sufficient architecture: **OPFS** (Origin Private File System) for local file storage, **direct HTTP sync** from the extension to the Save Button Server, and an **optional** standalone native daemon that mirrors files to `~/.kaya/` for users who want local disk copies.

## Architecture Overview

```
Browser Extension (self-sufficient)
  |-- OPFS: stores anga/ and meta/ as real files with real filenames
  |-- HTTP Sync: syncs OPFS <-> Save Button Server via fetch()
  |-- Daemon Client (optional): pushes copies to localhost daemon
  
Optional Native Daemon (standalone binary)
  |-- HTTP server on localhost (e.g. port 21420)
  |-- Receives files from extension, writes to ~/.kaya/
  |-- Can also sync with server independently
```

The extension no longer depends on native messaging. It works fully without the daemon.

## Phase 1: OPFS Storage Layer

Create `extension/utils/opfs.ts` providing a thin wrapper over the OPFS async API:

- `getRoot()` -- returns the OPFS root `FileSystemDirectoryHandle`
- `ensureDir(name)` -- ensures `anga/` or `meta/` subdirectory exists
- `writeFile(dir, filename, content: string | ArrayBuffer)` -- creates or overwrites a file
- `readFile(dir, filename)` -- returns file content
- `listFiles(dir)` -- returns array of filenames
- `readAllBookmarkUrls()` -- scans `anga/*.url` files, extracts URLs (replaces `get_all_bookmarked_urls()` from Rust)

OPFS is accessed via `navigator.storage.getDirectory()` in the service worker. The async `FileSystemWritableFileStream` API (`createWritable()`) works in service workers (Chrome 86+, Firefox 111+).

**Files**: New `extension/utils/opfs.ts`

## Phase 2: HTTP Sync Client

Create `extension/utils/sync.ts` implementing the same sync logic currently in `nativehost/src/main.rs` (and `bin/sync.rb`):

- `syncWithServer(config)` -- top-level entry point
- `syncCollection(config, collection: "anga" | "meta")` -- fetches server file listing, diffs against OPFS, downloads missing, uploads local-only
- `downloadFile(config, collection, filename)` -- writes to OPFS
- `uploadFile(config, collection, filename)` -- reads from OPFS, uploads as multipart form-data
- Uses `fetch()` with HTTP Basic Auth

Create `extension/utils/config.ts`:
- `loadConfig()` -- reads server, email, password from `browser.storage.local`
- `saveConfig(config)` -- writes to `browser.storage.local`

Sync scheduling via `chrome.alarms` (1-minute interval) + immediate sync after each save.

**Files**: New `extension/utils/sync.ts`, new `extension/utils/config.ts`

## Phase 3: Rewire Background Script

Rewrite `extension/entrypoints/background.ts` to use OPFS + HTTP sync instead of native messaging.

**Files**: Modified `extension/entrypoints/background.ts`

## Phase 4: Rewire Popup and Options

Update popup and options pages to use `browser.storage.local` + background script messages instead of native messaging.

**Files**: Modified `extension/entrypoints/popup/main.ts`, `extension/entrypoints/options/main.ts`

## Phase 5: Optional Daemon Communication

Create `extension/utils/daemon.ts` for optional localhost daemon communication.

**Files**: New `extension/utils/daemon.ts`

## Phase 6: Refactor Rust Binary into Standalone Daemon

Transform `nativehost/` into a standalone HTTP daemon. Rename to `daemon/`.

**Files**: Renamed `nativehost/` -> `daemon/`, modified `daemon/src/main.rs`

## Phase 7: Update Manifest and Packaging

Remove `nativeMessaging` permission, add `alarms`. Update CI/CD paths.

**Files**: Modified `extension/wxt.config.ts`, `.github/workflows/release.yml`, packaging scripts

## Phase 8: Update Documentation

Update AGENTS.md, README.md. New ADR for OPFS decision.

**Files**: Modified `AGENTS.md`, `README.md`, new `doc/arch/adr-0004-opfs-storage.md`
