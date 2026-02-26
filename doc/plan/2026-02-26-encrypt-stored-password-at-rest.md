# Plan: Encrypt Stored Password at Rest

## Context

The Save Button extension stores the user's server password in plaintext in `browser.storage.local`. While `browser.storage.local` is sandboxed per-extension (other extensions cannot read it), the plaintext password is exposed to:
- Disk forensics / stolen laptop (browser profile database files are readable)
- Pattern-scanning malware looking for `password=` in plaintext files
- Inadvertent backup/cloud sync of browser profile directories
- Browser sync features that replicate `storage.local` to the cloud

The daemon already encrypts the password at rest (AES-256-GCM with a co-located key in `~/.kaya/.config`). The extension should provide at least the same level of protection.

Additionally, the popup and options pages bypass `config.ts` and write directly to `browser.storage.local`, which complicates any centralized change. This plan addresses both the encryption and the direct-access problem.

---

## Recommended Approach: AES-256-GCM with Co-located Key

Generate a random AES-256-GCM key on first setup. Encrypt the password with a fresh random IV each time it's saved. Store `{ iv, ciphertext, key(JWK) }` in `browser.storage.local`. The plaintext password is never stored on disk.

**Why not PBKDF2?** PBKDF2 stretches weak human-chosen passwords. Here the key is randomly generated at full entropy -- PBKDF2 adds complexity without benefit.

**Why co-located key (key stored alongside ciphertext)?** A key stored separately (e.g., `browser.storage.session`) would provide stronger protection but requires re-authentication after every browser restart on MV3, and `browser.storage.session` doesn't exist on Firefox MV2. The co-located approach matches the daemon's model and protects against pattern scanners and casual inspection without UX disruption.

**What about `browser.storage.session`?** Could be added later as an opt-in "high security" mode. Not included in this initial plan to keep cross-browser behavior consistent and avoid surprising users with re-authentication prompts.

**Should email be encrypted?** No. The email is sent in cleartext in API URL paths (`/api/v1/{email}/anga`) and is not a secret.

### Threat Model Summary

| Threat | Plaintext | Co-located Key | Session Key (future) |
|--------|-----------|---------------|---------------------|
| Other extensions reading storage | Protected (browser sandbox) | Protected | Protected |
| Pattern-scanning malware | Exposed | Protected | Protected |
| Disk forensics (full profile access) | Exposed | Not protected (key is on disk too) | Protected |
| Browser restart UX | No change | No change | Must re-enter password |

---

## Plan Alternative: `browser.storage.session` Hybrid

Store the AES key in `browser.storage.session` (MV3 only, memory-only). On MV2 (Firefox), fall back to `browser.storage.local`. This provides real disk-at-rest protection on Chrome/Edge/Safari but requires MV3 users to re-enter their password after every browser restart. **Not recommended as the default** due to UX cost, but could be offered as a "high security" toggle in a future iteration.

---

## Implementation

### Step 1: Create `extension/utils/crypto.ts`

New utility module encapsulating all encryption/decryption:
- `encryptPassword(password: string)` -- generates key if needed, encrypts with random IV, stores `{ iv, ciphertext, key(JWK) }` in `browser.storage.local`, removes any plaintext `password` key
- `decryptPassword(): string | null` -- retrieves key, decrypts, returns plaintext or `null` if unavailable
- Internal helpers: `generateKey()`, `exportKey()`, `importKey()`, `storeKey()`, `retrieveKey()`
- Uses Web Crypto API (`crypto.subtle`) -- available in all extension contexts without permissions

Storage keys used: `encryptedPassword`, `passwordIv`, `cryptoKey` (all in `browser.storage.local`).

### Step 2: Modify `extension/utils/config.ts`

- `saveConfig()`: when `config.password` is provided, call `encryptPassword()` instead of storing plaintext
- `loadConfig()`: call `decryptPassword()` to get the plaintext password; if that returns `null`, check for legacy plaintext `password` in storage and migrate it transparently
- The returned `Config` object still has a plaintext `password` field for runtime use by `sync.ts` and `daemon.ts` (unchanged)

### Step 3: Modify `extension/entrypoints/popup/main.ts`

Replace 2 direct `browser.storage.local` calls:
- `checkConfigured()` (line 74): use `isConfigured()` from config.ts
- `saveSetup()` (line 122): use `saveConfig()` from config.ts

### Step 4: Modify `extension/entrypoints/options/main.ts`

Replace 4 direct `browser.storage.local` calls:
- `loadSettings()` (line 25): use `loadConfig()` from config.ts
- `saveSettings()` (line 72): use `saveConfig()` from config.ts
- `saveSettings()` (line 75): use `loadConfig()` for daemon push
- `doTestConnection()` (line 108): use `loadConfig()` for password retrieval

### Step 5: Test

- Fresh install: first-run setup encrypts password
- Existing install: migration from plaintext happens transparently on first `loadConfig()`
- Options page: loads/displays/saves correctly
- Sync and daemon push: work with decrypted password
- Inspect `browser.storage.local` to confirm no plaintext `password` key exists
- Build for both Firefox (MV2) and Chrome (MV3)

---

## Files Changed

| File | Action |
|------|--------|
| `extension/utils/crypto.ts` | **Create** -- AES-256-GCM encrypt/decrypt, key management |
| `extension/utils/config.ts` | **Modify** -- integrate encryption, add migration |
| `extension/entrypoints/popup/main.ts` | **Modify** -- route storage through config.ts |
| `extension/entrypoints/options/main.ts` | **Modify** -- route storage through config.ts |

No changes to `background.ts`, `sync.ts`, or `daemon.ts` -- they already consume `Config.password` as plaintext from `loadConfig()`.
