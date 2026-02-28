# Releasing Extensions to Browser Stores

Save Button is published to four browser stores. This document covers the full release process.

## Quick Reference

| Store | Dashboard | GitHub Action |
|---|---|---|
| Chrome Web Store | [Developer Dashboard](https://chrome.google.com/webstore/devconsole) | [mnao305/chrome-extension-upload@v5](https://github.com/mnao305/chrome-extension-upload) |
| Edge Add-ons | [Partner Center](https://partner.microsoft.com/dashboard/microsoftedge/) | [wdzeng/edge-addon@v2](https://github.com/wdzeng/edge-addon) |
| Firefox AMO | [AMO Developer Hub](https://addons.mozilla.org/en-US/developers/) | `wxt submit` / `web-ext sign` |
| Safari / App Store | [App Store Connect](https://appstoreconnect.apple.com/) | `build-safari` job in `release.yml` |

## How Releases Work

1. Run `ruby bin/release.rb` -- this bumps the version in `extension/package.json`, commits, tags (e.g. `v0.1.1`), and pushes.
2. The `v*.*.*` tag triggers the GitHub Actions workflow (`.github/workflows/release.yml`).
3. The workflow builds the extension for all four browsers, runs tests, and then:
   - Uploads the Chrome zip to the Chrome Web Store
   - Uploads the Edge zip to Edge Add-ons
   - Uploads the Firefox zip to AMO
   - Builds, archives, and uploads the Safari extension to App Store Connect
   - Creates a GitHub Release with all artifacts (extension zips, daemon binaries, Linux packages)
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
3. Configure OAuth consent screen (External, scope: `https://www.googleapis.com/auth/chromewebstore`). Under Audience, set publishing status to **Production** (Testing mode tokens expire after 7 days).
4. Create an OAuth 2.0 Client ID (Desktop app or Web application). Desktop apps support `http://localhost` redirects by default; for Web application type, add `http://localhost` as an authorized redirect URI.
5. Generate a refresh token:
   ```
   # 1. Get auth code (open in browser):
   https://accounts.google.com/o/oauth2/auth?response_type=code&scope=https://www.googleapis.com/auth/chromewebstore&client_id=YOUR_CLIENT_ID&redirect_uri=http://localhost&access_type=offline&prompt=consent

   # 2. The browser redirects to http://localhost?code=XXXX&scope=...
   #    The page won't load (nothing is listening). Copy the code= value from the URL bar.

   # 3. Exchange for refresh token:
   curl -X POST "https://oauth2.googleapis.com/token" \
     -d "client_id=YOUR_CLIENT_ID" \
     -d "client_secret=YOUR_CLIENT_SECRET" \
     -d "code=YOUR_AUTH_CODE" \
     -d "grant_type=authorization_code" \
     -d "redirect_uri=http://localhost"
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

### Safari / App Store

All base64 values should be encoded without line breaks (`base64 -w 0` on Linux, `base64` on macOS).

| Secret | Description |
|---|---|
| `APPLE_TEAM_ID` | Apple Developer Team ID (e.g. `FDPGS97G76`) |
| `APPLE_CERTIFICATE_BASE64` | Distribution certificate ("Apple Distribution") exported as `.p12`, then base64-encoded |
| `APPLE_CERTIFICATE_PASSWORD` | Password set when exporting the distribution `.p12` file |
| `APPLE_DEV_CERTIFICATE_BASE64` | Development certificate ("Apple Development") exported as `.p12`, then base64-encoded |
| `APPLE_DEV_CERTIFICATE_PASSWORD` | Password set when exporting the development `.p12` file |
| `APPLE_PROVISION_PROFILE_APP_BASE64` | Provisioning profile for `org.savebutton.safari` (the container app), base64-encoded |
| `APPLE_PROVISION_PROFILE_EXT_BASE64` | Provisioning profile for `org.savebutton.safari.Extension` (the extension), base64-encoded |
| `APP_STORE_API_KEY` | App Store Connect API Key ID |
| `APP_STORE_API_ISSUER` | App Store Connect API Issuer ID |
| `APP_STORE_API_KEY_BASE64` | The `.p8` private key file from App Store Connect, base64-encoded |

**How to get the certificates and profiles:**

All of these steps must be done on a Mac.

1. **Distribution certificate** (`APPLE_CERTIFICATE_BASE64`, `APPLE_CERTIFICATE_PASSWORD`):
   - Open **Keychain Access**, find your "Apple Distribution" certificate
   - Right-click > **Export Items...** > save as `.p12` (you'll set a password)
   - Encode: `base64 < Distribution.p12 | pbcopy`

2. **Development certificate** (`APPLE_DEV_CERTIFICATE_BASE64`, `APPLE_DEV_CERTIFICATE_PASSWORD`):
   - Open **Keychain Access**, find your "Apple Development" certificate
   - Right-click > **Export Items...** > save as `.p12` (you'll set a password)
   - Encode: `base64 < Development.p12 | pbcopy`

3. **Provisioning profiles** (`APPLE_PROVISION_PROFILE_APP_BASE64`, `APPLE_PROVISION_PROFILE_EXT_BASE64`):
   - Go to the [Apple Developer portal](https://developer.apple.com/account/resources/profiles/list) > Certificates, Identifiers & Profiles > Profiles
   - Download (or create) two **Mac App Store** distribution profiles:
     - One for App ID `org.savebutton.safari` (the container app)
     - One for App ID `org.savebutton.safari.Extension` (the extension)
   - Encode each: `base64 < SaveButton_App.provisionprofile | pbcopy`

4. **App Store Connect API key** (`APP_STORE_API_KEY`, `APP_STORE_API_ISSUER`, `APP_STORE_API_KEY_BASE64`):
   - Go to [App Store Connect > Users and Access > Integrations > Keys](https://appstoreconnect.apple.com/access/integrations/api)
   - Create a new key with **App Manager** or **Admin** role
   - Note the **Key ID** (`APP_STORE_API_KEY`) and **Issuer ID** (`APP_STORE_API_ISSUER`) shown on the page
   - Download the `.p8` file (only available once!)
   - Encode: `base64 < AuthKey_XXXXXX.p8 | pbcopy`

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

### Edge Add-ons -- First Submission

1. Build: `cd extension && pnpm zip:edge`
2. Go to [Partner Center](https://partner.microsoft.com/dashboard/microsoftedge/), click "Create new extension"
3. Upload the zip from `extension/.output/`
4. Fill in listing using `doc/stores/listing.md`, screenshots, icon `store-icon-300.png`
5. Submit for review
6. Note the **product ID** and add it as the `EDGE_PRODUCT_ID` secret
7. Generate API credentials (Partner Center > Publish API) and add as secrets

---

### Safari / App Store -- First Submission

Safari extensions are packaged as macOS/iOS apps via Xcode. The Xcode project lives in `safari/Save Button/`.

1. Build the WXT output: `bin/build-safari.sh`
2. Open in Xcode: `open "safari/Save Button/Save Button.xcodeproj"`
3. Configure signing: Select your Apple Developer team for all 4 targets, enable automatic signing
4. Register App IDs in App Store Connect:
   - `org.savebutton.safari` (container app)
   - `org.savebutton.safari.Extension` (web extension target)
5. Add App Group capability: `group.org.savebutton` to both container and extension targets
6. Product > Archive (select "Any Mac" or specific iOS device/simulator)
7. In the Organizer: Distribute App > App Store Connect
8. In [App Store Connect](https://appstoreconnect.apple.com/):
   - Create a new app listing for "Save Button" under Productivity
   - Set platforms to macOS + iOS
   - Fill in description from `doc/stores/listing.md`
   - Upload screenshots from Safari (macOS) and iOS Safari
   - Set pricing to Free
   - Submit for review

**Bundle identifiers:**
- Container app: `org.savebutton.safari`
- Extension: `org.savebutton.safari.Extension`

**Deployment targets:**
- macOS 12.0 (Safari 15.2+ for OPFS support)
- iOS 16.0 (Safari 16+ for OPFS support)

---

## Updating Store Submissions

After `release.yml` completes, Firefox submissions are fully automatic. Chrome and Edge may each require a manual step. Safari always requires manual submission.

### Chrome Web Store

The CI workflow uploads the zip and auto-publishes (submits for review). This is usually automatic, but the Chrome Web Store only allows **one version in review at a time**. If a previous version is still being reviewed, CI will upload the new zip as a **draft** but the publish step will fail silently (`continue-on-error: true`). When this happens:

1. Wait for the current review to complete (typically 1-3 days)
2. Go to the [Chrome Developer Dashboard](https://chrome.google.com/webstore/devconsole) and open Save Button
3. If the latest draft hasn't been auto-submitted, click **Submit for review**

If multiple releases land while a review is pending, only the latest draft needs to be submitted -- older drafts can be discarded.

### Edge Add-ons

The CI workflow uploads and submits automatically, but Edge also only allows **one version in review at a time**. If a previous version is still in review when a new version is uploaded, the new version will remain as a draft. When this happens, cancel the stale in-review submission and submit the latest draft instead -- there's no value in reviewing an old version that will be immediately superseded.

1. Go to [Partner Center](https://partner.microsoft.com/dashboard/microsoftedge/) and open Save Button
2. Cancel the submission for the older in-review version
3. Click **Submit for review** on the latest draft

### Safari / App Store

The CI workflow uploads the build to App Store Connect, where it appears in TestFlight. It will not be submitted for App Store review automatically. To submit:

1. Go to [App Store Connect](https://appstoreconnect.apple.com/) > Apps > Save Button
2. In the sidebar under "App Store", click `+` next to the platform and create a new version (e.g. `1.2.15`)
3. Scroll to the **Build** section and click `+` to select the build uploaded by CI
4. Fill in the **What's New** text and verify all required metadata is present
5. Save the page (required before uploading screenshots for a new locale)
6. Click **Add for Review** (top-right)
7. Click **Submit for Review**

## Updating Store Listings

To update descriptions, screenshots, or other listing metadata, do so directly in each store's dashboard. The automated workflow only uploads new extension zips -- it does not update listing text or images.

## Troubleshooting

- **Chrome publish fails with 401**: The refresh token may have expired. Regenerate it using the OAuth flow above.
- **Edge publish fails with 500**: The Edge API is occasionally unreliable. Retry the workflow or upload manually via Partner Center.
- **Firefox submit fails**: AMO may not support fully automated listed signing. The extension will be submitted for review rather than auto-published. Check the [AMO Developer Hub](https://addons.mozilla.org/en-US/developers/) for status.
- **Review rejection**: Check store-specific feedback. Common issues: permissions justification not detailed enough, missing privacy policy, screenshots not showing actual functionality.
