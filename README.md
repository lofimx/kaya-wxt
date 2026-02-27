# kaya-wxt

Kaya browser extensions

## Browser Support

* Firefox
* Chrome
* Edge
* Safari (macOS, iOS, iPadOS)
* Orion (via Firefox or Chrome)
* Chromium:
  * Vivaldi
  * Brave
  * Arc

## Architecture

The browser extension is self-sufficient: it stores files locally using OPFS (Origin Private File System) and syncs them directly with the Save Button Server over HTTP. An optional local daemon can mirror files to `~/.kaya/` on disk.

Read the [Architecture Decision Records](doc/arch/) for full details.

## Prerequisites

* Node.js 24 (managed via [mise](https://mise.jdx.dev/))
* PNPM

## Development

```bash
cd extension
pnpm install
pnpm dev:chrome    # Chrome with hot reload
pnpm dev:firefox   # Firefox with hot reload
```

### Safari

Safari requires an Xcode project wrapping the web extension. The Xcode project lives in `safari/` and references the WXT build output at `extension/.output/safari-mv2/`.

```bash
bin/build-safari.sh                  # build WXT output (required before Xcode build)
open "safari/Save Button/Save Button.xcodeproj"  # open in Xcode, then build & run
```

To regenerate the Xcode project from scratch (e.g. after changing entrypoints):

```bash
bin/build-safari.sh --regen
```

### Optional Daemon

The daemon is not required for development or normal use. To run it:

```bash
cd daemon
cargo build --release
./target/release/savebutton-daemon
# Listens on localhost:21420
```

## Release

To release a new version:

```bash
ruby bin/release.rb
```

This bumps the patch version in `extension/package.json`, commits, tags (e.g. `v0.1.1`), and pushes. The tag triggers the GitHub Actions workflow which builds the extension for Firefox, Chrome, and Edge, runs tests, publishes to all three browser stores, and creates a GitHub Release with all artifacts.

Safari releases are submitted manually via Xcode Archive and App Store Connect (see [doc/stores/STORES.md](doc/stores/STORES.md)).

For detailed store setup, secrets configuration, and first-time submission instructions, see [doc/stores/STORES.md](doc/stores/STORES.md).

## Safari: Manual Tasks

These steps must be completed in Xcode and App Store Connect before the Safari extension can be distributed.

### One-time Xcode setup

1. Open the project: `open "safari/Save Button/Save Button.xcodeproj"`
2. Select your Apple Developer team for all 4 targets (iOS app, macOS app, iOS extension, macOS extension) and enable automatic signing
3. Register App IDs in the Apple Developer portal:
   - `org.savebutton.safari` (container app)
   - `org.savebutton.safari.Extension` (web extension)
4. Add the **App Groups** capability (`group.org.savebutton`) to both the container app and extension targets on both platforms so they can share data with the full iOS app

### Local testing

**macOS:**
1. Select the "Save Button (macOS)" scheme, press Cmd+R
2. Safari > Settings > Extensions > enable "Save Button"
3. Test: bookmark a page, save text via context menu, save an image, verify sync
4. Check Safari Web Inspector for console errors in the extension background page

**iOS (Simulator or device):**
1. Select the "Save Button (iOS)" scheme, choose a simulator or connected device
2. Build and run
3. Settings > Safari > Extensions > enable "Save Button"
4. Open Safari, test bookmarking and context menu actions

### App Store submission

1. Product > Archive (select "Any Mac" for macOS, or a device/simulator for iOS)
2. In the Organizer window: Distribute App > App Store Connect
3. In App Store Connect:
   - Create a new app listing for "Save Button" under Productivity
   - Set platforms to macOS + iOS
   - Fill in description from `doc/stores/listing.md`
   - Upload screenshots from Safari (macOS) and iOS Safari
   - Set pricing to Free
   - Submit for review

See [doc/stores/STORES.md](doc/stores/STORES.md) for full details.

## Open Questions

* Ladybird and Servo Browser support in the future?
* "Unsaved" icon: should it just be an outline, instead of grayscale?

## TODO

* [x] First submission to Chrome Web Store (update Chrome Extension ID after publish)
* [x] First submission to Edge Add-ons (update Edge Extension ID after publish)
* [x] Configure GitHub repository secrets for automated store publishing
* [ ] Automate Safari CI: add the following secrets to the GitHub repo, then Safari builds and App Store uploads will be fully automated

### Safari CI Secrets

These secrets must be added at **Settings > Secrets and variables > Actions** in the GitHub repo. All base64 values should be encoded without line breaks (`base64 -w 0` on Linux, `base64` on macOS).

| Secret                                | Description                                                                              |
|---------------------------------------|------------------------------------------------------------------------------------------|
| `APPLE_TEAM_ID`                       | Apple Developer Team ID (e.g. `FDPGS97G76`)                                             |
| `APPLE_CODE_SIGN_IDENTITY`            | Signing identity, e.g. `Apple Distribution: Your Name (FDPGS97G76)`                     |
| `APPLE_CERTIFICATE_BASE64`            | Distribution certificate exported as `.p12`, then base64-encoded                         |
| `APPLE_CERTIFICATE_PASSWORD`          | Password set when exporting the `.p12` file                                              |
| `APPLE_PROVISION_PROFILE_APP_BASE64`  | Provisioning profile for `org.savebutton.safari` (the container app), base64-encoded     |
| `APPLE_PROVISION_PROFILE_EXT_BASE64`  | Provisioning profile for `org.savebutton.safari.Extension` (the extension), base64-encoded |
| `APP_STORE_API_KEY`                   | App Store Connect API Key ID                                                             |
| `APP_STORE_API_ISSUER`                | App Store Connect API Issuer ID                                                          |
| `APP_STORE_API_KEY_BASE64`            | The `.p8` private key file from App Store Connect, base64-encoded                        |

### How to get the certificate and profiles

All of these steps must be done on a Mac.

1. **Distribution certificate** (`APPLE_CERTIFICATE_BASE64`, `APPLE_CERTIFICATE_PASSWORD`):
   - Open **Keychain Access**, find your "Apple Distribution" certificate
   - Right-click > **Export Items...** > save as `.p12` (you'll set a password)
   - Encode: `base64 < Certificates.p12 | pbcopy`

2. **Provisioning profiles** (`APPLE_PROVISION_PROFILE_APP_BASE64`, `APPLE_PROVISION_PROFILE_EXT_BASE64`):
   - Go to the [Apple Developer portal](https://developer.apple.com/account/resources/profiles/list) > Certificates, Identifiers & Profiles > Profiles
   - Download (or create) two **Mac App Store** distribution profiles:
     - One for App ID `org.savebutton.safari` (the container app)
     - One for App ID `org.savebutton.safari.Extension` (the extension)
   - Encode each: `base64 < SaveButton_App.provisionprofile | pbcopy`

3. **App Store Connect API key** (`APP_STORE_API_KEY`, `APP_STORE_API_ISSUER`, `APP_STORE_API_KEY_BASE64`):
   - Go to [App Store Connect > Users and Access > Integrations > Keys](https://appstoreconnect.apple.com/access/integrations/api)
   - Create a new key with **App Manager** or **Admin** role
   - Note the **Key ID** (`APP_STORE_API_KEY`) and **Issuer ID** (`APP_STORE_API_ISSUER`) shown on the page
   - Download the `.p8` file (only available once!)
   - Encode: `base64 < AuthKey_XXXXXX.p8 | pbcopy`
