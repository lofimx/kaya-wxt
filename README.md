# kaya-wxt

Kaya browser extensions

## Prerequisites

* Native (non-Flatpak) Chrome: https://linuxcapable.com/how-to-install-google-chrome-on-debian-linux/

## Release

To release a new version:

```bash
ruby bin/release.rb
```

This bumps the patch version in `extension/package.json`, commits, tags (e.g. `v0.1.1`), and pushes. The tag triggers the GitHub Actions workflow which builds the extension for Firefox, Chrome, and Edge, runs tests, publishes to all three browser stores, and creates a GitHub Release with all artifacts.

For detailed store setup, secrets configuration, and first-time submission instructions, see [doc/stores/STORES.md](doc/stores/STORES.md).

## Open Questions

* Switch to OPFS + Webworker in extension? https://youtu.be/rlFJ6AuJX9U?si=XuN31aTyQaeD2HGh&t=419
* Ladybird and Servo Browser support in the future?
* **Flatpak browsers**: Flatpak-sandboxed browsers (increasingly common on Linux) cannot use native messaging because the sandbox prevents spawning host executables. There is an [xdg-desktop-portal NativeMessaging proposal](https://github.com/flatpak/xdg-desktop-portal/issues/655) in progress but it hasn't landed yet. Until it does, Save Button requires a native (non-Flatpak) browser install. If the portal never ships, alternatives include communicating over a local socket (requires running a daemon) or using the browser download API as a file-drop fallback.

## TODO

* [ ] Pin a key for Chrome Extension ID (after first Chrome Web Store publish, update `CHROME_EXTENSION_ORIGIN` in `nativehost/src/main.rs`)
* [ ] Pin a key for Edge Extension ID (after first Edge Add-ons publish, same as above for Edge)

## Temp: Saving Screenshots and First Store Submissions

**Screenshots first.** Before submitting to either store, you'll need at least one 1280x800 screenshot. To capture one:

1. Load the extension in Chrome: `cd extension && pnpm dev:chrome`, then go to `chrome://extensions`, enable Developer mode, load unpacked from `extension/.output/chrome-mv3/`
2. Navigate to any website, click the toolbar button
3. Capture a 1280x800 screenshot of the browser window
4. Save it as `doc/stores/screenshot-1-popup.png`

---

**Then, Chrome Web Store submission** (Phase 2 of the plan):

1. Build the zip: `cd extension && pnpm zip:chrome`
2. Go to [Chrome Web Store Developer Dashboard](https://chrome.google.com/webstore/devconsole)
3. Click "New item", upload the zip from `extension/.output/`
4. Fill in the listing using the text from `doc/stores/listing.md`, the screenshot(s), and `doc/stores/store-icon-128.png`
5. Fill in Privacy tab with the privacy policy URL and permissions justifications from `listing.md`
6. Submit for review
7. Tell me the **Chrome Extension ID** (32-char string from the dashboard URL)

Also, before or after submission, set up the **Google Cloud OAuth credentials** (Phase 2b in the plan) so we have them ready for GitHub secrets.

Once you have the Chrome extension ID and OAuth credentials, I can update the code. We can do the Edge submission in parallel or after Chrome -- your call.
