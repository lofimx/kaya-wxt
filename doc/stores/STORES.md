# Releasing Extensions to Browser Stores

Save Button is published to three browser extension stores. This document covers the full release process.

## Quick Reference

| Store | Dashboard | GitHub Action |
|---|---|---|
| Chrome Web Store | [Developer Dashboard](https://chrome.google.com/webstore/devconsole) | [mnao305/chrome-extension-upload@v5](https://github.com/mnao305/chrome-extension-upload) |
| Edge Add-ons | [Partner Center](https://partner.microsoft.com/dashboard/microsoftedge/) | [wdzeng/edge-addon@v2](https://github.com/wdzeng/edge-addon) |
| Firefox AMO | [AMO Developer Hub](https://addons.mozilla.org/en-US/developers/) | `wxt submit` / `web-ext sign` |

## How Releases Work

1. Run `ruby bin/release.rb` -- this bumps the version in `extension/package.json`, commits, tags (e.g. `v0.1.1`), and pushes.
2. The `v*.*.*` tag triggers the GitHub Actions workflow (`.github/workflows/release.yml`).
3. The workflow builds the extension for all three browsers, runs tests, and then:
   - Uploads the Chrome zip to the Chrome Web Store
   - Uploads the Edge zip to Edge Add-ons
   - Uploads the Firefox zip to AMO
   - Creates a GitHub Release with all artifacts (extension zips, native host binaries, Linux packages)
4. Each store performs its own review before publishing the update.

## Build Artifacts

Extension zips are built by the `build-extension` job in the GitHub Actions workflow. To build locally:

```bash
cd extension
pnpm zip:chrome    # -> .output/save-button-<version>-chrome.zip
pnpm zip:edge      # -> .output/save-button-<version>-edge.zip
pnpm zip:firefox   # -> .output/save-button-<version>-firefox.zip
```

## Store Listing Assets

Assets are checked into `doc/stores/`:

| File | Dimensions | Used by |
|---|---|---|
| `store-icon-128.png` | 128x128 | Chrome Web Store, Firefox AMO |
| `store-icon-300.png` | 300x300 | Edge Add-ons |
| `promo-small-440x280.png` | 440x280 | Chrome Web Store (optional promo tile) |
| `screenshot-*.png` | 1280x800 | All stores |
| `listing.md` | -- | Listing text for all stores |

Regenerate icons and promo images:

```bash
bin/generate-store-assets.sh
```

### Capturing Screenshots

Screenshots must be captured manually:

1. Build and load the extension in dev mode:
   - Chrome/Edge: `cd extension && pnpm dev:chrome`, then go to `chrome://extensions`, enable Developer mode, click "Load unpacked", select `extension/.output/chrome-mv3/`
   - Firefox: `cd extension && pnpm dev:firefox`, WXT auto-loads via `web-ext`
2. Navigate to any website.
3. Click the toolbar button to show the Save Button popup.
4. Capture a 1280x800 screenshot of the browser window.
5. Save as `doc/stores/screenshot-1-popup.png`.
6. Optionally capture more (context menu, options page) as `screenshot-2-*.png`, etc.

All three stores accept 1280x800 screenshots.

---

## GitHub Secrets

The automated publish jobs require these repository secrets (Settings > Secrets and variables > Actions):

### Chrome Web Store

| Secret | Description | How to get it |
|---|---|---|
| `CHROME_EXTENSION_ID` | 32-char extension ID | From the Developer Dashboard URL after first upload |
| `CHROME_CLIENT_ID` | Google OAuth Client ID | Google Cloud Console > APIs & Services > Credentials |
| `CHROME_CLIENT_SECRET` | Google OAuth Client Secret | Same as above |
| `CHROME_REFRESH_TOKEN` | Google OAuth Refresh Token | OAuth flow (see below) |

**Getting Chrome OAuth credentials:**

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a project, enable the **Chrome Web Store API**
3. Configure OAuth consent screen (External, scope: `https://www.googleapis.com/auth/chromewebstore`)
4. Create an OAuth 2.0 Client ID (Desktop app)
5. Generate a refresh token:
   ```
   # 1. Get auth code (open in browser):
   https://accounts.google.com/o/oauth2/auth?response_type=code&scope=https://www.googleapis.com/auth/chromewebstore&client_id=YOUR_CLIENT_ID&redirect_uri=urn:ietf:wg:oauth:2.0:oob

   # 2. Exchange for refresh token:
   curl -X POST "https://oauth2.googleapis.com/token" \
     -d "client_id=YOUR_CLIENT_ID" \
     -d "client_secret=YOUR_CLIENT_SECRET" \
     -d "code=YOUR_AUTH_CODE" \
     -d "grant_type=authorization_code" \
     -d "redirect_uri=urn:ietf:wg:oauth:2.0:oob"
   ```

### Edge Add-ons

| Secret | Description | How to get it |
|---|---|---|
| `EDGE_PRODUCT_ID` | Product ID | From the Partner Center URL after first upload |
| `EDGE_CLIENT_ID` | API Client ID | Partner Center > Publish API > Create API credentials |
| `EDGE_API_KEY` | API Key (v1.1) | Same as above |

### Firefox AMO

| Secret | Description | How to get it |
|---|---|---|
| `AMO_JWT_ISSUER` | JWT issuer key (e.g. `user:12345:67`) | [AMO API keys page](https://addons.mozilla.org/en-US/developers/addon/api/key/) |
| `AMO_JWT_SECRET` | JWT secret (64-char hex) | Same as above |

---

## First-Time Store Submission

Both Chrome and Edge require a manual first submission. Firefox has already been submitted.

### Chrome Web Store -- First Submission

1. Build: `cd extension && pnpm zip:chrome`
2. Go to [Developer Dashboard](https://chrome.google.com/webstore/devconsole), click "New item"
3. Upload the zip from `extension/.output/`
4. Store Listing: use text from `doc/stores/listing.md`, screenshots from `doc/stores/`, icon `store-icon-128.png`
5. Category: Productivity, Language: English
6. Privacy tab: privacy policy URL, permissions justification (see `listing.md`)
7. Submit for review
8. Note the **extension ID** and add it as the `CHROME_EXTENSION_ID` secret
9. Update `nativehost/src/main.rs` `CHROME_ORIGIN_PLACEHOLDER` with the real ID

### Edge Add-ons -- First Submission

1. Build: `cd extension && pnpm zip:edge`
2. Go to [Partner Center](https://partner.microsoft.com/dashboard/microsoftedge/), click "Create new extension"
3. Upload the zip from `extension/.output/`
4. Fill in listing using `doc/stores/listing.md`, screenshots, icon `store-icon-300.png`
5. Submit for review
6. Note the **product ID** and add it as the `EDGE_PRODUCT_ID` secret
7. Generate API credentials (Partner Center > Publish API) and add as secrets
8. Update `nativehost/src/main.rs` with the Edge extension origin

---

## Updating Store Listings

To update descriptions, screenshots, or other listing metadata, do so directly in each store's dashboard. The automated workflow only uploads new extension zips -- it does not update listing text or images.

## Troubleshooting

- **Chrome publish fails with 401**: The refresh token may have expired. Regenerate it using the OAuth flow above.
- **Edge publish fails with 500**: The Edge API is occasionally unreliable. Retry the workflow or upload manually via Partner Center.
- **Firefox submit fails**: AMO may not support fully automated listed signing. The extension will be submitted for review rather than auto-published. Check the [AMO Developer Hub](https://addons.mozilla.org/en-US/developers/) for status.
- **Review rejection**: Check store-specific feedback. Common issues: permissions justification not detailed enough, missing privacy policy, screenshots not showing actual functionality.
