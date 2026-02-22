# ADR 0005: Full Text Search

## Context

Because Kaya aims to be local-first, local search needs to be possible on all edge devices.

## Decision

Kaya WXT will keep a plaintext copy of bookmarks, PDFs, and other anga which are difficult to search directly. These plaintext copies will be stored in `/kaya/words` (OPFS for browser extension) or `~/.kaya/words/` (daemon/nativehost), according to the following layout:

* `/kaya/words/`                      = `~/.kaya/words/` = root
* `/kaya/words/{bookmark}`            = `~/.kaya/words/{bookmark}` = bookmark root
* `/kaya/words/{bookmark}/{filename}` = `~/.kaya/words/{bookmark}/{filename}` = plaintext bookmark contents
* `/kaya/words/{pdf}`                 = `~/.kaya/words/{pdf}` = pdf root
* `/kaya/words/{pdf}/{filename}`      = `~/.kaya/words/{pdf}/{filename}` = plaintext pdf contents
* etc.

These three patterns are symmetrical to the 3 routes Kaya Server exposes:

* `/api/v1/:user_email/words`
* `/api/v1/:user_email/words/:anga`
* `/api/v1/:user_email/words/:anga/:filename`

When the user creates a new anga, whether directly or indirectly (via sync), Kaya Server enqueues a background job to transform it into a plaintext copy. For now, Kaya WXT does not transform anga into plaintext copies for search on its own, so these plaintext copies are sync'd from Kaya Server.

**API Mapping:**

These use the home directory root (used by the daemon) as an example, but apply equally to `/kaya/words` for the browser extension and OPFS.

* `~/.kaya/words/` <=> `/api/v1/:user_email/words`
* `~/.kaya/words/{anga}` <=> `/api/v1/:user_email/words/:anga`
* `~/.kaya/words/{anga}/{filename}` <=> `/api/v1/:user_email/words/:anga/:filename`

## Status

Accepted.

## Consequences

Cached contents for Full Text Search over both bookmarks and PDFs will allow both local search and server-side search to be much faster. These text files are also human-readable, which means they are useful directly to the user and can also be consumed by other tools.
