# Adjustments: OPFS Root, Daemon Config Endpoint, Words Sync

**Date**: 2026-02-22
**Parent**: `doc/plan/2026-02-22-r-opfs-storage-and-optional-daemon.md`

These adjustments follow the OPFS + optional daemon refactor.

---

## 1. OPFS Root: `/kaya`

Currently `opfs.ts` uses the raw OPFS root for `anga/` and `meta/`. Change it so all extension storage lives under a `/kaya` parent directory, matching the daemon's `~/.kaya/` layout.

**Changes:**

- `extension/utils/opfs.ts`: `getRoot()` returns a `kaya` subdirectory handle instead of the raw OPFS root:
  ```typescript
  async function getRoot(): Promise<FileSystemDirectoryHandle> {
    const opfsRoot = await navigator.storage.getDirectory();
    return opfsRoot.getDirectoryHandle("kaya", { create: true });
  }
  ```
- No other files change. All callers use `getRoot()` -> `ensureDir()` -> file operations, so the `/kaya` prefix is transparent.

**Result:** OPFS layout becomes `/kaya/anga/`, `/kaya/meta/`, `/kaya/words/` -- symmetrical with `~/.kaya/anga/`, `~/.kaya/meta/`, `~/.kaya/words/`.

---

## 2. `POST /config` Daemon Endpoint

The extension stores config in `browser.storage.local`. The daemon reads config from `~/.kaya/.config`. Currently there's no way for the extension to push config to the daemon. Add a `POST /config` endpoint.

**Daemon changes (`daemon/src/main.rs`):**

- New route: `POST /config` accepts JSON body:
  ```json
  { "server": "https://savebutton.com", "email": "user@example.com", "password": "plaintext" }
  ```
- Handler calls existing `encrypt_password()` + `save_config()` (currently dead code, now live)
- Responds 200 on success, 400/500 on error

**Extension changes (`extension/utils/daemon.ts`):**

- New function: `pushConfigToDaemon(config: Config)` -- POSTs JSON to `http://localhost:21420/config`
- Silently ignores failures (daemon is optional)

**Extension changes (`extension/entrypoints/options/main.ts`):**

- After saving config to `browser.storage.local`, also call `pushConfigToDaemon(config)`

**Extension changes (`extension/entrypoints/background.ts`):**

- On each periodic sync alarm, if daemon is running, push config (in case daemon started after user configured extension)

**AGENTS.md:**

- Add `POST /config` to the daemon HTTP API documentation

---

## 3. Daemon Log Path

Change daemon log path from `~/.kaya/log` to `~/.kaya/daemon-log`.

**Changes:**

- `daemon/src/main.rs`: `setup_logging()` changes `get_kaya_dir().join("log")` to `get_kaya_dir().join("daemon-log")`
- `AGENTS.md`: Update "Logging" section

---

## 4. AUR Mention

Add AUR to the packaging list in `AGENTS.md`.

**Changes:**

- `AGENTS.md`: In the daemon Packaging section, change "DEB, RPM" to "DEB, RPM, AUR"

---

## 5. Words Sync (ADR-0005)

Sync plaintext word files from the server. Words are **download-only** -- the server generates them via background jobs. The directory structure is nested: `words/{anga}/{filename}`.

### 5a. OPFS Words Support (`extension/utils/opfs.ts`)

Add functions for the nested words directory structure:

- `ensureWordsDir(anga: string)` -- ensures `/kaya/words/{anga}/` exists
- `writeWordsFile(anga: string, filename: string, content: string)` -- writes a file under `/kaya/words/{anga}/{filename}`
- `listWordsAngaDirs()` -- lists subdirectory names under `/kaya/words/`
- `listWordsFiles(anga: string)` -- lists filenames under `/kaya/words/{anga}/`

### 5b. Extension Sync (`extension/utils/sync.ts`)

Add `syncWords(config)`:

1. `GET /api/v1/{email}/words` -- returns newline-separated anga directory names
2. For each anga dir, `GET /api/v1/{email}/words/{anga}` -- returns newline-separated filenames
3. Diff against local OPFS listing; download missing files with `GET /api/v1/{email}/words/{anga}/{filename}`
4. **No uploads** -- words are server-generated

Update `syncWithServer()` to also call `syncWords()`. Update `SyncResult` type to include words stats.

### 5c. Daemon Words Sync (`daemon/src/main.rs`)

Add to the daemon's server sync cycle:

1. `sync_words()` function: `GET /api/v1/{email}/words` lists anga dirs, then for each, `GET /api/v1/{email}/words/{anga}` lists files, downloads missing to `~/.kaya/words/{anga}/{filename}`
2. `get_words_dir()` -> `~/.kaya/words/`
3. `ensure_directories()` also creates `~/.kaya/words/`
4. **Download-only** -- no uploads

Add HTTP API routes for the extension to push words to the daemon (optional mirroring):

- `GET /words` -- list anga subdirectories
- `GET /words/{anga}` -- list files in an anga subdir
- `POST /words/{anga}/{filename}` -- write file to `~/.kaya/words/{anga}/{filename}`

### 5d. Daemon Client (`extension/utils/daemon.ts`)

Add `pushWordsFileToDaemon(anga: string, filename: string, content: string)` for optional mirroring after download.

### 5e. Background Script (`extension/entrypoints/background.ts`)

After `syncWords()` downloads new words files, push them to the daemon if running.

### 5f. Documentation

- `AGENTS.md`: Add words/FTS section under Storage, update daemon HTTP API list, mention words sync in Sync section

---

## Implementation Order

1 -> 3 -> 4 -> 2 -> 5

Items 1, 3, 4 are small and independent. Item 2 (config endpoint) is medium. Item 5 (words) is the largest and depends on item 1 (OPFS root).

## Questions

1. **Config push timing**: Should the extension push config to the daemon only when the user saves settings (options page), or also on every periodic sync alarm (to cover the case where the daemon starts after the user has already configured the extension)? The plan currently says both.

2. **Daemon words sync**: Should the daemon's own 60-second server sync cycle also sync words (download-only from server to `~/.kaya/words/`)? The plan currently says yes.
